import AppKit
import CryptoKit

@MainActor
final class GuardianLock: ObservableObject {
    static let shared = GuardianLock()

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool
    @Published var guardianName: String

    private init() {
        isEnabled = defaults.string(forKey: "guardianPasswordHash") != nil
        guardianName = defaults.string(forKey: "guardianName") ?? ""
    }

    var passwordHint: String {
        get { defaults.string(forKey: "guardianPasswordHint") ?? "" }
        set { defaults.set(newValue, forKey: "guardianPasswordHint") }
    }

    /// Set password and generate a one-time recovery code.
    /// Returns the recovery code — must be shown to the guardian immediately.
    @discardableResult
    func setPassword(_ password: String, name: String, hint: String = "") -> String {
        let salt = UUID().uuidString
        let hashString = hash(password, salt: salt)
        defaults.set(hashString, forKey: "guardianPasswordHash")
        defaults.set(salt, forKey: "guardianPasswordSalt")
        defaults.set(name, forKey: "guardianName")
        defaults.set(hint, forKey: "guardianPasswordHint")

        // Generate 8-character recovery code
        let code = generateRecoveryCode()
        let codeSalt = UUID().uuidString
        defaults.set(hash(code, salt: codeSalt), forKey: "guardianRecoveryHash")
        defaults.set(codeSalt, forKey: "guardianRecoverySalt")

        guardianName = name
        isEnabled = true
        return code
    }

    func verifyRecoveryCode(_ code: String) -> Bool {
        guard let stored = defaults.string(forKey: "guardianRecoveryHash") else { return false }
        let salt = defaults.string(forKey: "guardianRecoverySalt") ?? ""
        return hash(code, salt: salt) == stored
    }

    /// Reset guardian lock using recovery code
    func resetWithRecoveryCode(_ code: String) -> Bool {
        guard verifyRecoveryCode(code) else { return false }
        disable()
        return true
    }

    private func generateRecoveryCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  // No I/O/0/1 to avoid confusion
        return String((0..<8).map { _ in chars.randomElement()! })
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
        defaults.removeObject(forKey: "guardianPasswordHint")
        defaults.removeObject(forKey: "guardianRecoveryHash")
        defaults.removeObject(forKey: "guardianRecoverySalt")
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

}
