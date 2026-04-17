import Foundation

/// The result of schema negotiation: which metrics are resolved and which were dropped.
public struct ResolvedSchema: Sendable {
    public let schemaVersion: String
    public let name: String

    /// Metrics that matched the registry and will be collected/streamed.
    public let resolved: [ResolvedMetric]

    /// Metrics the endpoint requested but the app can't provide.
    public let dropped: [DroppedMetric]

    public init(
        schemaVersion: String,
        name: String,
        resolved: [ResolvedMetric],
        dropped: [DroppedMetric]
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.resolved = resolved
        self.dropped = dropped
    }

    public var resolvedIdentifiers: Set<String> {
        Set(resolved.map(\.identifier))
    }

    /// Whether all required metrics were resolved.
    public var isFullyResolved: Bool {
        dropped.allSatisfy { !$0.wasRequired }
    }
}

public struct ResolvedMetric: Codable, Sendable {
    public let identifier: String
    public let source: String

    public init(identifier: String, source: String) {
        self.identifier = identifier
        self.source = source
    }
}

public struct DroppedMetric: Codable, Sendable {
    public let identifier: String
    public let reason: String
    public let wasRequired: Bool

    public init(identifier: String, reason: String, wasRequired: Bool) {
        self.identifier = identifier
        self.reason = reason
        self.wasRequired = wasRequired
    }
}
