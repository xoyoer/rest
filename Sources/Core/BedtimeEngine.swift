import Foundation
import Combine

enum BedtimeState: Equatable {
    case off           // Feature disabled or daytime
    case approaching   // Within 10 minutes of bedtime
    case locked        // Bedtime lockdown active
    case unlocked      // Temporarily unlocked (30 min)
}

@MainActor
class BedtimeEngine: ObservableObject {
    @Published var state: BedtimeState = .off
    @Published var minutesUntilBedtime: Int = 0

    private var timer: Timer?
    private var unlockTimer: Timer?
    private var unlockRemainingSeconds: Int = 0
    @Published var unlockDisplayRemaining: Int = 0

    var onBedtimeLock: (() -> Void)?
    var onBedtimeUnlock: (() -> Void)?
    var onBedtimeWarning: ((Int) -> Void)?  // minutes remaining

    private var lastWarningMinute: Int = -1
    private let warningMinutes = [10, 5, 1]

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
            [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.tick()
            }
        }
        // Immediate check
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        unlockTimer?.invalidate()
        unlockTimer = nil
    }

    func temporaryUnlock() {
        state = .unlocked
        unlockRemainingSeconds = 30 * 60  // 30 minutes
        unlockDisplayRemaining = unlockRemainingSeconds
        onBedtimeUnlock?()

        unlockTimer?.invalidate()
        unlockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.unlockRemainingSeconds -= 1
                self.unlockDisplayRemaining = self.unlockRemainingSeconds
                if self.unlockRemainingSeconds <= 0 {
                    self.unlockTimer?.invalidate()
                    self.unlockTimer = nil
                    // Re-lock if still in bedtime window
                    if self.isInBedtimeWindow() {
                        self.state = .locked
                        self.onBedtimeLock?()
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func tick() {
        let settings = AppSettings.shared
        guard settings.bedtimeEnabled else {
            if state != .off {
                state = .off
                lastWarningMinute = -1
            }
            return
        }

        // If temporarily unlocked, let the unlock timer handle state
        if state == .unlocked { return }

        if isInBedtimeWindow() {
            if state != .locked && state != .unlocked {
                state = .locked
                lastWarningMinute = -1
                onBedtimeLock?()
            }
        } else {
            let minutes = minutesUntil(hour: settings.bedtimeHour, minute: settings.bedtimeMinute)
            minutesUntilBedtime = minutes

            if minutes <= 10 && minutes > 0 {
                state = .approaching

                // Check warning thresholds
                for wm in warningMinutes {
                    if minutes <= wm && lastWarningMinute != wm {
                        lastWarningMinute = wm
                        onBedtimeWarning?(wm)
                        break
                    }
                }

                // 30-second warning
                let seconds = secondsUntil(hour: settings.bedtimeHour, minute: settings.bedtimeMinute)
                if seconds <= 30 && lastWarningMinute != 0 {
                    lastWarningMinute = 0
                    onBedtimeWarning?(0)
                }
            } else {
                if state != .off {
                    state = .off
                    lastWarningMinute = -1
                }
            }
        }
    }

    func isInBedtimeWindow() -> Bool {
        let settings = AppSettings.shared
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        let bedMinutes = settings.bedtimeHour * 60 + settings.bedtimeMinute
        let wakeMinutes = settings.wakeHour * 60 + settings.wakeMinute

        if bedMinutes > wakeMinutes {
            // Crosses midnight: e.g. bed=23:00, wake=08:00
            // In window if current >= 23:00 OR current < 08:00
            return currentMinutes >= bedMinutes || currentMinutes < wakeMinutes
        } else if bedMinutes < wakeMinutes {
            // Same day: e.g. bed=01:00, wake=08:00
            // In window if current >= 01:00 AND current < 08:00
            return currentMinutes >= bedMinutes && currentMinutes < wakeMinutes
        } else {
            return false
        }
    }

    private func minutesUntil(hour: Int, minute: Int) -> Int {
        let seconds = secondsUntil(hour: hour, minute: minute)
        return max(0, Int(ceil(Double(seconds) / 60.0)))
    }

    private func secondsUntil(hour: Int, minute: Int) -> Int {
        let cal = Calendar.current
        let now = Date()
        var target = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
        if target <= now {
            target = cal.date(byAdding: .day, value: 1, to: target)!
        }
        return max(0, Int(target.timeIntervalSince(now)))
    }
}
