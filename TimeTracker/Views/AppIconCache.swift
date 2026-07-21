import AppKit

// Resolving an icon means scanning every running application, so results are
// memoized per app name. Rows re-render constantly (live durations, hover
// animations) and would otherwise repeat that scan each time.
enum AppIconCache {
    private static var cache: [String: NSImage?] = [:]

    static func icon(for appName: String) -> NSImage? {
        if let cached = cache[appName] { return cached }

        let apps = NSWorkspace.shared.runningApplications
        var found = apps.first { $0.localizedName == appName }?.icon
        if found == nil {
            // Browser-tab rows read "Some Page · Safari", so fall back to
            // matching the browser name suffix
            found = apps.first { app in
                guard let name = app.localizedName, !name.isEmpty else { return false }
                return appName.hasSuffix("· \(name)")
            }?.icon
        }

        // Only remember hits: a miss may just mean the app isn't running yet
        if found != nil {
            cache[appName] = found
        }
        return found
    }
}
