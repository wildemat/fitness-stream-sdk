import Foundation
import os.log

/// Thread-safe store for app-pushed custom metric values.
/// Merged into each MetricSnapshot on every tick.
public final class CustomMetricStore: @unchecked Sendable {

    private static let log = Logger(subsystem: "FitnessStreamSDK", category: "CustomMetricStore")

    private let lock = NSLock()
    private var storage: [String: MetricValue] = [:]
    private let registry: MetricRegistry

    public init(registry: MetricRegistry) {
        self.registry = registry
    }

    /// Set a custom metric value. No-op with warning if identifier isn't registered.
    public func setValue(_ value: MetricValue, for identifier: String) {
        guard registry.registeredCustom.contains(where: { $0.identifier == identifier }) else {
            Self.log.warning("setCustomValue for unregistered identifier '\(identifier)' — ignored")
            return
        }
        lock.lock()
        defer { lock.unlock() }
        storage[identifier] = value
    }

    /// Clear a specific custom metric value.
    public func clearValue(for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: identifier)
    }

    /// Get a snapshot of all current custom values.
    public func currentValues() -> [String: MetricValue] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Clear all custom values.
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
