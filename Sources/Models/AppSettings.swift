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
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    // Bedtime
    @Published var bedtimeEnabled: Bool {
        didSet { UserDefaults.standard.set(bedtimeEnabled, forKey: "bedtimeEnabled") }
    }
    @Published var bedtimeHour: Int {
        didSet { UserDefaults.standard.set(bedtimeHour, forKey: "bedtimeHour") }
    }
    @Published var bedtimeMinute: Int {
        didSet { UserDefaults.standard.set(bedtimeMinute, forKey: "bedtimeMinute") }
    }
    @Published var wakeHour: Int {
        didSet { UserDefaults.standard.set(wakeHour, forKey: "wakeHour") }
    }
    @Published var wakeMinute: Int {
        didSet { UserDefaults.standard.set(wakeMinute, forKey: "wakeMinute") }
    }

    private init() {
        let d = UserDefaults.standard
        workDurationMinutes = d.object(forKey: "workDuration") as? Int ?? 60
        restDurationMinutes = d.object(forKey: "restDuration") as? Int ?? 15
        idleThresholdMinutes = d.object(forKey: "idleThreshold") as? Int ?? 2
        bedtimeEnabled = d.object(forKey: "bedtimeEnabled") as? Bool ?? false
        bedtimeHour = d.object(forKey: "bedtimeHour") as? Int ?? 23
        bedtimeMinute = d.object(forKey: "bedtimeMinute") as? Int ?? 0
        wakeHour = d.object(forKey: "wakeHour") as? Int ?? 8
        wakeMinute = d.object(forKey: "wakeMinute") as? Int ?? 0
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
