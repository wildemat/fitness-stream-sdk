import Foundation

/// Delegate protocol for SDK events.
public protocol FitnessStreamDelegate: AnyObject {
    func engine(_ engine: FitnessStreamEngine, didCollect snapshot: MetricSnapshot)
    func engine(_ engine: FitnessStreamEngine, didStreamTo endpoint: StreamEndpoint, statusCode: Int)
    func engine(_ engine: FitnessStreamEngine, didFailWith error: Error)
    func engine(_ engine: FitnessStreamEngine, didChangeState state: StreamState)
}

/// Default empty implementations so adopters only need to implement what they care about.
public extension FitnessStreamDelegate {
    func engine(_ engine: FitnessStreamEngine, didCollect snapshot: MetricSnapshot) {}
    func engine(_ engine: FitnessStreamEngine, didStreamTo endpoint: StreamEndpoint, statusCode: Int) {}
    func engine(_ engine: FitnessStreamEngine, didFailWith error: Error) {}
    func engine(_ engine: FitnessStreamEngine, didChangeState state: StreamState) {}
}
