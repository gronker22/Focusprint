import Foundation
import AppKit
import Combine
import SwiftData

// The one live, in-progress session. Completed sessions live in SwiftData
// as AppSessionModel — this struct only ever describes "right now".
struct AppSession {
    let appName: String
    let bundleIdentifier: String
    var host: String? = nil
    let startTime: Date

    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

// Published so SwiftUI views update automatically when tracking data changes
class AppWatcher: ObservableObject {

    @Published var currentAppName: String = ""
    @Published var isTracking: Bool = true
    @Published var isIdle: Bool = false
    @Published private(set) var todaySummary: [(app: String, duration: TimeInterval)] = []
    // Cached so the popover chip and menu bar label never recompute the score
    // themselves — analyzing a full day on every render was pure waste
    @Published private(set) var todayFocus: FocusDayStats = .empty

    // Internal (not private) so the reports extension can fetch too
    let modelContext: ModelContext

    private var currentSession: AppSession?
    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?
    private var idleTimer: Timer?

    // Apple Events block the calling thread, so tab reads run off-main on one
    // serial queue (NSAppleScript can't be shared across threads)
    private let tabQueue = DispatchQueue(label: "com.markos.timetracker.tabreader", qos: .utility)
    private var isReadingTab = false
    private var tabBackoffUntil: Date?
    private var loggedPermissionDenial = false

    // Nobody's looking at the popover most of the time — poll slowly until it
    // opens. This is the single biggest energy win.
    private var isPopoverVisible = false
    private var visibleTickInterval: TimeInterval = 5
    private var hiddenTickInterval: TimeInterval = 60

    // Read live from defaults so Settings changes apply without a restart
    var idleThreshold: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: "idleThresholdMinutes")
        return TimeInterval((minutes > 0 ? minutes : 2) * 60)
    }

    // Never tracked regardless of user settings: the lock screen isn't app
    // usage, and the tracker shouldn't track itself
    private static let hardExcludedBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        Bundle.main.bundleIdentifier ?? "",
    ]

    var excludedBundleIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? ["com.apple.finder"])
            .union(Self.hardExcludedBundleIDs)
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        startWatching()
        startTick()
        startIdleCheck()
        refreshTodaySummary()
    }

    // MARK: — Watching

    private func startWatching() {
        // Listen for app switches
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    let name = app.localizedName
                else { return }
                self?.handleAppSwitch(to: name, bundleID: app.bundleIdentifier ?? "unknown")
            }
            .store(in: &cancellables)

        // Capture whatever is already in the foreground at launch
        if let app = NSWorkspace.shared.frontmostApplication {
            handleAppSwitch(
                to: app.localizedName ?? "Unknown",
                bundleID: app.bundleIdentifier ?? "unknown"
            )
        }

        startSleepWatching()
    }

    // Sleeping with a session open would otherwise bank the whole sleep as
    // usage — close the lid at 6pm, open at 9am, and you'd "work" 15 hours
    private func startSleepWatching() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.willSleepNotification,          // system sleep
            NSWorkspace.screensDidSleepNotification,    // display off
            NSWorkspace.sessionDidResignActiveNotification,  // fast user switch
        ] {
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.suspendForSleep() }
                .store(in: &cancellables)
        }

        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.resumeFromSleep() }
                .store(in: &cancellables)
        }
    }

    private func suspendForSleep() {
        closeCurrentSession(at: Date())
        isIdle = true
    }

    private func resumeFromSleep() {
        guard isTracking else { return }
        isIdle = false
        // Nothing may activate after waking if the same app stays frontmost,
        // so start the new session explicitly
        resumeWithFrontmostApp()
    }

    // MARK: — Timers

    // Called by AppDelegate when the popover opens/closes so the tick slows
    // right down while nothing is on screen — the biggest energy win here
    func setPopoverVisible(_ visible: Bool) {
        guard visible != isPopoverVisible else { return }
        isPopoverVisible = visible
        startTick()
        if visible {
            refreshBrowserTab()
            refreshTodaySummary()
        }
    }

    private func startTick() {
        tickTimer?.invalidate()
        let interval: TimeInterval = isPopoverVisible ? 5 : 60
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, self.isTracking else { return }
            self.refreshBrowserTab()
            self.refreshTodaySummary()
        }
        // Generous tolerance lets macOS coalesce our wakeups with other timers
        // rather than waking the CPU on our own schedule
        timer.tolerance = interval * 0.5
        tickTimer = timer
    }

    // MARK: — Browser tab tracking

    // When a supported browser is frontmost, split sessions per tab title
    // instead of lumping everything under the browser.
    // The Apple Event runs off-main because it's synchronous IPC that can
    // block for seconds if the browser is busy.
    private func refreshBrowserTab() {
        guard
            !isIdle,
            isTracking,
            !isReadingTab,
            let frontmost = NSWorkspace.shared.frontmostApplication,
            let bundleID = frontmost.bundleIdentifier,
            BrowserTabReader.browserBundleIDs.contains(bundleID),
            !excludedBundleIDs.contains(bundleID)
        else { return }

        // Automation denied? Stop hammering it every tick
        if let backoff = tabBackoffUntil, Date() < backoff { return }

        let browserName = frontmost.localizedName ?? "Browser"
        isReadingTab = true
        tabQueue.async { [weak self] in
            let result = BrowserTabReader.activeTab(bundleID: bundleID)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReadingTab = false
                self.applyTabResult(result, bundleID: bundleID, browserName: browserName)
            }
        }
    }

    private func applyTabResult(
        _ result: BrowserTabReader.Result,
        bundleID: String,
        browserName: String
    ) {
        switch result {
        case .permissionDenied:
            // Retry occasionally in case the user grants access later, but
            // log only once — a message per tick was its own energy drain
            tabBackoffUntil = Date().addingTimeInterval(300)
            if !loggedPermissionDenial {
                loggedPermissionDenial = true
                NSLog("Focusprint: Automation permission denied for \(bundleID); "
                      + "tab tracking paused. Grant it in System Settings › Privacy & Security › Automation.")
            }

        case .unavailable:
            break

        case let .tab(label, host):
            tabBackoffUntil = nil
            loggedPermissionDenial = false

            // Still frontmost? The async hop means it might not be
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }

            let tabName = "\(label) · \(browserName)"
            guard tabName != currentSession?.appName else { return }

            closeCurrentSession(at: Date())
            currentAppName = tabName
            currentSession = AppSession(
                appName: tabName,
                bundleIdentifier: bundleID,
                host: host,
                startTime: Date()
            )
        }
    }

    private func startIdleCheck() {
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
        timer.tolerance = 10
        idleTimer = timer
    }

    // MARK: — Core logic

    private func handleAppSwitch(to appName: String, bundleID: String) {
        guard isTracking else { return }

        isIdle = false
        closeCurrentSession(at: Date())
        currentAppName = appName

        // Excluded apps end the previous session but never start one
        if !excludedBundleIDs.contains(bundleID) {
            currentSession = AppSession(
                appName: appName,
                bundleIdentifier: bundleID,
                startTime: Date()
            )
        }
        // If we just switched into a browser, refine to the active tab now
        refreshBrowserTab()
        // Recomputing totals on every alt-tab is wasted work when the popover
        // isn't open; the tick and the menu bar timer keep it current enough
        if isPopoverVisible { refreshTodaySummary() }
    }

    private func closeCurrentSession(at endTime: Date) {
        guard let session = currentSession else { return }
        currentSession = nil

        // Sub-second sessions are switch-through noise, not real usage
        guard endTime.timeIntervalSince(session.startTime) >= 1 else { return }

        modelContext.insert(AppSessionModel(
            appName: session.appName,
            bundleIdentifier: session.bundleIdentifier,
            host: session.host,
            startTime: session.startTime,
            endTime: endTime
        ))
        do {
            try modelContext.save()
        } catch {
            NSLog("TimeTracker: failed to save session — \(error)")
        }
    }

    func toggleTracking() {
        isTracking.toggle()
        if !isTracking {
            // End the open session so we don't count paused time
            closeCurrentSession(at: Date())
            refreshTodaySummary()
        } else {
            resumeWithFrontmostApp()
        }
    }

    private func resumeWithFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        handleAppSwitch(
            to: app.localizedName ?? "Unknown",
            bundleID: app.bundleIdentifier ?? "unknown"
        )
    }

    // MARK: — Idle detection

    private func checkIdle() {
        guard isTracking else { return }

        // Idle means no input of ANY kind, so take the most recent of the two
        let idleSeconds = min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        )

        if !isIdle && idleSeconds >= idleThreshold {
            handleIdle(idleFor: idleSeconds)
        } else if isIdle && idleSeconds < 30 {
            // Input came back without an app switch — restart tracking
            isIdle = false
            resumeWithFrontmostApp()
        }
    }

    func handleIdle(idleFor idleSeconds: TimeInterval) {
        // Backdate the end to when input actually stopped, so the idle
        // stretch we only just noticed isn't counted as usage
        closeCurrentSession(at: Date().addingTimeInterval(-idleSeconds))
        isIdle = true
        refreshTodaySummary()
    }

    // MARK: — Summaries

    func refreshTodaySummary() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todaySessions = fetchSessions(since: todayStart)

        var totals: [String: TimeInterval] = [:]
        for session in todaySessions {
            totals[session.appName, default: 0] += session.duration
        }
        if let live = currentSession, isTracking, !isIdle {
            totals[live.appName, default: 0] += live.duration
        }

        todaySummary = totals
            .map { (app: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }

        // One analysis per tick, shared by the popover chip and menu bar label
        todayFocus = FocusScore.analyze(todaySessions)
    }

    func fetchSessions(since date: Date) -> [AppSessionModel] {
        let descriptor = FetchDescriptor<AppSessionModel>(
            predicate: #Predicate { $0.startTime >= date },
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("TimeTracker: failed to fetch sessions — \(error)")
            return []
        }
    }

    var totalTimeToday: TimeInterval {
        todaySummary.reduce(0) { $0 + $1.duration }
    }
}
