import AppKit
import CryptoKit

@MainActor
final class GuardianLock: ObservableObject {
    static let shared = GuardianLock()

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool
    @Published var guardianName: String

    var setupShown: Bool {
        get { defaults.bool(forKey: "guardianSetupShown") }
        set { defaults.set(newValue, forKey: "guardianSetupShown") }
    }

    private init() {
        isEnabled = defaults.string(forKey: "guardianPasswordHash") != nil
        guardianName = defaults.string(forKey: "guardianName") ?? ""
    }

    var passwordHint: String {
        get { defaults.string(forKey: "guardianPasswordHint") ?? "" }
        set { defaults.set(newValue, forKey: "guardianPasswordHint") }
    }

    func setPassword(_ password: String, name: String, hint: String = "") {
        let salt = UUID().uuidString
        let hashString = hash(password, salt: salt)
        defaults.set(hashString, forKey: "guardianPasswordHash")
        defaults.set(salt, forKey: "guardianPasswordSalt")
        defaults.set(name, forKey: "guardianName")
        defaults.set(hint, forKey: "guardianPasswordHint")
        guardianName = name
        isEnabled = true
    }

    func verify(_ password: String) -> Bool {
        guard let stored = defaults.string(forKey: "guardianPasswordHash") else { return false }
        let salt = defaults.string(forKey: "guardianPasswordSalt") ?? ""
        return hash(password, salt: salt) == stored
    }

    func disable() {
        defaults.removeObject(forKey: "guardianPasswordHash")
        defaults.removeObject(forKey: "guardianPasswordSalt")
        defaults.removeObject(forKey: "guardianName")
        guardianName = ""
        isEnabled = false
    }

    private func hash(_ password: String, salt: String) -> String {
        let salted = salt + password
        let hash = SHA256.hash(data: Data(salted.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Show NSAlert password dialog and terminate app if password is correct.
    func showExitDialog() {
        let alert = NSAlert()
        alert.messageText = "退出需要守护密码"
        if !guardianName.isEmpty {
            alert.informativeText = "请联系 \(guardianName) 获取密码"
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
            if verify(input.stringValue) {
                NSApplication.shared.terminate(nil)
            } else {
                let errorAlert = NSAlert()
                errorAlert.messageText = "密码错误"
                if !passwordHint.isEmpty {
                    errorAlert.informativeText = "提示：\(passwordHint)"
                } else if !guardianName.isEmpty {
                    errorAlert.informativeText = "请联系 \(guardianName) 获取密码"
                }
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        }
    }

    /// Daily rotating reflection phrase — shown during skip cooldown
    var todaySkipPhrase: String {
        let phrases = [
            "休息是为了更好地工作，不是偷懒",
            "连续工作不会让你更高效，只会让你更疲惫",
            "你的身体比任何截止日期都重要",
            "现在休息 15 分钟，比之后生病休息 15 天划算",
            "真正的高手知道什么时候该停下来",
            "关心你的人正在看着，别让 TA 担心",
            "你已经很努力了，允许自己休息一下",
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return phrases[(day - 1) % phrases.count]
    }
}
