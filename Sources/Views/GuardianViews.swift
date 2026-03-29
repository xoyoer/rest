import SwiftUI

// MARK: - First Launch Onboarding (三步引导)

struct OnboardingView: View {
    var onComplete: () -> Void
    var onSkip: () -> Void

    enum Step {
        case welcome
        case setup
        case done
    }

    @State private var step: Step = .welcome

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomePageView(
                    onNext: { step = .setup }
                )
            case .setup:
                GuardianSetupView(
                    isFirstLaunch: true,
                    onComplete: { step = .done },
                    onSkip: { }  // First launch: no escape
                )
            case .done:
                SetupDoneView(onDone: onComplete)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step == .welcome)
    }
}

extension OnboardingView.Step: Equatable {}

// MARK: - Welcome Page

struct WelcomePageView: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "leaf")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.green.opacity(0.7))

            VStack(spacing: 12) {
                Text("TA 总是忘记休息？")
                    .font(.title3.weight(.medium))

                Text("装上这个，TA 就跑不掉了。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                featureRow("timer", "连续工作到点，全屏休息")
                featureRow("lock.shield", "密码在你手里，TA 退不掉")
                featureRow("bolt.heart", "不是控制，是守护")
            }
            .padding(.vertical, 8)

            Spacer()

            Button(action: onNext) {
                Text("为 TA 设置守护锁")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 8)
        }
        .padding(36)
        .frame(width: 400, height: 460)
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 60)
    }
}

// MARK: - Setup Done Page

struct SetupDoneView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.green)

            VStack(spacing: 10) {
                Text("守护锁已启用")
                    .font(.title3.weight(.medium))

                VStack(spacing: 4) {
                    Text("程序会在菜单栏安静运行，TA 不会注意到它。")
                    Text("连续工作超时后，就会被温柔地提醒休息。")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            if !GuardianLock.shared.guardianName.isEmpty {
                Text("守护人：\(GuardianLock.shared.guardianName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Capsule())
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onDone) {
                    Text("完成")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("你身边还有需要休息的人吗？")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 16)
        }
        .padding(36)
        .frame(width: 400, height: 460)
    }
}

// MARK: - Guardian Setup (密码设置)

struct GuardianSetupView: View {
    var isFirstLaunch: Bool = true
    var onComplete: () -> Void
    var onSkip: () -> Void

    @State private var guardianName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
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

                Text(isFirstLaunch
                    ? "设一个只有你知道的密码。\nTA 想退出的时候，需要你的允许。"
                    : "设置守护密码。退出程序时需要输入。"
                )
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
            }
            .frame(width: 260)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            // Button
            if isFirstLaunch {
                Button("启用守护锁") {
                    validate()
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 16) {
                    Button("取消") { onSkip() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Button("启用守护锁") { validate() }
                        .buttonStyle(.borderedProminent)
                }
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
        GuardianLock.shared.setPassword(password, name: name)
        GuardianLock.shared.setupShown = true
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

            Text("关闭后，退出程序和跳过休息将不再需要密码。")
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

// MARK: - Exit with Guardian Password

struct GuardianExitView: View {
    var onCancel: () -> Void

    @State private var password = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("退出需要守护密码")
                .font(.headline)

            if !GuardianLock.shared.guardianName.isEmpty {
                Text("请联系 \(GuardianLock.shared.guardianName) 获取密码")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SecureField("守护密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { attempt() }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                Button("取消") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("确认退出") { attempt() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(30)
        .frame(width: 320)
    }

    private func attempt() {
        if GuardianLock.shared.verify(password) {
            NSApplication.shared.terminate(nil)
        } else {
            errorMessage = "密码错误"
            password = ""
        }
    }
}
