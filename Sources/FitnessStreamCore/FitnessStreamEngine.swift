import Foundation
import HealthKit
import os.log

/// Main entry point for the FitnessStream SDK.
/// Coordinates metric collection, schema negotiation, and streaming transport.
public final class FitnessStreamEngine: ObservableObject {

    private static let log = Logger(subsystem: "FitnessStreamSDK", category: "Engine")

    // MARK: - Public properties

    public let healthStore: HKHealthStore
    public let registry = MetricRegistry()
    public let configuration: StreamConfiguration
    public weak var delegate: FitnessStreamDelegate?

    @Published public private(set) var state: StreamState = .idle {
        didSet {
            delegate?.engine(self, didChangeState: state)
        }
    }

    public private(set) var endpoint: StreamEndpoint?
    public private(set) var resolvedSchema: ResolvedSchema?

    // MARK: - Internal components

    public let collector: MetricCollector
    public let locationCollector = LocationCollector()
    public let customStore: CustomMetricStore
    private let computedEngine = ComputedMetricEngine()
    private let schemaFetcher = SchemaFetcher()
    private var transport: StreamTransport = HTTPPostTransport()

    private var streamTimer: Timer?
    private var lastStreamTime: Date = .distantPast
    private var workoutType: String = ""
    private var startDate: Date?

    // MARK: - Init

    public init(healthStore: HKHealthStore, configuration: StreamConfiguration? = nil) {
        self.healthStore = healthStore
        self.configuration = configuration ?? StreamConfiguration()
        self.collector = MetricCollector(healthStore: healthStore)
        self.customStore = CustomMetricStore(registry: registry)
    }

    // MARK: - Registration

    /// Register catalog metrics by their SDK identifiers.
    public func register(metrics identifiers: [String]) {
        registry.register(identifiers: identifiers)
        configuration.initializeIfEmpty(identifiers: identifiers)
    }

    /// Register a custom metric.
    @discardableResult
    public func registerCustom(
        identifier: String,
        valueType: ValueType,
        schema: [String: ValueType]? = nil
    ) -> Bool {
        registry.registerCustom(identifier: identifier, valueType: valueType, schema: schema)
    }

    // MARK: - Custom values

    /// Push a custom metric value during a workout.
    public func setCustomValue(_ value: MetricValue, for identifier: String) {
        customStore.setValue(value, for: identifier)
    }

    /// Clear a custom metric value.
    public func clearCustomValue(for identifier: String) {
        customStore.clearValue(for: identifier)
    }

    // MARK: - Endpoint management

    /// Save an endpoint URL and API key. Resets metric toggles to the default
    /// app-registered schema.
    public func saveEndpoint(url: String, apiKey: String?) {
        configuration.savedEndpointURL = url
        configuration.savedAPIKey = apiKey
        configuration.resetToDefaults(identifiers: registry.allDescriptors.map(\.identifier))

        if let parsed = URL(string: url) {
            self.endpoint = StreamEndpoint(
                url: parsed,
                apiKey: apiKey,
                frequency: configuration.frequency
            )
            let schema = SchemaResolver.resolveAll(registry: registry)
            self.resolvedSchema = schema
            state = .ready
        }
    }

    /// Rebuild the active endpoint from current configuration.
    public func refreshEndpoint() {
        guard let urlString = configuration.savedEndpointURL,
              let url = URL(string: urlString) else {
            self.endpoint = nil
            return
        }
        self.endpoint = StreamEndpoint(
            url: url,
            apiKey: configuration.savedAPIKey,
            frequency: configuration.frequency
        )
        let schema = SchemaResolver.resolveAll(registry: registry)
        self.resolvedSchema = schema
        state = .ready
    }

    // MARK: - Verify connection + auto schema fetch

    /// Two-step verification: health check then auto schema fetch.
    ///
    /// 1. POST ping to the endpoint URL
    /// 2. If succeeds, GET `{url}/schema`
    /// 3. Merge resolved schema into toggle list (additive only)
    public func verifyConnection(completion: @escaping (VerifyResult) -> Void) {
        guard let urlString = configuration.savedEndpointURL,
              let url = URL(string: urlString) else {
            completion(.connectionFailed(
                VerifyError.noEndpoint
            ))
            return
        }

        let apiKey = configuration.savedAPIKey

        // Step 1: Health check (POST ping)
        healthCheck(url: url, apiKey: apiKey) { [weak self] pingResult in
            DispatchQueue.main.async {
                guard let self else { return }
                switch pingResult {
                case .failure(let error):
                    completion(.connectionFailed(error))

                case .success(let statusCode):
                    if !(200...299).contains(statusCode) {
                        completion(.connectionFailed(
                            VerifyError.httpStatus(statusCode)
                        ))
                        return
                    }

                    // Step 2: Auto schema fetch (GET {url}/schema)
                    self.fetchAndMergeSchema(
                        baseURL: url,
                        apiKey: apiKey,
                        completion: completion
                    )
                }
            }
        }
    }

    private func healthCheck(
        url: URL,
        apiKey: String?,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        request.httpBody = Data("{\"ping\":true}".utf8)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(.success(status))
        }.resume()
    }

    private func fetchAndMergeSchema(
        baseURL: URL,
        apiKey: String?,
        completion: @escaping (VerifyResult) -> Void
    ) {
        let schemaURL: URL
        if #available(iOS 16.0, *) {
            schemaURL = baseURL.appending(path: "schema")
        } else {
            schemaURL = baseURL.appendingPathComponent("schema")
        }

        schemaFetcher.fetch(from: schemaURL, apiKey: apiKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .failure:
                    completion(.connectedNoSchema)

                case .success(let definition):
                    let resolved = SchemaResolver.resolve(
                        schema: definition,
                        registry: self.registry
                    )
                    self.resolvedSchema = resolved

                    let defaultIds = Set(self.registry.allDescriptors.map(\.identifier))

                    let (newToggles, newRemoteIds, didChange) = SchemaResolver.mergeIntoToggles(
                        resolvedSchema: resolved,
                        currentToggles: self.configuration.metricToggles,
                        defaultIdentifiers: defaultIds,
                        previousRemoteIdentifiers: self.configuration.remoteSchemaIdentifiers
                    )

                    self.configuration.metricToggles = newToggles
                    self.configuration.remoteSchemaIdentifiers = newRemoteIds

                    if didChange {
                        completion(.connectedSchemaApplied)
                    } else {
                        completion(.connectedSchemaUnchanged)
                    }
                }
            }
        }
    }

    // MARK: - Configuration (legacy compat)

    /// Configure a streaming endpoint. Triggers schema negotiation if schemaURL is set.
    public func configure(
        endpoint: StreamEndpoint,
        completion: @escaping (ConfigureResult) -> Void
    ) {
        self.endpoint = endpoint
        state = .configuring

        guard let schemaURL = endpoint.schemaURL else {
            let schema = SchemaResolver.resolveAll(registry: registry)
            self.resolvedSchema = schema
            state = .ready
            completion(.fallback("No schema URL configured"))
            return
        }

        schemaFetcher.fetch(from: schemaURL, apiKey: endpoint.apiKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let definition):
                    let resolved = SchemaResolver.resolve(schema: definition, registry: self.registry)
                    self.resolvedSchema = resolved

                    if !resolved.isFullyResolved {
                        let missingRequired = resolved.dropped.filter(\.wasRequired)
                        if !missingRequired.isEmpty {
                            self.state = .idle
                            completion(.failure(
                                SchemaConfigError.requiredMetricsMissing(
                                    missingRequired.map(\.identifier)
                                )
                            ))
                            return
                        }
                    }

                    self.state = .ready
                    completion(.resolved(resolved))

                case .failure(let error):
                    let schema = SchemaResolver.resolveAll(registry: self.registry)
                    self.resolvedSchema = schema
                    self.state = .ready
                    completion(.fallback(error.localizedDescription))
                }
            }
        }
    }

    /// Configure an endpoint directly without schema negotiation.
    public func configureSimple(endpoint: StreamEndpoint) {
        self.endpoint = endpoint
        let schema = SchemaResolver.resolveAll(registry: registry)
        self.resolvedSchema = schema
        state = .ready
    }

    // MARK: - Streaming lifecycle

    /// Start collecting and streaming metrics.
    public func startStreaming(workoutType: String, startDate: Date) {
        guard let schema = resolvedSchema else {
            Self.log.error("Cannot start streaming: no resolved schema. Call configure() first.")
            return
        }

        self.workoutType = workoutType
        self.startDate = startDate

        collector.start(schema: schema, from: startDate)

        if schema.resolvedIdentifiers.contains(where: { ["latitude", "longitude", "elevation_meters"].contains($0) }) {
            locationCollector.requestAuthorization()
            locationCollector.start()
        }

        state = .streaming
    }

    /// Pause streaming.
    public func pauseStreaming() {
        streamTimer?.invalidate()
        streamTimer = nil
        locationCollector.stop()
        state = .paused
    }

    /// Resume streaming after a pause.
    public func resumeStreaming() {
        if let schema = resolvedSchema,
           schema.resolvedIdentifiers.contains(where: { ["latitude", "longitude", "elevation_meters"].contains($0) }) {
            locationCollector.start()
        }
        state = .streaming
    }

    /// Stop all collection and streaming.
    public func stopStreaming() {
        streamTimer?.invalidate()
        streamTimer = nil
        collector.stop()
        locationCollector.stop()
        customStore.clearAll()
        state = .idle
    }

    // MARK: - Tick

    /// Build a snapshot from all sources and optionally stream it.
    /// Values are filtered through `configuration.enabledIdentifiers` — only
    /// metrics the user has toggled on are included in the payload.
    public func tick(elapsedSeconds: TimeInterval) -> MetricSnapshot {
        guard let schema = resolvedSchema else {
            return MetricSnapshot(
                timestamp: Date(),
                elapsedSeconds: elapsedSeconds,
                workoutType: workoutType,
                values: [:]
            )
        }

        let resolvedIds = schema.resolvedIdentifiers
        let enabledIds = configuration.enabledIdentifiers
        let activeIds = resolvedIds.intersection(enabledIds)

        var values: [String: MetricValue] = [:]

        let hkValues = collector.currentValues()
        for (key, value) in hkValues where activeIds.contains(key) {
            values[key] = value
        }

        let locationValues = locationCollector.currentValues()
        for (key, value) in locationValues where activeIds.contains(key) {
            values[key] = value
        }

        let computed = computedEngine.compute(
            rawValues: values,
            elapsedSeconds: elapsedSeconds,
            resolvedIdentifiers: activeIds
        )
        values.merge(computed) { _, new in new }

        let customValues = customStore.currentValues()
        for (key, value) in customValues where activeIds.contains(key) {
            values[key] = value
        }

        let snapshot = MetricSnapshot(
            timestamp: Date(),
            elapsedSeconds: elapsedSeconds,
            workoutType: workoutType,
            values: values
        )

        delegate?.engine(self, didCollect: snapshot)

        if state == .streaming,
           configuration.streamEnabled,
           let endpoint {
            let now = Date()
            if now.timeIntervalSince(lastStreamTime) >= endpoint.frequency {
                sendSnapshot(snapshot)
                lastStreamTime = now
            }
        }

        return snapshot
    }

    // MARK: - Transport

    public func setTransport(_ transport: StreamTransport) {
        self.transport = transport
    }

    private func sendSnapshot(_ snapshot: MetricSnapshot) {
        guard let endpoint else { return }
        transport.send(snapshot, to: endpoint) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let statusCode):
                    self.delegate?.engine(self, didStreamTo: endpoint, statusCode: statusCode)
                case .failure(let error):
                    self.delegate?.engine(self, didFailWith: error)
                }
            }
        }
    }

    /// Returns the HK types needed for authorization for the currently registered metrics.
    public var requiredHealthKitReadTypes: Set<HKObjectType> {
        MetricCollector.requiredReadTypes(for: registry.registeredCatalog)
    }

    /// Convenience: returns HK types needed for write authorization.
    public var requiredHealthKitShareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        types.insert(HKWorkoutType.workoutType())
        for descriptor in registry.registeredCatalog {
            guard case .healthKit(let hkId, _, let agg) = descriptor.source,
                  agg == .cumulative else { continue }
            let writeMap: [String: HKQuantityTypeIdentifier] = [
                "activeEnergyBurned": .activeEnergyBurned,
                "distanceWalkingRunning": .distanceWalkingRunning,
                "distanceCycling": .distanceCycling,
            ]
            if let typeId = writeMap[hkId] {
                types.insert(HKQuantityType(typeId))
            }
        }
        return types
    }
}

// MARK: - Verify result

public enum VerifyResult {
    case connectionFailed(Error)
    case connectedNoSchema
    case connectedSchemaApplied
    case connectedSchemaUnchanged
}

public enum VerifyError: Error, LocalizedError {
    case noEndpoint
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .noEndpoint: return "No endpoint URL saved"
        case .httpStatus(let code): return "HTTP \(code)"
        }
    }
}

// MARK: - Configuration result (legacy compat)

public enum ConfigureResult {
    case resolved(ResolvedSchema)
    case fallback(String)
    case failure(Error)
}

public enum SchemaConfigError: Error, LocalizedError {
    case requiredMetricsMissing([String])

    public var errorDescription: String? {
        switch self {
        case .requiredMetricsMissing(let ids):
            return "Required metrics missing: \(ids.joined(separator: ", "))"
        }
    }
}
