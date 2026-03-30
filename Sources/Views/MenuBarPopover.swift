import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var timerEngine: TimerEngine
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var bedtimeEngine: BedtimeEngine

    var fatiguePercent: Int {
        FatigueCalculator.calculate(
            continuousWorkSeconds: timerEngine.continuousWorkSeconds,
            workLimitMinutes: timerEngine.workDurationMinutes
        )
    }

    var onStartRest: () -> Void
    var onOpenSettings: () -> Void
    var onExit: () -> Void
    var onBedtimeUnlock: () -> Void

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
                    .foregroundStyle(progressColor(Double(fatiguePercent) / 100.0))

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

            // Bedtime status
            if bedtimeEngine.state == .approaching {
                HStack {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("距就寝 \(bedtimeEngine.minutesUntilBedtime) 分钟")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.bottom, 6)
            } else if bedtimeEngine.state == .locked {
                HStack {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                    Text("就寝锁定中")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    Spacer()
                    Button("临时解锁") { onBedtimeUnlock() }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
                .padding(.bottom, 6)
            } else if bedtimeEngine.state == .unlocked {
                HStack {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    let min = bedtimeEngine.unlockDisplayRemaining / 60
                    let sec = bedtimeEngine.unlockDisplayRemaining % 60
                    Text("临时解锁 \(min):\(String(format: "%02d", sec))")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.bottom, 6)
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
                .frame(width: 38, alignment: .leading)

            Text("–")
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 3)

            Text(session.end.map { String($0.prefix(5)) } ?? "now")
                .foregroundStyle(session.end == nil ? .green : .primary)
                .frame(width: 38, alignment: .leading)

            Spacer()

            if session.isRest {
                Text(session.seconds > 0
                    ? "休息 \(FatigueCalculator.formatDuration(session.seconds))" : "休息中")
                    .foregroundStyle(.tertiary)
            } else {
                Text(FatigueCalculator.formatDuration(session.seconds))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
    }
}
