import SwiftUI
import Combine

// MARK: - Guardian Setup (密码设置)

struct GuardianSetupView: View {
    var onComplete: () -> Void
    var onSkip: () -> Void

    @State private var guardianName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var passwordHint = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 28) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text("为 TA 设置守护锁")
                    .font(.title2.weight(.medium))

                Text("设置守护密码。退出程序时需要输入。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Form
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TA 平时怎么叫你")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("这个名字会在 TA 想退出时看到", text: $guardianName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("守护密码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("至少 4 位", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("确认密码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("再输入一次", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("密码提示（选填）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("忘记密码时显示", text: $passwordHint)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .frame(width: 260)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            // Button
            HStack(spacing: 16) {
                Button("取消") { onSkip() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("启用守护锁") { validate() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(36)
        .frame(width: 400, height: 460)
    }

    private func validate() {
        guard !password.isEmpty else {
            errorMessage = "请输入密码"
            return
        }
        guard password.count >= 4 else {
            errorMessage = "密码至少 4 位"
            return
        }
        guard password == confirmPassword else {
            errorMessage = "两次密码不一致"
            return
        }
        let name = guardianName.trimmingCharacters(in: .whitespaces)
        let hint = passwordHint.trimmingCharacters(in: .whitespaces)
        GuardianLock.shared.setPassword(password, name: name, hint: hint)
        onComplete()
    }
}

// MARK: - Change Password (需要当前密码)

struct GuardianChangePasswordView: View {
    var onDone: () -> Void

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var guardianName: String = GuardianLock.shared.guardianName
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("修改守护密码")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                SecureField("当前密码", text: $currentPassword)
                    .textFieldStyle(.roundedBorder)

                Divider()

                TextField("守护人称呼", text: $guardianName)
                    .textFieldStyle(.roundedBorder)
                SecureField("新密码（至少 4 位）", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("确认新密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 240)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                Button("取消") { onDone() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("确认修改") { attempt() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 320)
    }

    private func attempt() {
        guard GuardianLock.shared.verify(currentPassword) else {
            errorMessage = "当前密码错误"
            return
        }
        guard !newPassword.isEmpty else {
            errorMessage = "请输入新密码"
            return
        }
        guard newPassword.count >= 4 else {
            errorMessage = "密码至少 4 位"
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "两次密码不一致"
            return
        }
        let name = guardianName.trimmingCharacters(in: .whitespaces)
        GuardianLock.shared.setPassword(newPassword, name: name)
        onDone()
    }
}

// MARK: - Disable Guardian Lock (需要当前密码)

struct GuardianDisableView: View {
    var onDone: () -> Void

    @State private var password = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("关闭守护锁")
                .font(.headline)

            Text("关闭后，退出程序将不再需要密码。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("输入当前守护密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { attempt() }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                Button("取消") { onDone() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("确认关闭") { attempt() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(30)
        .frame(width: 320)
    }

    private func attempt() {
        if GuardianLock.shared.verify(password) {
            GuardianLock.shared.disable()
            onDone()
        } else {
            errorMessage = "密码错误"
            password = ""
        }
    }
}

// MARK: - Bedtime Cooldown Unlock (no guardian lock)

struct BedtimeCooldownUnlockView: View {
    var onUnlock: () -> Void
    var onCancel: () -> Void

    @State private var countdown = 60
    @State private var canUnlock = false
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("现在解锁，30 分钟后会重新锁定。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("确定不睡了？")
                .font(.title3.weight(.medium))

            if canUnlock {
                Button(action: {
                    NSApp.keyWindow?.close()
                    onUnlock()
                }) {
                    Text("临时解锁")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                Text("\(countdown) 秒")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Button("取消") {
                NSApp.keyWindow?.close()
                onCancel()
            }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(30)
        .frame(width: 300, height: 260)
        .onAppear {
            timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    guard countdown > 0 else { return }
                    countdown -= 1
                    if countdown == 0 { canUnlock = true }
                }
        }
        .onDisappear {
            timerCancellable?.cancel()
            timerCancellable = nil
        }
    }
}

// MARK: - Cooldown Exit (no guardian lock)

struct CooldownExitView: View {
    var onCancel: () -> Void

    @State private var countdown = 30
    @State private var canExit = false
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("退出后将不再提醒你休息。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("你确定吗？")
                .font(.title3.weight(.medium))

            if canExit {
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text("确认退出")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Text("\(countdown) 秒")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Button("取消") { onCancel() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(30)
        .frame(width: 300, height: 260)
        .onAppear {
            timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    guard countdown > 0 else { return }
                    countdown -= 1
                    if countdown == 0 { canExit = true }
                }
        }
        .onDisappear {
            timerCancellable?.cancel()
            timerCancellable = nil
        }
    }
}
