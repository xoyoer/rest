import SwiftUI
import Charts

struct HistoryChartsView: View {
    @ObservedObject var store: UsageStore
    @State private var selectedRange: TimeRange = .week
    @State private var selectedDay: Date?

    enum TimeRange: String, CaseIterable {
        case week = "7天"
        case month = "28天"
        case quarter = "90天"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 28
            case .quarter: return 90
            }
        }
    }

    private struct DayData: Identifiable {
        let id: String
        let date: Date
        let totalHours: Double
        let restCount: Int
        let hasData: Bool
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Data

    private var chartData: [DayData] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = Self.dateFmt

        var lookup: [String: UsageRecord] = [:]
        for r in store.records { lookup[r.date] = r }

        return (0..<selectedRange.days).reversed().compactMap { i in
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { return nil }
            let key = fmt.string(from: d)
            let rec = lookup[key]
            return DayData(
                id: key, date: d,
                totalHours: (rec?.totalSeconds ?? 0) / 3600.0,
                restCount: rec?.restCount ?? 0,
                hasData: rec != nil
            )
        }
    }

    private func selectedItem(from data: [DayData]) -> DayData? {
        guard let day = selectedDay else { return nil }
        return data.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if h > 0 && m > 0 { return "\(h)小时\(m)分" }
        if h > 0 { return "\(h)小时" }
        return "\(m)分钟"
    }

    private func weekdayLabel(_ date: Date) -> String {
        let w = Calendar.current.component(.weekday, from: date)
        return ["", "日", "一", "二", "三", "四", "五", "六"][w]
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let weekday = cal.component(.weekday, from: date)
        let weekdays = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return "\(month)月\(day)日 \(weekdays[weekday])"
    }

    private var xAxisStride: Int {
        switch selectedRange {
        case .week: return 1
        case .month: return 7
        case .quarter: return 14
        }
    }

    private func hoverOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { _ in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if let date: Date = proxy.value(atX: location.x, as: Date.self) {
                            selectedDay = Calendar.current.startOfDay(for: date)
                        }
                    case .ended:
                        selectedDay = nil
                    @unknown default:
                        break
                    }
                }
        }
    }

    // MARK: - Body

    var body: some View {
        let data = chartData
        let withData = data.filter { $0.hasData }
        let totalHours = withData.reduce(0.0) { $0 + $1.totalHours }
        let avgHours = withData.isEmpty ? 0 : totalHours / Double(withData.count)

        Form {
            // 今日摘要
            let todaySessions = store.todaySessions().filter { !$0.isRest }
            let todayTotal = store.todaySessionTotal()
            let todayRests = store.records(last: 1).first?.restCount ?? 0
            let firstStart = todaySessions.first?.start.prefix(5).description

            if todayTotal > 0 {
                Section("今日") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatHours(todayTotal / 3600))
                                .font(.title3.weight(.medium))
                            if let start = firstStart {
                                Text("从 \(start) 开始")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if todayRests > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(todayRests)")
                                    .font(.title3.weight(.medium))
                                Text("次休息")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Range picker
            Section {
                Picker("时间范围", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Usage chart
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    // Summary — fixed height to prevent layout jumps on hover
                    VStack(alignment: .leading, spacing: 2) {
                        if let item = selectedItem(from: data), item.hasData {
                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                Text(formatHours(item.totalHours))
                                    .font(.title2.weight(.medium))
                                if item.restCount > 0 {
                                    Text("休息 \(item.restCount) 次")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(dayLabel(item.date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                Text("日均 " + formatHours(avgHours))
                                    .font(.title2.weight(.medium))
                                let totalRests = withData.reduce(0) { $0 + $1.restCount }
                                if totalRests > 0 {
                                    Text("共休息 \(totalRests) 次")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("共 \(formatHours(totalHours))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 44, alignment: .topLeading)

                    // Bar chart — let Swift Charts handle defaults
                    Chart {
                        ForEach(data) { item in
                            BarMark(
                                x: .value("日期", item.date, unit: .day),
                                y: .value("小时", item.totalHours)
                            )
                            .foregroundStyle(
                                selectedDay != nil
                                    ? (Calendar.current.isDate(item.date, inSameDayAs: selectedDay!)
                                        ? Color.accentColor : Color.accentColor.opacity(0.3))
                                    : Color.accentColor
                            )
                        }

                        if let item = selectedItem(from: data) {
                            RuleMark(x: .value("日期", item.date, unit: .day))
                                .foregroundStyle(.secondary.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: selectedRange == .week
                                ? .dateTime.weekday(.abbreviated)
                                : .dateTime.month(.twoDigits).day(.twoDigits)
                            )
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(v))")
                                }
                            }
                        }
                    }
                    .chartYAxisLabel("小时")
                    .frame(height: 160)
                    .chartOverlay { proxy in hoverOverlay(proxy) }
                }
            } header: {
                Text("使用时长")
            }

        }
        .formStyle(.grouped)
    }
}
