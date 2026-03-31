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

    // MARK: - Time Picker Options

    struct TimeOption {
        let hour: Int
        let minute: Int
        var label: String {
            String(format: "%d:%02d", hour, minute)
        }
    }

    static let bedtimeOptions: [TimeOption] = {
        var opts: [TimeOption] = []
        for h in 20...23 {
            opts.append(TimeOption(hour: h, minute: 0))
            opts.append(TimeOption(hour: h, minute: 30))
        }
        for h in 0...3 {
            opts.append(TimeOption(hour: h, minute: 0))
            opts.append(TimeOption(hour: h, minute: 30))
        }
        return opts
    }()

    static let wakeOptions: [TimeOption] = {
        var opts: [TimeOption] = []
        for h in 5...11 {
            opts.append(TimeOption(hour: h, minute: 0))
            opts.append(TimeOption(hour: h, minute: 30))
        }
        return opts
    }()

    var bedtimeTimeIndex: Int {
        get {
            Self.bedtimeOptions.firstIndex(where: { $0.hour == bedtimeHour && $0.minute == bedtimeMinute }) ?? 6
        }
        set {
            let opt = Self.bedtimeOptions[newValue]
            bedtimeHour = opt.hour
            bedtimeMinute = opt.minute
        }
    }

    var wakeTimeIndex: Int {
        get {
            Self.wakeOptions.firstIndex(where: { $0.hour == wakeHour && $0.minute == wakeMinute }) ?? 6
        }
        set {
            let opt = Self.wakeOptions[newValue]
            wakeHour = opt.hour
            wakeMinute = opt.minute
        }
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
