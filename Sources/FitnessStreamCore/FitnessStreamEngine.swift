import Foundation
import HealthKit
import os.log

/// Main entry point for the FitnessStream SDK.
/// Coordinates metric collection, schema negotiation, and streaming transport.
public final class FitnessStreamEngine {

    private static let log = Logger(subsystem: "FitnessStreamSDK", category: "Engine")

    // MARK: - Public properties

    public let healthStore: HKHealthStore
    public let registry = MetricRegistry()
    public weak var delegate: FitnessStreamDelegate?

    public private(set) var state: StreamState = .idle {
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

    public init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        self.collector = MetricCollector(healthStore: healthStore)
        self.customStore = CustomMetricStore(registry: registry)
    }

    // MARK: - Registration

    /// Register catalog metrics by their SDK identifiers.
    public func register(metrics identifiers: [String]) {
        registry.register(identifiers: identifiers)
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

    // MARK: - Configuration

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
                    if case SchemaFetchError.notFound = error {
                        let schema = SchemaResolver.resolveAll(registry: self.registry)
                        self.resolvedSchema = schema
                        self.state = .ready
                        completion(.fallback("Schema endpoint returned 404"))
                    } else {
                        let schema = SchemaResolver.resolveAll(registry: self.registry)
                        self.resolvedSchema = schema
                        self.state = .ready
                        completion(.fallback(error.localizedDescription))
                    }
                }
            }
        }
    }

    /// Configure an endpoint directly without schema negotiation.
    /// Streams all registered metrics.
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

    /// Pause streaming (stops the transport timer but keeps collecting).
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

    // MARK: - Tick (called externally by the host app's timer)

    /// Build a snapshot from all sources and optionally stream it.
    /// The host app calls this on its own 1-second timer.
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
        var values: [String: MetricValue] = [:]

        // HK values
        let hkValues = collector.currentValues()
        for (key, value) in hkValues where resolvedIds.contains(key) {
            values[key] = value
        }

        // Location values
        let locationValues = locationCollector.currentValues()
        for (key, value) in locationValues where resolvedIds.contains(key) {
            values[key] = value
        }

        // Computed values
        let computed = computedEngine.compute(
            rawValues: values,
            elapsedSeconds: elapsedSeconds,
            resolvedIdentifiers: resolvedIds
        )
        values.merge(computed) { _, new in new }

        // Custom values
        let customValues = customStore.currentValues()
        for (key, value) in customValues where resolvedIds.contains(key) {
            values[key] = value
        }

        let snapshot = MetricSnapshot(
            timestamp: Date(),
            elapsedSeconds: elapsedSeconds,
            workoutType: workoutType,
            values: values
        )

        delegate?.engine(self, didCollect: snapshot)

        // Stream if enough time has passed
        if state == .streaming, let endpoint {
            let now = Date()
            if now.timeIntervalSince(lastStreamTime) >= endpoint.frequency {
                sendSnapshot(snapshot)
                lastStreamTime = now
            }
        }

        return snapshot
    }

    // MARK: - Transport

    /// Set a custom transport (for testing or alternate protocols).
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

// MARK: - Configuration result

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
