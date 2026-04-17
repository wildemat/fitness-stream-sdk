import Foundation

/// Describes a single metric and how it's sourced.
public struct MetricDescriptor: Codable, Hashable, Sendable {
    public let identifier: String
    public let source: MetricSource
    public let valueType: ValueType

    public init(identifier: String, source: MetricSource, valueType: ValueType) {
        self.identifier = identifier
        self.source = source
        self.valueType = valueType
    }
}

/// Where a metric's value comes from.
public enum MetricSource: Codable, Hashable, Sendable {
    case healthKit(hkIdentifier: String, unit: String, aggregation: Aggregation)
    case computed
    case location
    case custom
}

/// How a cumulative HK metric is aggregated.
public enum Aggregation: String, Codable, Sendable {
    case latest
    case cumulative
    case average
}

/// The shape of a metric value.
public enum ValueType: String, Codable, Sendable {
    case double
    case int
    case string
    case bool
    case object
}
