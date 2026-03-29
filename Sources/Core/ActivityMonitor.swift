import AppKit
import Combine

// MARK: - Activity Log (file-level, thread-safe)

private let _logQueue = DispatchQueue(label: "com.xoyoer.idle.log")

private let _logURL: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("com.xoyoer.idle", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("activity.log")
}()

private let _logFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

func activityLog(_ msg: String) {
    let now = Date()
    _logQueue.async {
        let ts = _logFmt.string(from: now)
        let line = "\(ts) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: _logURL.path) {
            if let handle = try? FileHandle(forWritingTo: _logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: _logURL)
        }
    }
}

// MARK: - ActivityMonitor

@MainActor
final class ActivityMonitor: ObservableObject {
    @Published var isIdle: Bool = true
    @Published var isScreenLocked: Bool = false
    @Published var isSystemSleeping: Bool = false
    @Published var isDisplaySleeping: Bool = false

    private var idleCheckTimer: Timer?
    private var heartbeatCounter: Int = 0

    var idleThreshold: TimeInterval = 180

    // MARK: - Start / Stop

    func start() {
        if let attr = try? FileManager.default.attributesOfItem(atPath: _logURL.path),
           let size = attr[.size] as? Int, size > 500_000 {
            try? "".write(to: _logURL, atomically: true, encoding: .utf8)
        }
        activityLog("=== APP STARTED (HID-only mode) ===")
        setupScreenLockObservers()
        setupSleepWakeObservers()
        startIdleCheckTimer()
    }

    func stop() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - HID Query

    /// Query the system HID layer for seconds since last user input.
    /// No permissions required — reads a system counter, not event content.
    private func systemIdleSeconds() -> TimeInterval {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown,
            .keyDown, .scrollWheel, .flagsChanged,
        ]
        var minIdle = Double.greatestFiniteMagnitude
        for t in types {
            let s = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: t)
            if s < minIdle { minIdle = s }
        }
        return minIdle
    }

    // MARK: - Idle Check Timer

    private func startIdleCheckTimer() {
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
            [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                let sysIdle = self.systemIdleSeconds()
                let displayOff = CGDisplayIsAsleep(CGMainDisplayID()) != 0
                let shouldBeIdle = sysIdle >= self.idleThreshold
                    || self.isScreenLocked || self.isSystemSleeping
                    || self.isDisplaySleeping || displayOff

                if self.isIdle != shouldBeIdle {
                    activityLog("→ \(shouldBeIdle ? "IDLE" : "ACTIVE") (sysIdle=\(Int(sysIdle))s)")
                    self.isIdle = shouldBeIdle
                }

                // Heartbeat every 60 seconds
                self.heartbeatCounter += 1
                if self.heartbeatCounter % 12 == 0 {
                    activityLog("♥ \(self.isIdle ? "IDLE" : "ACTIVE") sysIdle=\(Int(sysIdle))s")
                }
            }
        }
    }

    // MARK: - Sleep / Wake

    private func setupSleepWakeObservers() {
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(systemWillSleep),
                         name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(systemDidWake),
                         name: NSWorkspace.didWakeNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(displaysDidSleep),
                         name: NSWorkspace.screensDidSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(displaysDidWake),
                         name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc nonisolated private func systemWillSleep() {
        activityLog("→ IDLE (system sleep)")
        DispatchQueue.main.async { [weak self] in
            self?.isSystemSleeping = true
            self?.isIdle = true
        }
    }

    @objc nonisolated private func systemDidWake() {
        activityLog("System woke from sleep")
        DispatchQueue.main.async { [weak self] in
            self?.isSystemSleeping = false
        }
    }

    // MARK: - Screen Lock

    private func setupScreenLockObservers() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenDidLock),
                        name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenDidUnlock),
                        name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc nonisolated private func screenDidLock() {
        activityLog("→ IDLE (screen locked)")
        DispatchQueue.main.async { [weak self] in
            self?.isScreenLocked = true
            self?.isIdle = true
        }
    }

    @objc nonisolated private func screenDidUnlock() {
        activityLog("Screen unlocked")
        DispatchQueue.main.async { [weak self] in
            self?.isScreenLocked = false
        }
    }

    // MARK: - Display Sleep / Wake

    @objc nonisolated private func displaysDidSleep() {
        activityLog("→ IDLE (display sleep)")
        DispatchQueue.main.async { [weak self] in
            self?.isDisplaySleeping = true
            self?.isIdle = true
        }
    }

    @objc nonisolated private func displaysDidWake() {
        activityLog("Display woke")
        DispatchQueue.main.async { [weak self] in
            self?.isDisplaySleeping = false
        }
    }
}
