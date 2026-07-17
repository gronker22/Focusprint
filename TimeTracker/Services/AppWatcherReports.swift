import Foundation
import SwiftData

// One bar segment in the weekly chart: how long one app ran on one day
struct DayAppDuration: Identifiable {
    let day: Date
    let appName: String
    let seconds: TimeInterval

    var id: String { "\(day.timeIntervalSince1970)-\(appName)" }
    var hours: Double { seconds / 3600 }
}

// Reporting queries (weekly chart + CSV export), split out of AppWatcher.swift
// to keep the core engine file focused on tracking
extension AppWatcher {

    // Totals per (day, app) for the last N days, limited to the apps with
    // the most total time so the chart stays readable
    func weekData(days: Int = 7, topAppCount: Int = 5) -> [DayAppDuration] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
        let weekStart = calendar.startOfDay(for: weekAgo)

        var buckets: [Date: [String: TimeInterval]] = [:]
        var appTotals: [String: TimeInterval] = [:]
        for session in fetchSessions(since: weekStart) {
            let day = calendar.startOfDay(for: session.startTime)
            buckets[day, default: [:]][session.appName, default: 0] += session.duration
            appTotals[session.appName, default: 0] += session.duration
        }

        let topApps = Set(
            appTotals
                .sorted { $0.value > $1.value }
                .prefix(topAppCount)
                .map(\.key)
        )

        return buckets
            .flatMap { day, apps in
                apps
                    .filter { topApps.contains($0.key) }
                    .map { DayAppDuration(day: day, appName: $0.key, seconds: $0.value) }
            }
            .sorted { $0.day < $1.day }
    }

    // Writes every stored session to ~/Downloads/timetracker-export.csv
    // and returns the file URL
    @discardableResult
    func exportCSV() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var csv = "date,appName,duration(s)\n"
        for session in fetchSessions(since: .distantPast) {
            // Tab titles can contain commas AND quotes — full RFC 4180 escaping
            var name = session.appName
            if name.contains(",") || name.contains("\"") || name.contains("\n") {
                name = "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            csv += "\(formatter.string(from: session.startTime)),\(name),\(Int(session.duration))\n"
        }

        guard let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let url = downloads.appendingPathComponent("timeprint-export.csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
