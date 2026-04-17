import Foundation
import os.log

/// Fetches a `SchemaDefinition` from an endpoint's schema URL.
public final class SchemaFetcher {

    private static let log = Logger(subsystem: "FitnessStreamSDK", category: "SchemaFetcher")

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        return URLSession(configuration: config)
    }()

    public init() {}

    /// Fetch a schema definition from the given URL.
    public func fetch(
        from url: URL,
        apiKey: String?,
        completion: @escaping (Result<SchemaDefinition, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        session.dataTask(with: request) { data, response, error in
            if let error {
                Self.log.error("Schema fetch failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 404 {
                completion(.failure(SchemaFetchError.notFound))
                return
            }

            guard let data, (200...299).contains(statusCode) else {
                completion(.failure(SchemaFetchError.httpError(statusCode)))
                return
            }

            do {
                let decoder = JSONDecoder()
                let schema = try decoder.decode(SchemaDefinition.self, from: data)
                completion(.success(schema))
            } catch {
                Self.log.error("Schema decode failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }

    /// Send schema acknowledgment to the endpoint.
    public func acknowledge(
        resolvedSchema: ResolvedSchema,
        to url: URL,
        apiKey: String?,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        var ackURL = url
        ackURL.appendPathComponent("schema/ack")

        var request = URLRequest(url: ackURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let ack = SchemaAck(
            schemaVersion: resolvedSchema.schemaVersion,
            status: resolvedSchema.isFullyResolved ? "resolved" : "partial",
            resolvedMetrics: resolvedSchema.resolved,
            droppedMetrics: resolvedSchema.dropped,
            sdkVersion: "0.1.0"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try? encoder.encode(ack)

        session.dataTask(with: request) { _, _, error in
            if let error {
                completion?(.failure(error))
            } else {
                completion?(.success(()))
            }
        }.resume()
    }
}

public enum SchemaFetchError: Error, LocalizedError {
    case notFound
    case httpError(Int)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "Schema endpoint returned 404"
        case .httpError(let code): return "Schema endpoint returned HTTP \(code)"
        }
    }
}

private struct SchemaAck: Encodable {
    let schemaVersion: String
    let status: String
    let resolvedMetrics: [ResolvedMetric]
    let droppedMetrics: [DroppedMetric]
    let sdkVersion: String
}
