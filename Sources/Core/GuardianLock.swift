import Foundation
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

    func setPassword(_ password: String, name: String) {
        let hash = SHA256.hash(data: Data(password.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        defaults.set(hashString, forKey: "guardianPasswordHash")
        defaults.set(name, forKey: "guardianName")
        guardianName = name
        isEnabled = true
    }

    func verify(_ password: String) -> Bool {
        guard let stored = defaults.string(forKey: "guardianPasswordHash") else { return false }
        let hash = SHA256.hash(data: Data(password.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return hashString == stored
    }

    func disable() {
        defaults.removeObject(forKey: "guardianPasswordHash")
        defaults.removeObject(forKey: "guardianName")
        guardianName = ""
        isEnabled = false
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
