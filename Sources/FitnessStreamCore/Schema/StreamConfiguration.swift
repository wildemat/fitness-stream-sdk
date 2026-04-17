import Foundation
import os.log

/// Persisted configuration state for streaming. This is the single source of truth
/// for the endpoint, metric toggles, and user preferences.
///
/// The toggle list represents what the user has chosen to send. It starts as the
/// app's default registered schema and is updated (additively) by schema negotiation.
/// Toggle values are never overridden by schema merges — only the user flips toggles.
public final class StreamConfiguration: ObservableObject {

    private static let log = Logger(subsystem: "FitnessStreamSDK", category: "StreamConfiguration")

    private let defaults: UserDefaults
    private let prefix: String

    // MARK: - Published state

    @Published public var savedEndpointURL: String? {
        didSet { defaults.set(savedEndpointURL, forKey: key("endpointURL")) }
    }

    @Published public var savedAPIKey: String? {
        didSet { defaults.set(savedAPIKey, forKey: key("apiKey")) }
    }

    @Published public var frequency: TimeInterval {
        didSet { defaults.set(max(1, min(30, frequency)), forKey: key("frequency")) }
    }

    @Published public var streamEnabled: Bool {
        didSet { defaults.set(streamEnabled, forKey: key("streamEnabled")) }
    }

    /// Metric toggle list — keyed by identifier, value = whether the user wants it sent.
    /// This is the final source of truth for what goes over the wire.
    @Published public var metricToggles: [String: Bool] {
        didSet { persistToggles() }
    }

    /// Identifiers that were added by a remote schema fetch (vs. default app registration).
    @Published public var remoteSchemaIdentifiers: Set<String> {
        didSet {
            defaults.set(Array(remoteSchemaIdentifiers), forKey: key("remoteSchemaIds"))
        }
    }

    /// Host app can override the default friendly names from MetricCatalog.
    public var friendlyNameOverrides: [String: String] = [:]

    // MARK: - Init

    /// - Parameters:
    ///   - suiteName: UserDefaults suite name. Pass nil for standard defaults.
    ///   - keyPrefix: Prefix for all persisted keys. Allows multiple SDK instances.
    public init(suiteName: String? = nil, keyPrefix: String = "com.fitnessstream.sdk") {
        self.defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.prefix = keyPrefix

        self.savedEndpointURL = defaults.string(forKey: "\(keyPrefix).endpointURL")
        self.savedAPIKey = defaults.string(forKey: "\(keyPrefix).apiKey")

        let freq = defaults.double(forKey: "\(keyPrefix).frequency")
        self.frequency = freq >= 1 ? freq : 5.0

        if defaults.object(forKey: "\(keyPrefix).streamEnabled") == nil {
            self.streamEnabled = true
        } else {
            self.streamEnabled = defaults.bool(forKey: "\(keyPrefix).streamEnabled")
        }

        if let data = defaults.data(forKey: "\(keyPrefix).metricToggles"),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            self.metricToggles = decoded
        } else {
            self.metricToggles = [:]
        }

        if let arr = defaults.stringArray(forKey: "\(keyPrefix).remoteSchemaIds") {
            self.remoteSchemaIdentifiers = Set(arr)
        } else {
            self.remoteSchemaIdentifiers = []
        }
    }

    private func key(_ name: String) -> String { "\(prefix).\(name)" }

    private func persistToggles() {
        if let data = try? JSONEncoder().encode(metricToggles) {
            defaults.set(data, forKey: key("metricToggles"))
        }
    }

    // MARK: - Default schema from app registration

    /// Reset the toggle list to the default app-registered schema with all metrics on.
    /// Called when a new endpoint is saved.
    public func resetToDefaults(identifiers: [String]) {
        var toggles: [String: Bool] = [:]
        for id in identifiers {
            toggles[id] = true
        }
        metricToggles = toggles
        remoteSchemaIdentifiers = []
        Self.log.info("Reset toggles to \(identifiers.count) default metrics")
    }

    /// Initialize toggles from app registration if no toggles are persisted yet.
    /// Does nothing if toggles are already populated.
    public func initializeIfEmpty(identifiers: [String]) {
        guard metricToggles.isEmpty else { return }
        resetToDefaults(identifiers: identifiers)
    }

    // MARK: - Friendly names

    /// Resolve the display name for a metric identifier.
    /// Priority: host app overrides > catalog defaults > identifier as-is.
    public func friendlyName(for identifier: String) -> String {
        friendlyNameOverrides[identifier]
            ?? MetricCatalog.friendlyNames[identifier]
            ?? identifier.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Active identifiers

    /// The set of identifiers the user has toggled on — what actually gets streamed.
    public var enabledIdentifiers: Set<String> {
        Set(metricToggles.filter { $0.value }.map(\.key))
    }

    /// Whether there is a valid saved endpoint to stream to.
    public var hasEndpoint: Bool {
        guard let url = savedEndpointURL, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }
}
