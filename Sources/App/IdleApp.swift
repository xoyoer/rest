import AppKit
import SwiftUI
import Combine

@main
struct IdleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(
                timerEngine: coordinator.timerEngine,
                usageStore: coordinator.usageStore,
                onStartRest: { coordinator.startManualRest() },
                onOpenSettings: { coordinator.openSettings() },
                onExit: { coordinator.requestExit() }
            )
        } label: {
            let icon = coordinator.isFlashing ? "leaf.fill" : "leaf"
            Image(systemName: icon)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    let activityMonitor = ActivityMonitor()
    let timerEngine = TimerEngine()
    let settings = AppSettings.shared
    let quoteManager = QuoteManager()
    let usageStore = UsageStore()

    @Published var isFlashing: Bool = false
    private var idleSince: Date? = nil

    private let restController = RestWindowController()
    private var settingsWindow: NSWindow?
    private var guardianSetupWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var usageSaveTimer: Timer?
    private var restEventMonitor: Any?
    private var flashTimer: Timer?
    private var restWasSkipped = false

    init() {
        // Apply initial settings
        syncSettingsToEngines()

        // Connect ActivityMonitor.isIdle -> TimerEngine
        // Daily reset happens here: when user returns from idle on a new calendar date
        activityMonitor.$isIdle
            .removeDuplicates()
            .sink { [weak self] isIdle in
                guard let self else { return }
                if isIdle {
                    self.timerEngine.userBecameIdle()
                    self.idleSince = Date()
                    // Don't close sessions during rest — user is naturally idle while resting
                    if self.timerEngine.state != .resting {
                        self.usageStore.endSession()
                    }
                } else {
                    // Only reset the logical day if the user was idle long enough to count
                    // as a genuine sleep/break (>= 1 hour). Short pauses past midnight
                    // (e.g., a 3-minute break at 00:01) should NOT start a new work day.
                    let calendarToday = UsageStore.calendarToday
                    let idleDuration = self.idleSince.map { Date().timeIntervalSince($0) } ?? 0
                    if calendarToday != self.usageStore.logicalDay && idleDuration >= 3600 {
                        // Long idle + new calendar day = new logical work day
                        self.saveUsageData()
                        self.usageStore.resetToNewDay(calendarToday)
                        self.timerEngine.resetDaily()
                        _ = self.usageStore.recordForToday()
                    }
                    self.idleSince = nil
                    self.timerEngine.userBecameActive()
                    self.usageStore.startSession()
                }
            }
            .store(in: &cancellables)

        // Sync settings changes -> engines (debounced)
        settings.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.syncSettingsToEngines()
                }
            }
            .store(in: &cancellables)

        // Forward timerEngine changes so menu bar label refreshes
        timerEngine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Configure timer callbacks
        timerEngine.configure(
            onForceRest: { [weak self] in
                self?.showRestScreen()
            },
            onRestComplete: { [weak self] in
                guard let self else { return }
                self.restController.dismiss()
                self.endRestMode()
                // Positive feedback only for natural completion, not skip
                if !self.restWasSkipped {
                    NotificationManager.sendRestComplete()
                }
                self.restWasSkipped = false
                // Close rest session, start new work session if active
                self.usageStore.endRestSession()
                if !self.activityMonitor.isIdle {
                    self.usageStore.startSession()
                }
                self.saveUsageData()
                self.syncIdleState()
            },
            onWorkTick: { [weak self] in
                self?.usageStore.tickOpenSession()
            },
            onPreForceRest: { [weak self] in
                NotificationManager.sendPreRestWarning()
                self?.flashMenuBarIcon()
            }
        )

        // Request notification permission
        NotificationManager.requestPermission()

        // Start monitoring
        activityMonitor.start()
        timerEngine.start()

        // Periodically save usage data (every 60 seconds)
        usageSaveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
            [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.saveUsageData()
            }
        }

        // On startup: if calendar date changed and user was idle (app restart after sleep),
        // switch to new day. If user restarted app during active work past midnight, keep logical day.
        let calendarToday = UsageStore.calendarToday
        if calendarToday != usageStore.logicalDay {
            // App restarted on a new calendar day — reset
            usageStore.resetToNewDay(calendarToday)
        }

        // Restore today's data — use session total if sessions exist, else stored value
        let todayRecord = usageStore.recordForToday()
        let sessionTotal = todayRecord.sessionTotalSeconds
        timerEngine.todayTotalSeconds = sessionTotal > 0 ? sessionTotal : todayRecord.totalSeconds
        timerEngine.todayRestCount = todayRecord.restCount

        // Restore continuous work seconds across app restarts
        restoreContinuousWork()

        // Sync initial idle state — timer starts as .working but user may be idle
        syncIdleState()

        // Listen for manual rest shortcut (Shift+Cmd+B)
        NotificationCenter.default.addObserver(
            forName: .manualRestRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.startManualRest()
            }
        }

        // Listen for toggle popover shortcut (Shift+Cmd+I)
        NotificationCenter.default.addObserver(
            forName: .togglePopoverRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        }

        // Listen for app termination to save data
        // Use queue: nil for synchronous execution on posting thread (main).
        // queue: .main + DispatchQueue.main.sync would deadlock.
        NotificationCenter.default.addObserver(
            forName: .appWillTerminate,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.usageStore.endSession()
                self?.saveUsageData()
            }
        }

        // Listen for Cmd+Q interception when guardian lock is on
        NotificationCenter.default.addObserver(
            forName: .exitRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.requestExit()
            }
        }

        print("[xoyoer.idle] Started successfully")

        // Show guardian setup on first launch
        if !GuardianLock.shared.setupShown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showGuardianSetup()
            }
        }
    }

    // MARK: - Settings Sync

    private func syncSettingsToEngines() {
        timerEngine.workDurationMinutes = settings.workDurationMinutes
        timerEngine.restDurationMinutes = settings.restDurationMinutes
        activityMonitor.idleThreshold = TimeInterval(settings.idleThresholdMinutes * 60)
    }

    // MARK: - Idle State Sync

    /// Force timerEngine state to match activityMonitor.isIdle.
    /// Needed after resetDaily() and on startup, because removeDuplicates()
    /// won't re-fire if isIdle was already true before the reset.
    private func syncIdleState() {
        if activityMonitor.isIdle {
            timerEngine.userBecameIdle()
        } else {
            timerEngine.userBecameActive()
        }
    }

    // MARK: - Rest

    func startManualRest() {
        guard timerEngine.state != .resting else { return }
        timerEngine.startForcedRest()
    }

    func openSettings() {
        // If window already exists and is visible, just bring to front
        if let window = settingsWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            NSCursor.arrow.set()
            return
        }

        let settingsContent = SettingsContainer(settings: settings, usageStore: usageStore)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "休息"
        window.titlebarAppearsTransparent = false
        window.acceptsMouseMovedEvents = true
        window.contentView = NSHostingView(rootView: settingsContent)
        window.center()
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSCursor.arrow.set()

        settingsWindow = window
    }

    private func showRestScreen() {
        stopFlashing()
        // Close work session and start rest session in timeline
        usageStore.startRestSession()

        let quote = quoteManager.random()
        let canSkip = !timerEngine.skipUsedToday

        startRestMode()

        restController.show(
            quote: quote,
            timerEngine: timerEngine,
            canSkip: canSkip,
            onSkip: { [weak self] in
                self?.restWasSkipped = true
                self?.usageStore.skipRestSession()
                _ = self?.timerEngine.skipRest()
                self?.endRestMode()
            }
        )
    }

    // MARK: - Rest Mode Event Interception

    private func startRestMode() {
        restEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            return self?.timerEngine.state == .resting ? nil : event
        }
    }

    func endRestMode() {
        if let monitor = restEventMonitor {
            NSEvent.removeMonitor(monitor)
            restEventMonitor = nil
        }
    }

    // MARK: - Menu Bar Flash

    private func flashMenuBarIcon() {
        flashTimer?.invalidate()
        var count = 0
        isFlashing = true
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] timer in
            DispatchQueue.main.async { [weak self] in
                guard let self else { timer.invalidate(); return }
                count += 1
                self.isFlashing = count % 2 == 1
            }
        }
    }

    private func stopFlashing() {
        flashTimer?.invalidate()
        flashTimer = nil
        isFlashing = false
    }

    // MARK: - Usage Data

    func saveUsageData() {
        let fatigue = FatigueCalculator.calculate(
            continuousWorkSeconds: timerEngine.continuousWorkSeconds,
            workLimitMinutes: timerEngine.workDurationMinutes
        )
        usageStore.updateToday(
            restCount: timerEngine.todayRestCount,
            peakFatigue: fatigue
        )
        // Sync timerEngine's todayTotalSeconds from sessions
        timerEngine.todayTotalSeconds = usageStore.todaySessionTotal()

        // Persist continuous work state for restart recovery
        let d = UserDefaults.standard
        d.set(timerEngine.continuousWorkSeconds, forKey: "cws")
        d.set(Date().timeIntervalSince1970, forKey: "cwsSavedAt")
    }

    /// Restore continuousWorkSeconds from last save.
    /// Matches TimerEngine.userBecameActive(): if the app was down for >= one rest cycle,
    /// the downtime counted as a rest and fatigue resets to 0.
    private func restoreContinuousWork() {
        let d = UserDefaults.standard
        let saved = d.double(forKey: "cws")
        let savedAt = d.double(forKey: "cwsSavedAt")
        guard savedAt > 0, saved > 0 else { return }

        let elapsed = Date().timeIntervalSince1970 - savedAt
        if elapsed < TimeInterval(settings.restDurationMinutes * 60) {
            timerEngine.restoreContinuousWork(saved)
        }
        // If elapsed >= restDuration, keep at 0 — the downtime counted as a rest
    }

    // MARK: - Guardian Lock: Exit Protection

    func requestExit() {
        if GuardianLock.shared.isEnabled {
            showExitPasswordDialog()
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    private func showExitPasswordDialog() {
        let guardian = GuardianLock.shared
        let alert = NSAlert()
        alert.messageText = "需要守护密码才能退出"
        if !guardian.guardianName.isEmpty {
            alert.informativeText = "请联系 \(guardian.guardianName) 获取密码"
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确认退出")
        alert.addButton(withTitle: "取消")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = "守护密码"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if guardian.verify(input.stringValue) {
                NSApplication.shared.terminate(nil)
            } else {
                let errorAlert = NSAlert()
                errorAlert.messageText = "密码错误"
                if !guardian.guardianName.isEmpty {
                    errorAlert.informativeText = "请联系 \(guardian.guardianName) 获取正确密码"
                }
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        }
    }

    // MARK: - Guardian Lock: First Launch Setup

    func showGuardianSetup() {
        if guardianSetupWindow != nil { return }

        let setupView = OnboardingView(
            onComplete: { [weak self] in
                self?.guardianSetupWindow?.close()
                self?.guardianSetupWindow = nil
            },
            onSkip: { [weak self] in
                self?.guardianSetupWindow?.close()
                self?.guardianSetupWindow = nil
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "休息"
        window.acceptsMouseMovedEvents = true
        window.contentView = NSHostingView(rootView: setupView)
        window.center()
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSCursor.arrow.set()

        guardianSetupWindow = window

        // When user closes via X button, treat as "skip"
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                GuardianLock.shared.setupShown = true
                self?.guardianSetupWindow = nil
            }
        }
    }
}
