import Foundation

/// Computes derived metric values from raw inputs.
public enum ComputedMetrics {

    /// Heart rate zone (1–5) based on typical max HR ~190.
    public static func heartRateZone(bpm: Double) -> Int {
        switch bpm {
        case ..<104: return 1
        case 104..<123: return 2
        case 123..<142: return 3
        case 142..<161: return 4
        default: return 5
        }
    }

    /// Pace in minutes per kilometer from elapsed seconds and distance in meters.
    public static func paceMinPerKm(elapsedSeconds: TimeInterval, distanceMeters: Double) -> Double? {
        guard elapsedSeconds > 0, distanceMeters > 0 else { return nil }
        return (elapsedSeconds / 60.0) / (distanceMeters / 1000.0)
    }
}
