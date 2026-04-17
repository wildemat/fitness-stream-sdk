import Foundation

/// The schema an endpoint serves at `GET /schema`, defining which metrics it wants.
public struct SchemaDefinition: Codable, Sendable {
    public let schemaVersion: String
    public let name: String
    public let description: String?
    public let metrics: [MetricRequest]
    public let metaFields: [String]?

    public init(
        schemaVersion: String = "1.0",
        name: String,
        description: String? = nil,
        metrics: [MetricRequest],
        metaFields: [String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.description = description
        self.metrics = metrics
        self.metaFields = metaFields
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case name
        case description
        case metrics
        case metaFields = "meta_fields"
    }
}

/// A single metric requested by an endpoint schema.
public struct MetricRequest: Codable, Sendable {
    public let identifier: String
    public let required: Bool?
    public let valueType: String?

    public init(identifier: String, required: Bool? = nil, valueType: String? = nil) {
        self.identifier = identifier
        self.required = required
        self.valueType = valueType
    }

    enum CodingKeys: String, CodingKey {
        case identifier
        case required
        case valueType = "value_type"
    }
}
