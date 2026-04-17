import Foundation

/// Configuration for a streaming endpoint.
public struct StreamEndpoint: Sendable {
    public let url: URL
    public let schemaURL: URL?
    public let apiKey: String?
    public let frequency: TimeInterval

    public init(
        url: URL,
        schemaURL: URL? = nil,
        apiKey: String? = nil,
        frequency: TimeInterval = 5.0
    ) {
        self.url = url
        self.schemaURL = schemaURL
        self.apiKey = apiKey
        self.frequency = max(1, min(30, frequency))
    }
}
