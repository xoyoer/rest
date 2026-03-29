import SwiftUI

// MARK: - Settings Container

struct SettingsContainer: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var usageStore: UsageStore
    @State private var selectedTab: SettingsTab = .settings

    enum SettingsTab: String, CaseIterable {
        case settings = "设置"
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
                    CombinedSettingsView(settings: settings)
                case .history:
                    HistoryChartsView(store: usageStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 540)
    }
}

// MARK: - Combined Settings

struct CombinedSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var guardianLock = GuardianLock.shared
    @State private var showSetup = false
    @State private var showChangePassword = false
    @State private var showDisable = false
    @State private var showExit = false

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

                HStack {
                    Text("每日可跳过")
                    Spacer()
                    Text("1 次")
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("通用")
            } footer: {
                Text("无键鼠活动超过空闲判定时长后，计时自动暂停。")
            }

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

                    Button("修改密码") { showChangePassword = true }
                    Button("关闭守护锁") { showDisable = true }
                        .foregroundStyle(.red)
                } else {
                    Button("设置守护锁") { showSetup = true }
                }
            } header: {
                Text("守护锁")
            } footer: {
                Text(guardianLock.isEnabled
                    ? "退出程序需要守护密码。"
                    : "启用后退出程序需要密码。建议让关心你的人来设置。"
                )
            }

            // Exit
            if guardianLock.isEnabled {
                Section {
                    Button("退出程序") { showExit = true }
                        .foregroundStyle(.red)
                }
            }

            // About
            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("开发者")
                    Spacer()
                    Text("xoyoer")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("所有数据仅存储在本机，不会上传到任何服务器。")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showSetup) {
            GuardianSetupView(
                isFirstLaunch: false,
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
        .sheet(isPresented: $showExit) {
            GuardianExitView(onCancel: { showExit = false })
        }
    }
}
