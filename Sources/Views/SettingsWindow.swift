import SwiftUI

// MARK: - Settings Container

struct SettingsContainer: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var usageStore: UsageStore
    @State private var selectedTab: SettingsTab = .settings

    enum SettingsTab: String, CaseIterable {
        case settings = "设置"
        case guardian = "守护"
        case history = "历史"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Spacer()
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selectedTab == tab ? .medium : .regular))
                            .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, 8)

            Divider()

            Group {
                switch selectedTab {
                case .settings:
                    GeneralSettingsView(settings: settings)
                case .guardian:
                    GuardianSettingsView(settings: settings)
                case .history:
                    HistoryChartsView(store: usageStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 700)
    }
}

// MARK: - General Settings (设置)

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("工作时长", selection: $settings.workDurationMinutes) {
                    Text("45 分钟").tag(45)
                    Text("60 分钟").tag(60)
                    Text("75 分钟").tag(75)
                    Text("90 分钟").tag(90)
                }

                Picker("休息时长", selection: $settings.restDurationMinutes) {
                    Text("10 分钟").tag(10)
                    Text("15 分钟").tag(15)
                    Text("20 分钟").tag(20)
                    Text("25 分钟").tag(25)
                    Text("30 分钟").tag(30)
                }

                HStack {
                    Text("登录时启动")
                    Spacer()
                    Text("始终开启")
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("通用")
            } footer: {
                Text("无键鼠活动超过 \(settings.idleThresholdMinutes) 分钟后，计时自动暂停。")
            }

            // About
            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.1.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("开发者")
                    Spacer()
                    Link("@xoyoer", destination: URL(string: "https://www.xiaohongshu.com/user/profile/5fdde5a300000000010069f4")!)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Guardian Settings (守护)

struct GuardianSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var guardianLock = GuardianLock.shared
    @State private var showSetup = false
    @State private var showChangePassword = false
    @State private var showDisable = false
    @State private var showCooldownExit = false
    @State private var showRecovery = false
    @State private var showBedtimeEdit = false

    var body: some View {
        Form {
            // Guardian Lock
            Section {
                if guardianLock.isEnabled {
                    HStack {
                        Text("守护人")
                        Spacer()
                        Text(guardianLock.guardianName.isEmpty ? "已启用" : guardianLock.guardianName)
                            .foregroundStyle(.secondary)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 13))
                    }

                    Text("修改密码")
                        .foregroundStyle(.blue)
                        .onTapGesture { showChangePassword = true }
                    Text("忘记密码")
                        .foregroundStyle(.blue)
                        .onTapGesture { showRecovery = true }
                    Text("关闭守护锁")
                        .foregroundStyle(.red)
                        .onTapGesture { showDisable = true }
                } else {
                    Text("设置守护锁")
                        .foregroundStyle(.blue)
                        .onTapGesture { showSetup = true }
                }
            } header: {
                Text("守护锁")
            } footer: {
                Text(guardianLock.isEnabled
                    ? "退出程序和修改戒熬夜设置需要守护密码。"
                    : "启用后退出程序需要密码。建议让关心你的人来设置。"
                )
            }

            // Bedtime
            Section {
                if guardianLock.isEnabled && settings.bedtimeEnabled {
                    HStack {
                        Text("戒熬夜")
                        Spacer()
                        Text("已开启")
                            .foregroundStyle(.secondary)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 13))
                    }
                    HStack {
                        Text("就寝时间")
                        Spacer()
                        Text(AppSettings.bedtimeOptions[settings.bedtimeTimeIndex].label)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("开工时间")
                        Spacer()
                        Text(AppSettings.wakeOptions[settings.wakeTimeIndex].label)
                            .foregroundStyle(.secondary)
                    }
                    Text("修改设置")
                        .foregroundStyle(.blue)
                        .onTapGesture { requestBedtimeEdit() }
                } else if guardianLock.isEnabled && !settings.bedtimeEnabled {
                    HStack {
                        Text("戒熬夜")
                        Spacer()
                        Text("未开启")
                            .foregroundStyle(.tertiary)
                    }
                    Text("开启戒熬夜")
                        .foregroundStyle(.blue)
                        .onTapGesture { requestBedtimeEdit() }
                } else {
                    Toggle("戒熬夜", isOn: $settings.bedtimeEnabled)

                    if settings.bedtimeEnabled {
                        Picker("就寝时间", selection: $settings.bedtimeTimeIndex) {
                            ForEach(Array(AppSettings.bedtimeOptions.enumerated()), id: \.offset) { i, opt in
                                Text(opt.label).tag(i)
                            }
                        }

                        Picker("开工时间", selection: $settings.wakeTimeIndex) {
                            ForEach(Array(AppSettings.wakeOptions.enumerated()), id: \.offset) { i, opt in
                                Text(opt.label).tag(i)
                            }
                        }
                    }
                }
            } header: {
                Text("戒熬夜")
            } footer: {
                Text(settings.bedtimeEnabled
                    ? "就寝后全屏锁定，到开工时间自动解锁。提前 10 分钟开始提醒。"
                    : "开启后到点全屏锁定，帮你戒掉熬夜。"
                )
            }

            // Exit
            Section {
                if guardianLock.isEnabled {
                    Text("退出程序")
                        .foregroundStyle(.red)
                        .onTapGesture { exitWithGuardianPassword() }
                } else {
                    Text("退出程序")
                        .foregroundStyle(.red)
                        .onTapGesture { showCooldownExit = true }
                }
            } footer: {
                Text(guardianLock.isEnabled
                    ? "退出程序需要守护密码。"
                    : "退出后将不再提醒休息。"
                )
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showSetup) {
            GuardianSetupView(
                onComplete: { showSetup = false },
                onSkip: { showSetup = false }
            )
        }
        .sheet(isPresented: $showChangePassword) {
            GuardianChangePasswordView(onDone: { showChangePassword = false })
        }
        .sheet(isPresented: $showDisable) {
            GuardianDisableView(onDone: { showDisable = false })
        }
        .sheet(isPresented: $showCooldownExit) {
            CooldownExitView(onCancel: { showCooldownExit = false })
        }
        .sheet(isPresented: $showRecovery) {
            GuardianRecoveryView(onDone: { showRecovery = false })
        }
        .sheet(isPresented: $showBedtimeEdit) {
            BedtimeEditView(settings: settings, onDone: { showBedtimeEdit = false })
        }
    }

    private func exitWithGuardianPassword() {
        GuardianLock.shared.showExitDialog()
    }

    private func requestBedtimeEdit() {
        let alert = NSAlert()
        alert.messageText = "修改戒熬夜设置需要守护密码"
        alert.addButton(withTitle: "确认")
        alert.addButton(withTitle: "取消")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = "守护密码"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn && GuardianLock.shared.verify(input.stringValue) {
            showBedtimeEdit = true
        }
    }
}

// MARK: - Bedtime Edit (after guardian password verified)

struct BedtimeEditView: View {
    @ObservedObject var settings: AppSettings
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("修改戒熬夜设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("戒熬夜", isOn: $settings.bedtimeEnabled)

                if settings.bedtimeEnabled {
                    Picker("就寝时间", selection: $settings.bedtimeTimeIndex) {
                        ForEach(Array(AppSettings.bedtimeOptions.enumerated()), id: \.offset) { i, opt in
                            Text(opt.label).tag(i)
                        }
                    }

                    Picker("开工时间", selection: $settings.wakeTimeIndex) {
                        ForEach(Array(AppSettings.wakeOptions.enumerated()), id: \.offset) { i, opt in
                            Text(opt.label).tag(i)
                        }
                    }
                }
            }
            .frame(width: 260)

            Button("完成") { onDone() }
                .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(width: 340)
    }
}
