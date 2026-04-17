import Foundation

/// The streaming state of the engine.
public enum StreamState: Sendable {
    case idle
    case configuring
    case ready
    case streaming
    case paused
    case error(Error)
}

extension StreamState: Equatable {
    public static func == (lhs: StreamState, rhs: StreamState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.configuring, .configuring),
             (.ready, .ready),
             (.streaming, .streaming),
             (.paused, .paused):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}
