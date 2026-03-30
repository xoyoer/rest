import AppKit

// MARK: - Notification Names

extension Notification.Name {
    static let manualRestRequested = Notification.Name("manualRestRequested")
    static let togglePopoverRequested = Notification.Name("togglePopoverRequested")
    static let exitRequested = Notification.Name("exitRequested")
    static let appWillTerminate = Notification.Name("appWillTerminate")
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Setup global shortcuts
        setupGlobalShortcuts()

        // Daily reset is now handled by AppCoordinator on idle→active transition,
        // not by a midnight timer. This prevents data loss when working past midnight.
    }

    // MARK: - Global Shortcuts

    private func setupGlobalShortcuts() {
        // Global monitor: captures keys when app is NOT focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleShortcutEvent(event)
        }

        // Local monitor: captures keys when app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Always block Cmd+Q — exit only through Settings
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "q" {
                NotificationCenter.default.post(name: .exitRequested, object: nil)
                return nil
            }
            if self?.handleShortcutEvent(event) == true {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handleShortcutEvent(_ event: NSEvent) -> Bool {
        let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
        let relevantFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard relevantFlags.contains(requiredFlags) else { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b":
            NotificationCenter.default.post(name: .manualRestRequested, object: nil)
            return true
        case "i":
            NotificationCenter.default.post(name: .togglePopoverRequested, object: nil)
            return true
        default:
            return false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .appWillTerminate, object: nil)
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
