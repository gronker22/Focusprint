import Foundation

// Everything the dashboard renders, computed ONCE per refresh instead of on
// every SwiftUI render pass — full-history analytics on each frame is what
// made scrolling stutter
struct DashboardModel {
    struct DayTotal: Identifiable {
        let day: Date
        let seconds: TimeInterval
        var id: Date { day }
        var hours: Double { seconds / 3600 }
    }

    let sessions: [AppSessionModel]
    let stats: DashboardStats
    let dayTotals: [DayTotal]
    let averageHours: Double
    let trends: (risers: [AppTrend], fallers: [AppTrend])
    let records: PersonalRecords
    let fingerprint: [FingerprintCell]
    let focusToday: FocusDayStats
    let streakCurrent: Int
    let streakBest: Int
    let golden: FocusFeatures.GoldenWindow
    let villain: FocusFeatures.Villain

    static func load(watcher: AppWatcher, rangeDays: Int, streakGoal: Int) -> DashboardModel {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let periodStart = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: todayStart) ?? todayStart

        let history = watcher.fetchSessions(since: .distantPast)
        let sessions = history.filter { $0.startTime >= periodStart }
        let previousStart = calendar.date(byAdding: .day, value: -rangeDays, to: periodStart) ?? periodStart
        let previous = history.filter { $0.startTime >= previousStart && $0.startTime < periodStart }

        var totals: [Date: TimeInterval] = [:]
        for session in sessions {
            totals[calendar.startOfDay(for: session.startTime), default: 0] += session.duration
        }
        let dayTotals: [DayTotal] = (0..<rangeDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            return DayTotal(day: day, seconds: totals[day] ?? 0)
        }
        .sorted { $0.day < $1.day }

        let tracked = dayTotals.filter { $0.seconds > 0 }
        let averageHours = tracked.isEmpty
            ? 0 : tracked.reduce(0) { $0 + $1.hours } / Double(tracked.count)

        let byDay = FocusFeatures.sessionsByDay(history)
        let goldenStart = calendar.date(byAdding: .day, value: -20, to: todayStart) ?? todayStart

        return DashboardModel(
            sessions: sessions,
            stats: AnalyticsEngine.stats(for: sessions),
            dayTotals: dayTotals,
            averageHours: averageHours,
            trends: AnalyticsEngine.trends(current: sessions, previous: previous),
            records: AnalyticsEngine.records(allSessions: history),
            fingerprint: AnalyticsEngine.fingerprint(for: sessions),
            focusToday: FocusScore.analyze(byDay[todayStart] ?? []),
            streakCurrent: FocusFeatures.currentStreak(byDay: byDay, threshold: streakGoal),
            streakBest: FocusFeatures.bestStreak(byDay: byDay, threshold: streakGoal),
            golden: FocusFeatures.goldenHours(
                sessions: history.filter { $0.startTime >= goldenStart }
            ),
            villain: FocusFeatures.villain(byDay: byDay)
        )
    }
}
