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

        // Check accessibility permission
        checkAccessibilityPermission()

        // Setup global shortcuts
        setupGlobalShortcuts()

        // Daily reset is now handled by AppCoordinator on idle→active transition,
        // not by a midnight timer. This prevents data loss when working past midnight.
    }

    // MARK: - Accessibility Permission

    private func checkAccessibilityPermission() {
        // 不弹系统对话框——由 popover 内提示引导用户手动在系统设置中添加
        // 手动用"+"按钮添加的 TCC 记录比对话框触发的更持久
        if !AXIsProcessTrusted() {
            print("[xoyoer.idle] Accessibility permission not granted. Popover will show guidance.")
        }
    }

    // MARK: - Global Shortcuts

    private func setupGlobalShortcuts() {
        // Global monitor: captures keys when app is NOT focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleShortcutEvent(event)
        }

        // Local monitor: captures keys when app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Block Cmd+Q when guardian lock is enabled
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "q",
               UserDefaults.standard.string(forKey: "guardianPasswordHash") != nil {
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
