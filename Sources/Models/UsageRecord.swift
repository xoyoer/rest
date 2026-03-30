import Foundation

struct WorkSession: Codable {
    let start: String           // "HH:mm:ss"
    var end: String?            // "HH:mm:ss" or nil if ongoing
    var seconds: TimeInterval   // precise duration in seconds
    var isRest: Bool            // true = rest period, false = work period

    init(start: String, end: String? = nil, seconds: TimeInterval = 0, isRest: Bool = false) {
        self.start = start
        self.end = end
        self.seconds = seconds
        self.isRest = isRest
    }

    enum CodingKeys: String, CodingKey {
        case start, end, seconds, isRest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(String.self, forKey: .start)
        end = try c.decodeIfPresent(String.self, forKey: .end)
        seconds = try c.decode(TimeInterval.self, forKey: .seconds)
        isRest = try c.decodeIfPresent(Bool.self, forKey: .isRest) ?? false
    }
}

struct UsageRecord: Codable {
    let date: String  // "yyyy-MM-dd"
    var totalSeconds: TimeInterval
    var restCount: Int
    var peakFatiguePercent: Int
    var sessions: [WorkSession]

    init(date: String, totalSeconds: TimeInterval, restCount: Int, peakFatiguePercent: Int, sessions: [WorkSession] = []) {
        self.date = date
        self.totalSeconds = totalSeconds
        self.restCount = restCount
        self.peakFatiguePercent = peakFatiguePercent
        self.sessions = sessions
    }

    enum CodingKeys: String, CodingKey {
        case date, totalSeconds, restCount, peakFatiguePercent, sessions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        totalSeconds = try c.decode(TimeInterval.self, forKey: .totalSeconds)
        restCount = try c.decode(Int.self, forKey: .restCount)
        peakFatiguePercent = try c.decode(Int.self, forKey: .peakFatiguePercent)
        sessions = try c.decodeIfPresent([WorkSession].self, forKey: .sessions) ?? []
    }

    /// Total work seconds derived from sessions (excludes rest)
    var sessionTotalSeconds: TimeInterval {
        sessions.filter { !$0.isRest }.reduce(0) { $0 + $1.seconds }
    }
}

@MainActor
class UsageStore: ObservableObject {
    @Published private(set) var records: [UsageRecord] = []

    /// The "logical day" — only changes when user returns from idle on a new calendar date.
    /// Working past midnight keeps data in the same logical day.
    @Published private(set) var logicalDay: String

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("com.xoyoer.idle", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("usage.json")
        // Restore logical day from last save, or use current calendar date
        logicalDay = UserDefaults.standard.string(forKey: "logicalDay") ?? Self.calendarToday
        load()
    }

    /// Current calendar date string
    static var calendarToday: String {
        dateFmt.string(from: Date())
    }

    // MARK: - Persistence

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([UsageRecord].self, from: data)
        } catch {
            print("[UsageStore] load error: \(error)")
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[UsageStore] save error: \(error)")
        }
    }

    // MARK: - Today

    private static var dateFmt: DateFormatter { DateFormatting.dateFmt }

    func recordForToday() -> UsageRecord {
        let key = logicalDay
        if let existing = records.first(where: { $0.date == key }) {
            return existing
        }
        let fresh = UsageRecord(date: key, totalSeconds: 0, restCount: 0, peakFatiguePercent: 0)
        records.append(fresh)
        save()
        return fresh
    }

    func updateToday(restCount: Int, peakFatigue: Int) {
        let key = logicalDay
        if let idx = records.firstIndex(where: { $0.date == key }) {
            records[idx].totalSeconds = records[idx].sessionTotalSeconds
            records[idx].restCount = restCount
            records[idx].peakFatiguePercent = max(records[idx].peakFatiguePercent, peakFatigue)
        }
        save()
    }

    // MARK: - Work Session Tracking

    private static let mergeWindowSeconds: TimeInterval = 10

    func startSession() {
        let key = logicalDay
        ensureTodayExists()
        guard let idx = records.firstIndex(where: { $0.date == key }) else { return }

        // Try to merge with the last session if the idle gap was short
        // Never merge with rest sessions
        if let lastIdx = records[idx].sessions.indices.last,
           !records[idx].sessions[lastIdx].isRest,
           let endStr = records[idx].sessions[lastIdx].end,
           let gap = Self.secondsBetween(endStr, Self.timeString()),
           gap < Self.mergeWindowSeconds {
            records[idx].sessions[lastIdx].end = nil
            save()
            return
        }

        closeOpenSession(at: idx)
        let session = WorkSession(start: Self.timeString())
        records[idx].sessions.append(session)
        save()
    }

    func endSession() {
        let key = logicalDay
        guard let idx = records.firstIndex(where: { $0.date == key }) else { return }
        closeOpenSession(at: idx)
        records[idx].totalSeconds = records[idx].sessionTotalSeconds
        save()
    }

    /// Called every tick (1 second) while working — increment open work session
    func tickOpenSession() {
        let key = logicalDay
        guard let idx = records.firstIndex(where: { $0.date == key }) else { return }
        guard let sIdx = records[idx].sessions.lastIndex(where: { $0.end == nil && !$0.isRest }) else { return }
        records[idx].sessions[sIdx].seconds += 1
    }

    // MARK: - Rest Session Tracking

    /// Close current work session and start tracking a rest period
    func startRestSession() {
        let key = logicalDay
        ensureTodayExists()
        guard let idx = records.firstIndex(where: { $0.date == key }) else { return }
        closeOpenSession(at: idx)
        records[idx].totalSeconds = records[idx].sessionTotalSeconds
        let session = WorkSession(start: Self.timeString(), isRest: true)
        records[idx].sessions.append(session)
        save()
    }

    /// Close the open rest session (calculates duration from wall clock)
    func endRestSession() {
        let key = logicalDay
        guard let idx = records.firstIndex(where: { $0.date == key }) else { return }
        let now = Self.timeString()
        for i in records[idx].sessions.indices {
            if records[idx].sessions[i].isRest && records[idx].sessions[i].end == nil {
                records[idx].sessions[i].end = now
                if let gap = Self.secondsBetween(records[idx].sessions[i].start, now) {
                    records[idx].sessions[i].seconds = gap
                }
            }
        }
        save()
    }

    // MARK: - Display

    func todaySessions() -> [WorkSession] {
        let key = logicalDay
        return records.first(where: { $0.date == key })?.sessions ?? []
    }

    /// Merged sessions for display — consecutive work sessions with small gaps are combined.
    /// Rest sessions are never merged and act as boundaries.
    func todayMergedSessions() -> [WorkSession] {
        let raw = todaySessions()
        guard raw.count > 1 else { return raw }

        var merged: [WorkSession] = [raw[0]]
        for i in 1..<raw.count {
            let curr = raw[i]
            let lastIdx = merged.count - 1
            // Only merge consecutive work sessions with short gaps
            if !curr.isRest && !merged[lastIdx].isRest,
               let prevEnd = merged[lastIdx].end,
               let gap = Self.secondsBetween(prevEnd, curr.start),
               gap < Self.mergeWindowSeconds {
                merged[lastIdx].end = curr.end
                merged[lastIdx].seconds += curr.seconds
            } else {
                merged.append(curr)
            }
        }
        return merged
    }

    func todaySessionTotal() -> TimeInterval {
        let key = logicalDay
        return records.first(where: { $0.date == key })?.sessionTotalSeconds ?? 0
    }

    // MARK: - Day Boundary Cleanup

    /// Transition to a new logical day. Closes old sessions and updates the logical day.
    func resetToNewDay(_ newDay: String) {
        // Close any open sessions from the old logical day
        if let idx = records.firstIndex(where: { $0.date == logicalDay }) {
            closeOpenSession(at: idx)
            records[idx].totalSeconds = records[idx].sessionTotalSeconds
        }
        // Also close any other stale open sessions
        for i in records.indices {
            guard records[i].date != newDay else { continue }
            for j in records[i].sessions.indices {
                if records[i].sessions[j].end == nil {
                    records[i].sessions[j].end = "23:59:59"
                }
            }
            records[i].totalSeconds = records[i].sessionTotalSeconds
        }
        // Switch to new day
        logicalDay = newDay
        UserDefaults.standard.set(newDay, forKey: "logicalDay")
        save()
    }

    func closePreviousDaySessions() {
        let key = logicalDay
        var changed = false
        for i in records.indices {
            guard records[i].date != key else { continue }
            for j in records[i].sessions.indices {
                if records[i].sessions[j].end == nil {
                    records[i].sessions[j].end = "23:59:59"
                    changed = true
                }
            }
            if changed {
                records[i].totalSeconds = records[i].sessionTotalSeconds
            }
        }
        if changed { save() }
    }

    // MARK: - Helpers

    private func ensureTodayExists() {
        let key = logicalDay
        if !records.contains(where: { $0.date == key }) {
            records.append(UsageRecord(date: key, totalSeconds: 0, restCount: 0, peakFatiguePercent: 0))
        }
    }

    private func closeOpenSession(at recordIndex: Int) {
        let now = Self.timeString()
        for i in records[recordIndex].sessions.indices {
            if records[recordIndex].sessions[i].end == nil {
                records[recordIndex].sessions[i].end = now
            }
        }
    }

    private static var timeFmt: DateFormatter { DateFormatting.timeFmt }

    private static func timeString() -> String {
        timeFmt.string(from: Date())
    }

    private static func secondsBetween(_ t1: String, _ t2: String) -> TimeInterval? {
        guard let d1 = timeFmt.date(from: t1), let d2 = timeFmt.date(from: t2) else { return nil }
        let interval = d2.timeIntervalSince(d1)
        return interval >= 0 ? interval : interval + 86400
    }

    // MARK: - Query

    func records(last days: Int) -> [UsageRecord] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) else {
            return records
        }
        return records.filter { record in
            if let d = Self.dateFmt.date(from: record.date) {
                return d >= cutoff
            }
            return false
        }.sorted { $0.date < $1.date }
    }
}
