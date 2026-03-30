import Foundation
import Combine

enum TimerState: Equatable {
    case working
    case idle
    case resting
}

@MainActor
class TimerEngine: ObservableObject {
    @Published var state: TimerState = .working
    @Published var continuousWorkSeconds: TimeInterval = 0
    @Published var todayTotalSeconds: TimeInterval = 0
    @Published var todayRestCount: Int = 0
    @Published var restRemainingSeconds: TimeInterval = 0
    @Published var preRestCountdown: Int = 0  // > 0 = pre-rest warning active

    var workDurationMinutes: Int = 60
    var restDurationMinutes: Int = 15

    private var timer: Timer?
    private var restTimer: Timer?
    private var onForceRest: (() -> Void)?
    private var onRestComplete: (() -> Void)?
    private var onWorkTick: (() -> Void)?
    private var onPreForceRest: (() -> Void)?

    private var idleSinceDate: Date?
    private var restStartDate: Date?
    private var restTotalDuration: TimeInterval = 0
    private var overtimeAlertSent = false

    func configure(
        onForceRest: @escaping () -> Void,
        onRestComplete: @escaping () -> Void,
        onWorkTick: @escaping () -> Void = {},
        onPreForceRest: @escaping () -> Void = {}
    ) {
        self.onForceRest = onForceRest
        self.onRestComplete = onRestComplete
        self.onWorkTick = onWorkTick
        self.onPreForceRest = onPreForceRest
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        restTimer?.invalidate()
        restTimer = nil
    }

    func userBecameActive() {
        guard state == .idle else { return }
        if let idleSince = idleSinceDate {
            let idleDuration = Date().timeIntervalSince(idleSince)
            if idleDuration >= TimeInterval(restDurationMinutes * 60) {
                continuousWorkSeconds = 0
                preRestCountdown = 0
            }
        }
        idleSinceDate = nil
        state = .working
    }

    func userBecameIdle() {
        guard state == .working else { return }
        preRestCountdown = 0  // Cancel pre-rest if user walked away
        idleSinceDate = Date()
        state = .idle
    }

    func startForcedRest() {
        preRestCountdown = 0
        state = .resting
        todayRestCount += 1
        restTotalDuration = TimeInterval(restDurationMinutes * 60)
        restStartDate = Date()
        restRemainingSeconds = restTotalDuration

        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restTick()
            }
        }

        onForceRest?()
    }

    func restoreContinuousWork(_ seconds: TimeInterval) {
        continuousWorkSeconds = seconds
    }

    func resetDaily() {
        continuousWorkSeconds = 0
        todayTotalSeconds = 0
        todayRestCount = 0
        restRemainingSeconds = 0
        preRestCountdown = 0
        overtimeAlertSent = false
        state = .working
    }

    // MARK: - Private

    private func tick() {
        guard state == .working else { return }

        // Pre-rest countdown: still count time but don't increase CWS
        if preRestCountdown > 0 {
            preRestCountdown -= 1
            todayTotalSeconds += 1
            onWorkTick?()
            if preRestCountdown <= 0 {
                startForcedRest()
            }
            return
        }

        continuousWorkSeconds += 1
        todayTotalSeconds += 1
        onWorkTick?()

        if !overtimeAlertSent && todayTotalSeconds >= 8 * 3600 {
            overtimeAlertSent = true
            NotificationManager.sendOvertimeReminder()
        }

        // Check forced rest (with 30-second pre-warning)
        let workLimitSeconds = workDurationMinutes * 60
        if Int(continuousWorkSeconds) >= workLimitSeconds {
            preRestCountdown = 30
            onPreForceRest?()
        }
    }

    private func restTick() {
        guard let startDate = restStartDate else {
            restRemainingSeconds -= 1
            if restRemainingSeconds <= 0 {
                restRemainingSeconds = 0
                endRest()
            }
            return
        }
        let elapsed = Date().timeIntervalSince(startDate)
        restRemainingSeconds = max(0, restTotalDuration - elapsed)
        if restRemainingSeconds <= 0 {
            endRest()
        }
    }

    private func endRest() {
        restTimer?.invalidate()
        restTimer = nil
        restStartDate = nil
        restTotalDuration = 0
        continuousWorkSeconds = 0
        preRestCountdown = 0
        state = .working
        onRestComplete?()
    }
}
