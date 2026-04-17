import Foundation
import os.log

/// POST-based HTTP transport. Sends metric snapshots as flat JSON matching
/// the legacy WorkoutMetrics wire format for backward compatibility.
public final class HTTPPostTransport: StreamTransport {

    private static let log = Logger(subsystem: "FitnessStreamSDK", category: "HTTPPostTransport")

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    public init() {}

    public func send(
        _ snapshot: MetricSnapshot,
        to endpoint: StreamEndpoint,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = endpoint.apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let body: Data
        do {
            body = try snapshot.encodeFlatJSON()
        } catch {
            Self.log.error("Failed to encode snapshot: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        request.httpBody = body

        session.dataTask(with: request) { _, response, error in
            if let error {
                Self.log.error("POST failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200...299).contains(statusCode) {
                Self.log.warning("POST returned \(statusCode)")
            }
            completion(.success(statusCode))
        }.resume()
    }
}
