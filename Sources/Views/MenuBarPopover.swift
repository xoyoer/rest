import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var timerEngine: TimerEngine
    @ObservedObject var usageStore: UsageStore

    var fatiguePercent: Int {
        FatigueCalculator.calculate(
            continuousWorkSeconds: timerEngine.continuousWorkSeconds,
            workLimitMinutes: timerEngine.workDurationMinutes
        )
    }

    var onStartRest: () -> Void
    var onOpenSettings: () -> Void
    var onExit: () -> Void

    private let showTimeline = true

    private var sessions: [WorkSession] {
        usageStore.todayMergedSessions().filter { session in
            session.isRest || session.end == nil || session.seconds >= 60
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Hero — percentage + stats side by side
            HStack(alignment: .lastTextBaseline) {
                Text("\(fatiguePercent)%")
                    .font(.system(size: 36, weight: .regular, design: .rounded))

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        Text("本轮")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(FatigueCalculator.formatDuration(timerEngine.continuousWorkSeconds))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(timerEngine.state == .idle ? Color.secondary : Color.primary)
                    }
                    HStack(spacing: 2) {
                        Text("今日")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(FatigueCalculator.formatDuration(timerEngine.todayTotalSeconds))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(timerEngine.todayTotalSeconds >= 8 * 3600 ? Color.orange : Color.primary)
                    }
                }
            }
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 10)

            // Status
            statusSection
                .padding(.bottom, 10)

            Divider()
                .padding(.bottom, 10)

            // Timeline (collapsible)
            if showTimeline {
                if sessions.isEmpty {
                    Text("暂无记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 10)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                            sessionRow(session)
                        }
                    }
                    .padding(.bottom, 10)
                }

                Divider()
                    .padding(.bottom, 8)
            }

            // Actions
            HStack {
                Button(action: onStartRest) {
                    Text("立即休息")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onOpenSettings) {
                    Text("设置")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)

                if !GuardianLock.shared.isEnabled {
                    Button(action: onExit) {
                        Text("退出")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        if timerEngine.preRestCountdown > 0 {
            HStack {
                Text("\(timerEngine.preRestCountdown) 秒后进入休息")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                Spacer()
            }
        } else if timerEngine.state == .resting {
            HStack {
                Text("休息中")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(FatigueCalculator.formatCountdown(timerEngine.restRemainingSeconds))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        } else if timerEngine.state == .idle {
            HStack {
                Text("已暂停")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("空闲中")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        } else {
            VStack(spacing: 6) {
                HStack {
                    Text("距下次休息")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    let remaining = max(0, TimeInterval(timerEngine.workDurationMinutes * 60) - timerEngine.continuousWorkSeconds)
                    Text(FatigueCalculator.formatCountdown(remaining))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }

                let total = TimeInterval(timerEngine.workDurationMinutes * 60)
                let progress = min(1.0, timerEngine.continuousWorkSeconds / total)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(progressColor(progress))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private func progressColor(_ progress: Double) -> Color {
        if progress < 0.5 { return .green.opacity(0.6) }
        if progress < 0.75 { return .yellow.opacity(0.6) }
        if progress < 0.9 { return .orange.opacity(0.6) }
        return .red.opacity(0.6)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: WorkSession) -> some View {
        HStack(spacing: 0) {
            Text(String(session.start.prefix(5)))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 42, alignment: .leading)

            Text("–")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

            Text(session.end.map { String($0.prefix(5)) } ?? "now")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(session.end == nil ? .green : .primary)
                .frame(width: 42, alignment: .leading)

            Spacer()

            if session.isRest {
                HStack(spacing: 3) {
                    Image(systemName: session.skipped ? "forward.fill" : "leaf")
                        .font(.system(size: 9))
                    if session.skipped || (session.end != nil && session.seconds < 10) {
                        Text("已跳过")
                            .font(.system(size: 12))
                    } else if session.seconds > 0 {
                        Text("休息 \(FatigueCalculator.formatDuration(session.seconds))")
                            .font(.system(size: 12))
                    } else {
                        Text("休息中")
                            .font(.system(size: 12))
                    }
                }
                .foregroundStyle(.secondary)
            } else {
                Text(FatigueCalculator.formatDuration(session.seconds))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
