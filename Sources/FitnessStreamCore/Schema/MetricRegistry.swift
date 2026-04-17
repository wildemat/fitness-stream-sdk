import Foundation
import os.log

/// Holds all metrics the host app has registered as available.
/// Two buckets: catalog metrics (HK / computed / location) and custom metrics.
public final class MetricRegistry: @unchecked Sendable {

    private static let log = Logger(subsystem: "FitnessStreamSDK", category: "MetricRegistry")

    /// Catalog metrics the app opted into.
    private(set) public var registeredCatalog: [MetricDescriptor] = []

    /// Custom metrics the app defined.
    private(set) public var registeredCustom: [MetricDescriptor] = []

    /// All registered identifiers (catalog + custom).
    public var allIdentifiers: Set<String> {
        Set(registeredCatalog.map(\.identifier) + registeredCustom.map(\.identifier))
    }

    /// All registered descriptors.
    public var allDescriptors: [MetricDescriptor] {
        registeredCatalog + registeredCustom
    }

    public init() {}

    /// Register catalog metrics by their SDK identifiers (e.g. "heart_rate", "pace_min_per_km").
    public func register(identifiers: [String]) {
        for id in identifiers {
            guard let descriptor = MetricCatalog.descriptor(for: id) else {
                Self.log.warning("Unknown catalog metric '\(id)' — skipping")
                continue
            }
            guard !registeredCatalog.contains(where: { $0.identifier == id }) else { continue }
            registeredCatalog.append(descriptor)
        }
    }

    /// Register a custom metric. Rejects identifiers that collide with the catalog.
    @discardableResult
    public func registerCustom(
        identifier: String,
        valueType: ValueType,
        schema: [String: ValueType]? = nil
    ) -> Bool {
        if MetricCatalog.allIdentifiers.contains(identifier) {
            Self.log.error("Cannot register custom metric '\(identifier)' — collides with catalog")
            return false
        }
        guard !registeredCustom.contains(where: { $0.identifier == identifier }) else {
            return true
        }
        let descriptor = MetricDescriptor(
            identifier: identifier,
            source: .custom,
            valueType: valueType
        )
        registeredCustom.append(descriptor)
        return true
    }

    /// Look up a descriptor by identifier (catalog first, then custom).
    public func descriptor(for identifier: String) -> MetricDescriptor? {
        registeredCatalog.first(where: { $0.identifier == identifier })
            ?? registeredCustom.first(where: { $0.identifier == identifier })
    }

    /// Check if an identifier is registered.
    public func isRegistered(_ identifier: String) -> Bool {
        allIdentifiers.contains(identifier)
    }

    public func reset() {
        registeredCatalog.removeAll()
        registeredCustom.removeAll()
    }
}
