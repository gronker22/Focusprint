import Foundation

extension Notification.Name {
    // Posted by the popover; AppDelegate owns the dashboard window
    static let openDashboard = Notification.Name("openDashboard")
    // Posted when category overrides change so cached analytics refresh
    static let categoriesChanged = Notification.Name("categoriesChanged")
}

/// Formats a TimeInterval as "2h 14m" or "45m" or "< 1m"
func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(max(0, duration))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60

    if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
        return "\(minutes)m"
    } else {
        return "< 1m"
    }
}
