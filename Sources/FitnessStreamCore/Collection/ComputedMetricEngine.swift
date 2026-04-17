import Foundation

/// Derives computed metric values from raw collected data on each tick.
public final class ComputedMetricEngine {

    public init() {}

    /// Compute derived values from current raw metrics.
    /// - Parameters:
    ///   - rawValues: Current metric values collected from HK and location.
    ///   - elapsedSeconds: Workout elapsed time.
    ///   - resolvedIdentifiers: Set of metric identifiers in the resolved schema.
    /// - Returns: Dictionary of computed metric values to merge into the snapshot.
    public func compute(
        rawValues: [String: MetricValue],
        elapsedSeconds: TimeInterval,
        resolvedIdentifiers: Set<String>
    ) -> [String: MetricValue] {
        var computed: [String: MetricValue] = [:]

        if resolvedIdentifiers.contains("heart_rate_zone"),
           case .double(let bpm)? = rawValues["heart_rate"] {
            computed["heart_rate_zone"] = .int(ComputedMetrics.heartRateZone(bpm: bpm))
        }

        if resolvedIdentifiers.contains("pace_min_per_km"),
           case .double(let distance)? = rawValues["distance_meters"] {
            if let pace = ComputedMetrics.paceMinPerKm(
                elapsedSeconds: elapsedSeconds,
                distanceMeters: distance
            ) {
                computed["pace_min_per_km"] = .double(pace)
            }
        }

        return computed
    }
}
