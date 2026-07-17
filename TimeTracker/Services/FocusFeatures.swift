import Foundation

// Streaks, golden hours and the monthly App Villain, ported from scattrd.
// All operate on per-day FocusDayStats computed from SwiftData sessions.
enum FocusFeatures {

    // Sessions grouped by start-of-day, oldest day first within each bucket
    static func sessionsByDay(_ sessions: [AppSessionModel]) -> [Date: [AppSessionModel]] {
        let calendar = Calendar.current
        return Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startTime) }
    }

    // MARK: — Streaks (scattrd rules: no-data days are skipped, a completed
    // day below the threshold ends it, today never breaks it)

    static func currentStreak(byDay: [Date: [AppSessionModel]], threshold: Int, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        var streak = 0, noDataRun = 0, first = true
        var day = calendar.startOfDay(for: now)
        for _ in 0..<400 {
            let stats = FocusScore.analyze(byDay[day] ?? [])
            if stats.hasEnoughData {
                noDataRun = 0
                if stats.score >= threshold { streak += 1 }
                else if !first { break }
            } else {
                noDataRun += 1
                if noDataRun > 10 { break }
            }
            first = false
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    static func bestStreak(byDay: [Date: [AppSessionModel]], threshold: Int, now: Date = Date()) -> Int {
        var best = 0, run = 0
        for day in byDay.keys.sorted() {
            let stats = FocusScore.analyze(byDay[day] ?? [])
            if stats.hasEnoughData {
                if stats.score >= threshold { run += 1; best = max(best, run) }
                else { run = 0 }
            }
        }
        return max(best, currentStreak(byDay: byDay, threshold: threshold, now: now))
    }

    // MARK: — Golden hours (recurring 3-hour peak-focus window)

    struct GoldenWindow {
        let valid: Bool
        let label: String   // e.g. "9am–12pm"
    }

    static func goldenHours(sessions: [AppSessionModel]) -> GoldenWindow {
        let calendar = Calendar.current
        var deep = [Double](repeating: 0, count: 24)
        var active = [Double](repeating: 0, count: 24)

        for block in FocusScore.blocks(from: sessions) {
            var t = block.start
            while t < block.end {
                guard let hourInterval = calendar.dateInterval(of: .hour, for: t) else { break }
                let chunkEnd = min(hourInterval.end, block.end)
                if chunkEnd <= t { break }
                let hour = calendar.component(.hour, from: t)
                active[hour] += chunkEnd.timeIntervalSince(t)
                if block.category == .deepWork {
                    deep[hour] += chunkEnd.timeIntervalSince(t)
                }
                t = chunkEnd
            }
        }

        // Prefer deep-work concentration; fall back to overall active time
        let metric = deep.reduce(0, +) > 0 ? deep : active
        guard metric.reduce(0, +) >= 1800 else {    // need ≥30 min of history
            return GoldenWindow(valid: false, label: "—")
        }
        var bestStart = 9, bestSum = -1.0
        for start in 0...21 {
            let sum = metric[start] + metric[start + 1] + metric[start + 2]
            if sum > bestSum { bestSum = sum; bestStart = start }
        }
        return GoldenWindow(valid: true, label: "\(hourName(bestStart))–\(hourName(bestStart + 3))")
    }

    static func hourName(_ h: Int) -> String {
        let hh = ((h % 24) + 24) % 24
        let display = hh % 12 == 0 ? 12 : hh % 12
        return "\(display)\(hh < 12 ? "am" : "pm")"
    }

    // MARK: — Distraction leaderboard (this month's attention drains, ranked
    // by how often you switch into them, then by time sunk)

    struct DistractionEntry: Identifiable {
        let key: String
        let switchIns: Int
        let seconds: TimeInterval
        var id: String { key }
    }

    static func distractionLeaderboard(byDay: [Date: [AppSessionModel]], now: Date = Date()) -> [DistractionEntry] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) else { return [] }

        var switchIns: [String: Int] = [:]
        var seconds: [String: TimeInterval] = [:]
        for (day, sessions) in byDay where day >= monthStart {
            let blocks = FocusScore.blocks(from: sessions)
            for (i, block) in blocks.enumerated() where block.category == .distraction {
                seconds[block.categoryKey, default: 0] += block.duration
                if i > 0 { switchIns[block.categoryKey, default: 0] += 1 }
            }
        }

        return Set(switchIns.keys).union(seconds.keys)
            .map { DistractionEntry(key: $0, switchIns: switchIns[$0] ?? 0, seconds: seconds[$0] ?? 0) }
            .sorted { ($0.switchIns, $0.seconds) > ($1.switchIns, $1.seconds) }
    }

    // MARK: — App Villain of the month (the distraction you switch into most,
    // as a share of all context switches)

    struct Villain {
        let valid: Bool
        let app: String
        let switchIns: Int
        let pct: Int
        let totalSwitches: Int
        let runnerUp: String?
        let runnerUpPct: Int
        let tie: Bool
        let periodLabel: String
    }

    static func villain(byDay: [Date: [AppSessionModel]], now: Date = Date()) -> Villain {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let label = formatter.string(from: now)

        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) else {
            return Villain(valid: false, app: "—", switchIns: 0, pct: 0, totalSwitches: 0,
                           runnerUp: nil, runnerUpPct: 0, tie: false, periodLabel: label)
        }

        var total = 0
        var counts: [String: Int] = [:]
        for (day, sessions) in byDay where day >= monthStart {
            let blocks = FocusScore.blocks(from: sessions)
            guard blocks.count > 1 else { continue }
            for i in 1..<blocks.count where FocusScore.isContextSwitch(blocks[i].category) {
                total += 1
                // Group by the category key (domain/app), not the tab title —
                // 20 YouTube videos are one villain
                counts[blocks[i].categoryKey, default: 0] += 1
            }
        }

        let ranked = counts.sorted { $0.value > $1.value }
        guard total > 0, let top = ranked.first else {
            return Villain(valid: false, app: "—", switchIns: 0, pct: 0, totalSwitches: total,
                           runnerUp: nil, runnerUpPct: 0, tie: false, periodLabel: label)
        }

        let topPct = Double(top.value) / Double(total) * 100
        let runner = ranked.count > 1 ? ranked[1] : nil
        let runnerPct = runner.map { Double($0.value) / Double(total) * 100 } ?? 0
        // Top two within 1 percentage point → a near-tie, not a clear winner
        let tie = runner.map { Double(top.value - $0.value) / Double(total) * 100 < 1.0 } ?? false

        return Villain(
            valid: true, app: top.key, switchIns: top.value,
            pct: Int(topPct.rounded()), totalSwitches: total,
            runnerUp: runner?.key, runnerUpPct: Int(runnerPct.rounded()),
            tie: tie, periodLabel: label
        )
    }
}
