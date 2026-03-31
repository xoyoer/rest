import UserNotifications

struct NotificationManager {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            @Sendable _, _ in
        }
    }

    static func sendPreRestWarning() {
        let content = UNMutableNotificationContent()
        content.title = "休息"
        content.body = "30 秒后进入休息，请保存当前工作"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "pre-rest-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func sendRestComplete() {
        let messages = [
            "休息完成，状态已恢复。继续加油",
            "充电完毕，重新出发",
            "休息好了，接下来会更专注",
            "很好，你做到了按时休息",
        ]
        let content = UNMutableNotificationContent()
        content.title = "休息"
        content.body = messages.randomElement() ?? messages[0]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "rest-complete-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func sendBedtimeWarning(minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "休息"
        switch minutes {
        case 10:
            content.body = "距离就寝还有 10 分钟，请开始保存工作"
        case 5:
            content.body = "距离就寝还有 5 分钟，请保存所有工作"
        case 1:
            content.body = "1 分钟后全屏锁定，立即保存"
        case 0:
            content.body = "30 秒后锁定屏幕"
        default:
            content.body = "距离就寝还有 \(minutes) 分钟"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "bedtime-\(minutes)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func sendOvertimeReminder() {
        let messages = [
            "今天工作了 8 小时，德国人早就下班了",
            "8 小时的账单够了，剩下的明天再说",
            "好状态是明天最贵的素材，今晚先收工吧",
            "连轴转出不了好作品，今天先到这",
            "眼睛和背已经工作了 8 小时了",
        ]
        let content = UNMutableNotificationContent()
        content.title = "休息"
        content.body = messages.randomElement() ?? messages[0]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "overtime-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
