import Foundation
import ServiceManagement

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var workDurationMinutes: Int {
        didSet { UserDefaults.standard.set(workDurationMinutes, forKey: "workDuration") }
    }
    @Published var restDurationMinutes: Int {
        didSet { UserDefaults.standard.set(restDurationMinutes, forKey: "restDuration") }
    }
    @Published var idleThresholdMinutes: Int {
        didSet { UserDefaults.standard.set(idleThresholdMinutes, forKey: "idleThreshold") }
    }
    @Published var lightReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(lightReminderEnabled, forKey: "lightReminder") }
    }
    @Published var lightReminderMinutes: Int {
        didSet { UserDefaults.standard.set(lightReminderMinutes, forKey: "lightReminderInterval") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    private init() {
        let d = UserDefaults.standard
        workDurationMinutes = d.object(forKey: "workDuration") as? Int ?? 60
        restDurationMinutes = d.object(forKey: "restDuration") as? Int ?? 15
        idleThresholdMinutes = 3
        lightReminderEnabled = d.object(forKey: "lightReminder") as? Bool ?? true
        lightReminderMinutes = d.object(forKey: "lightReminderInterval") as? Int ?? 30
        launchAtLogin = true
        d.set(true, forKey: "launchAtLogin")
        updateLaunchAtLogin()
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
        }
    }
}
