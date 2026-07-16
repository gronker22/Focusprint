import Foundation

// Reads the active tab out of Google Chrome via Apple Events.
// First use triggers the macOS Automation permission prompt.
enum BrowserTabReader {

    static let chromeBundleID = "com.google.Chrome"

    // Titles can be very long ("Some 90-word article headline - Medium");
    // cap them so rows and charts stay readable
    private static let maxTitleLength = 60

    // Compiled once — NSAppleScript compilation is the expensive part
    private static let script = NSAppleScript(source: """
        tell application "Google Chrome"
            if (count of windows) > 0 then
                return {URL, title} of active tab of front window
            end if
        end tell
        """)

    // The exact page the user is looking at: the tab's title, falling back
    // to the domain when the title is empty. Nil if Chrome has no windows
    // or the user denied Automation access.
    static func activeChromeTab() -> String? {
        var error: NSDictionary?
        guard let descriptor = script?.executeAndReturnError(&error),
              descriptor.numberOfItems >= 2 else { return nil }

        let urlString = descriptor.atIndex(1)?.stringValue ?? ""
        let title = (descriptor.atIndex(2)?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !title.isEmpty {
            return title.count > maxTitleLength
                ? String(title.prefix(maxTitleLength - 1)) + "…"
                : title
        }
        guard let host = URL(string: urlString)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
