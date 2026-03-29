import Foundation

struct FatigueCalculator: Sendable {
    static func calculate(
        continuousWorkSeconds: TimeInterval,
        workLimitMinutes: Int
    ) -> Int {
        let limitSeconds = TimeInterval(workLimitMinutes * 60)
        guard limitSeconds > 0 else { return 0 }
        let ratio = continuousWorkSeconds / limitSeconds
        return min(100, max(0, Int(ratio * 100)))
    }

    static func formatDuration(_ totalSeconds: TimeInterval) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)\u{5c0f}\u{65f6}\(minutes)\u{5206}"
        } else {
            return "\(minutes)\u{5206}\u{949f}"
        }
    }

    static func formatCountdown(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
