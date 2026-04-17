import Foundation
import HealthKit
import os.log

/// Dynamically creates and manages HK anchored queries based on a resolved schema.
public final class MetricCollector {

    private static let log = Logger(subsystem: "FitnessStreamSDK", category: "MetricCollector")

    private let healthStore: HKHealthStore
    private var activeQueries: [String: HKAnchoredObjectQuery] = [:]
    private var startDate: Date?

    /// Current collected HK values, keyed by SDK identifier.
    private var collectedValues: [String: MetricValue] = [:]
    private let lock = NSLock()

    /// Tracks which fields are provided by the Watch, so phone queries skip them.
    public var watchProvidedMetrics: Set<String> = []

    public init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    /// Start HK queries for the given resolved schema.
    public func start(schema: ResolvedSchema, from date: Date) {
        self.startDate = date
        stop()

        for metric in schema.resolved {
            guard let descriptor = MetricCatalog.descriptor(for: metric.identifier) else { continue }
            guard case .healthKit(let hkId, let unitStr, let aggregation) = descriptor.source else { continue }

            guard let quantityType = hkQuantityType(for: hkId) else {
                Self.log.warning("Unknown HK quantity type: \(hkId)")
                continue
            }
            guard let unit = hkUnit(for: unitStr) else {
                Self.log.warning("Unknown HK unit: \(unitStr)")
                continue
            }

            let identifier = descriptor.identifier
            switch aggregation {
            case .latest:
                let query = makeLatestValueQuery(
                    identifier: identifier,
                    type: quantityType,
                    unit: unit,
                    startDate: date
                )
                activeQueries[identifier] = query

            case .cumulative:
                let query = makeCumulativeQuery(
                    identifier: identifier,
                    type: quantityType,
                    unit: unit,
                    startDate: date
                )
                activeQueries[identifier] = query

            case .average:
                let query = makeLatestValueQuery(
                    identifier: identifier,
                    type: quantityType,
                    unit: unit,
                    startDate: date
                )
                activeQueries[identifier] = query
            }
        }
    }

    /// Stop all active HK queries.
    public func stop() {
        for (_, query) in activeQueries {
            healthStore.stop(query)
        }
        activeQueries.removeAll()
    }

    /// Get current collected values (thread-safe snapshot).
    public func currentValues() -> [String: MetricValue] {
        lock.lock()
        defer { lock.unlock() }
        return collectedValues
    }

    /// Directly set a metric value (used for watch-provided metrics).
    public func setValue(_ value: MetricValue, for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        collectedValues[identifier] = value
    }

    /// Clear all collected values.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        collectedValues.removeAll()
        watchProvidedMetrics.removeAll()
    }

    // MARK: - HK Quantity Types

    private func hkQuantityType(for identifier: String) -> HKQuantityType? {
        var typeMap: [String: HKQuantityTypeIdentifier] = [
            "heartRate": .heartRate,
            "activeEnergyBurned": .activeEnergyBurned,
            "distanceWalkingRunning": .distanceWalkingRunning,
            "distanceCycling": .distanceCycling,
            "stepCount": .stepCount,
            "runningPower": .runningPower,
            "runningSpeed": .runningSpeed,
            "runningStrideLength": .runningStrideLength,
            "runningVerticalOscillation": .runningVerticalOscillation,
            "runningGroundContactTime": .runningGroundContactTime,
            "swimmingStrokeCount": .swimmingStrokeCount,
            "distanceSwimming": .distanceSwimming,
            "vo2Max": .vo2Max,
            "respiratoryRate": .respiratoryRate,
        ]
        if #available(iOS 17.0, watchOS 10.0, *) {
            typeMap["cyclingCadence"] = .cyclingCadence
            typeMap["cyclingPower"] = .cyclingPower
            typeMap["cyclingSpeed"] = .cyclingSpeed
        }
        guard let typeId = typeMap[identifier] else { return nil }
        return HKQuantityType(typeId)
    }

    private func hkUnit(for unitStr: String) -> HKUnit? {
        switch unitStr {
        case "count/min": return .count().unitDivided(by: .minute())
        case "kcal": return .kilocalorie()
        case "m": return .meter()
        case "count": return .count()
        case "W": return .watt()
        case "m/s": return .meter().unitDivided(by: .second())
        case "cm": return .meterUnit(with: .centi)
        case "ms": return .secondUnit(with: .milli)
        case "mL/kg/min":
            return .literUnit(with: .milli)
                .unitDivided(by: .gramUnit(with: .kilo))
                .unitDivided(by: .minute())
        default: return nil
        }
    }

    // MARK: - Query Builders

    private func makeLatestValueQuery(
        identifier: String,
        type: HKQuantityType,
        unit: HKUnit,
        startDate: Date
    ) -> HKAnchoredObjectQuery {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate, end: nil, options: .strictStartDate)

        let handler: (String, [HKSample]?) -> Void = { [weak self] id, samples in
            guard let self,
                  self.watchProvidedMetrics.contains(id) != true,
                  let quantitySamples = samples as? [HKQuantitySample],
                  let latest = quantitySamples.last else { return }
            let value = latest.quantity.doubleValue(for: unit)
            DispatchQueue.main.async {
                self.lock.lock()
                self.collectedValues[id] = .double(value)
                self.lock.unlock()
            }
        }

        let query = HKAnchoredObjectQuery(
            type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in
            handler(identifier, samples)
        }
        query.updateHandler = { _, samples, _, _, _ in
            handler(identifier, samples)
        }
        healthStore.execute(query)
        return query
    }

    private func makeCumulativeQuery(
        identifier: String,
        type: HKQuantityType,
        unit: HKUnit,
        startDate: Date
    ) -> HKAnchoredObjectQuery {
        var runningTotal: Double = 0
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate, end: nil, options: .strictStartDate)

        let accumulate: (String, [HKSample]?) -> Void = { [weak self] id, samples in
            guard let self,
                  self.watchProvidedMetrics.contains(id) != true,
                  let quantitySamples = samples as? [HKQuantitySample],
                  !quantitySamples.isEmpty else { return }
            let batchSum = quantitySamples.reduce(0.0) {
                $0 + $1.quantity.doubleValue(for: unit)
            }
            runningTotal += batchSum
            let total = runningTotal
            let useInt = (unit == .count())
            DispatchQueue.main.async {
                self.lock.lock()
                self.collectedValues[id] = useInt ? .int(Int(total)) : .double(total)
                self.lock.unlock()
            }
        }

        let query = HKAnchoredObjectQuery(
            type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in
            accumulate(identifier, samples)
        }
        query.updateHandler = { _, samples, _, _, _ in
            accumulate(identifier, samples)
        }
        healthStore.execute(query)
        return query
    }

    /// Returns the HK types needed for authorization based on registered metrics.
    public static func requiredReadTypes(for descriptors: [MetricDescriptor]) -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for descriptor in descriptors {
            guard case .healthKit(let hkId, _, _) = descriptor.source else { continue }
            var typeMap: [String: HKQuantityTypeIdentifier] = [
                "heartRate": .heartRate,
                "activeEnergyBurned": .activeEnergyBurned,
                "distanceWalkingRunning": .distanceWalkingRunning,
                "distanceCycling": .distanceCycling,
                "stepCount": .stepCount,
                "runningPower": .runningPower,
                "runningSpeed": .runningSpeed,
                "runningStrideLength": .runningStrideLength,
                "runningVerticalOscillation": .runningVerticalOscillation,
                "runningGroundContactTime": .runningGroundContactTime,
                "swimmingStrokeCount": .swimmingStrokeCount,
                "distanceSwimming": .distanceSwimming,
                "vo2Max": .vo2Max,
                "respiratoryRate": .respiratoryRate,
            ]
            if #available(iOS 17.0, watchOS 10.0, *) {
                typeMap["cyclingCadence"] = .cyclingCadence
                typeMap["cyclingPower"] = .cyclingPower
                typeMap["cyclingSpeed"] = .cyclingSpeed
            }
            if let typeId = typeMap[hkId] {
                types.insert(HKQuantityType(typeId))
            }
        }
        return types
    }
}
