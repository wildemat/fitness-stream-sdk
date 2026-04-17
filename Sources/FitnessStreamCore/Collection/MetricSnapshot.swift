import Foundation

/// A timestamped collection of metric values, keyed by SDK identifier.
/// Replaces the flat `WorkoutMetrics` struct with a dynamic dictionary.
public struct MetricSnapshot: Sendable {
    public let timestamp: Date
    public let elapsedSeconds: TimeInterval
    public let workoutType: String
    public let values: [String: MetricValue]

    public init(
        timestamp: Date,
        elapsedSeconds: TimeInterval,
        workoutType: String,
        values: [String: MetricValue]
    ) {
        self.timestamp = timestamp
        self.elapsedSeconds = elapsedSeconds
        self.workoutType = workoutType
        self.values = values
    }
}

// MARK: - Flat JSON encoding (backward compatible with WorkoutMetrics)

extension MetricSnapshot {

    /// Encodes the snapshot as flat JSON matching the legacy `WorkoutMetrics` wire format.
    /// Meta fields (timestamp, elapsed_seconds, workout_type) are top-level.
    /// All values are flattened into the same top-level object.
    public func encodeFlatJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(FlatSnapshot(snapshot: self))
    }
}

/// Internal wrapper that serializes MetricSnapshot to the flat wire format
/// expected by the current server and overlay code.
private struct FlatSnapshot: Encodable {
    let snapshot: MetricSnapshot

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        try container.encode(snapshot.workoutType, forKey: .init("workout_type"))
        try container.encode(snapshot.elapsedSeconds, forKey: .init("elapsed_seconds"))
        try container.encode(snapshot.timestamp, forKey: .init("timestamp"))

        for (key, value) in snapshot.values {
            try container.encode(value, forKey: .init(key))
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
