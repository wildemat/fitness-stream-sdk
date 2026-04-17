import Foundation

/// Static, exhaustive list of HealthKit workout metrics the SDK can auto-collect,
/// plus computed and location metrics.
public enum MetricCatalog {

    /// All known HK quantity-type metrics available during a live workout session.
    public static let healthKitMetrics: [MetricDescriptor] = [
        MetricDescriptor(
            identifier: "heart_rate",
            source: .healthKit(hkIdentifier: "heartRate", unit: "count/min", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "active_energy_kcal",
            source: .healthKit(hkIdentifier: "activeEnergyBurned", unit: "kcal", aggregation: .cumulative),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "distance_meters",
            source: .healthKit(hkIdentifier: "distanceWalkingRunning", unit: "m", aggregation: .cumulative),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "distance_cycling_meters",
            source: .healthKit(hkIdentifier: "distanceCycling", unit: "m", aggregation: .cumulative),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "step_count",
            source: .healthKit(hkIdentifier: "stepCount", unit: "count", aggregation: .cumulative),
            valueType: .int
        ),
        MetricDescriptor(
            identifier: "cadence",
            source: .healthKit(hkIdentifier: "cyclingCadence", unit: "count/min", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "cycling_power",
            source: .healthKit(hkIdentifier: "cyclingPower", unit: "W", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "cycling_speed",
            source: .healthKit(hkIdentifier: "cyclingSpeed", unit: "m/s", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "running_power",
            source: .healthKit(hkIdentifier: "runningPower", unit: "W", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "running_speed",
            source: .healthKit(hkIdentifier: "runningSpeed", unit: "m/s", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "running_stride_length",
            source: .healthKit(hkIdentifier: "runningStrideLength", unit: "m", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "running_vertical_oscillation",
            source: .healthKit(hkIdentifier: "runningVerticalOscillation", unit: "cm", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "running_ground_contact_time",
            source: .healthKit(hkIdentifier: "runningGroundContactTime", unit: "ms", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "swimming_stroke_count",
            source: .healthKit(hkIdentifier: "swimmingStrokeCount", unit: "count", aggregation: .cumulative),
            valueType: .int
        ),
        MetricDescriptor(
            identifier: "distance_swimming",
            source: .healthKit(hkIdentifier: "distanceSwimming", unit: "m", aggregation: .cumulative),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "vo2_max",
            source: .healthKit(hkIdentifier: "vo2Max", unit: "mL/kg/min", aggregation: .latest),
            valueType: .double
        ),
        MetricDescriptor(
            identifier: "respiratory_rate",
            source: .healthKit(hkIdentifier: "respiratoryRate", unit: "count/min", aggregation: .latest),
            valueType: .double
        ),
    ]

    /// Computed / derived metrics the SDK can also provide.
    public static let computedMetrics: [MetricDescriptor] = [
        MetricDescriptor(identifier: "pace_min_per_km", source: .computed, valueType: .double),
        MetricDescriptor(identifier: "heart_rate_zone", source: .computed, valueType: .int),
    ]

    /// Location-sourced metrics.
    public static let locationMetrics: [MetricDescriptor] = [
        MetricDescriptor(identifier: "latitude", source: .location, valueType: .double),
        MetricDescriptor(identifier: "longitude", source: .location, valueType: .double),
        MetricDescriptor(identifier: "elevation_meters", source: .location, valueType: .double),
    ]

    /// All catalog entries (HK + computed + location).
    public static let all: [MetricDescriptor] = healthKitMetrics + computedMetrics + locationMetrics

    /// Quick lookup by identifier.
    public static func descriptor(for identifier: String) -> MetricDescriptor? {
        all.first { $0.identifier == identifier }
    }

    /// Set of all catalog identifiers, for collision checks.
    public static let allIdentifiers: Set<String> = Set(all.map(\.identifier))
}
