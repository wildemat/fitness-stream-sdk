import Foundation

/// A dynamically-typed metric value that serializes to its natural JSON type.
public indirect enum MetricValue: Sendable, Equatable {
    case double(Double)
    case int(Int)
    case string(String)
    case bool(Bool)
    case object([String: MetricValue])
}

// MARK: - Codable

extension MetricValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([String: MetricValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "MetricValue could not be decoded"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .string(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}
