import Foundation

/// Protocol for pluggable transports. Implementations encode and send snapshots.
public protocol StreamTransport: AnyObject {
    /// Send a metric snapshot to the endpoint.
    /// - Parameters:
    ///   - snapshot: The snapshot to send.
    ///   - endpoint: The configured endpoint.
    ///   - completion: Called with the HTTP status code or error.
    func send(
        _ snapshot: MetricSnapshot,
        to endpoint: StreamEndpoint,
        completion: @escaping (Result<Int, Error>) -> Void
    )
}
