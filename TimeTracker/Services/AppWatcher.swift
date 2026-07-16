import Foundation
import AppKit
import Combine
import SwiftData

// The one live, in-progress session. Completed sessions live in SwiftData
// as AppSessionModel — this struct only ever describes "right now".
struct AppSession {
    let appName: String
    let bundleIdentifier: String
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

    // Internal (not private) so the reports extension can fetch too
    let modelContext: ModelContext

    private var currentSession: AppSession?
    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?
    private var idleTimer: Timer?

    // Read live from defaults so Settings changes apply without a restart
    var idleThreshold: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: "idleThresholdMinutes")
        return TimeInterval((minutes > 0 ? minutes : 2) * 60)
    }

    var excludedBundleIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? ["com.apple.finder"])
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
    }

    // MARK: — Timers

    private func startTick() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isTracking else { return }
            self.refreshBrowserTab()
            self.refreshTodaySummary()
        }
    }

    // MARK: — Browser tab tracking

    // When Chrome is frontmost, split sessions per tab title instead of
    // lumping everything under "Google Chrome"
    private func refreshBrowserTab() {
        guard
            !isIdle,
            let frontmost = NSWorkspace.shared.frontmostApplication,
            let bundleID = frontmost.bundleIdentifier,
            bundleID == BrowserTabReader.chromeBundleID,
            !excludedBundleIDs.contains(bundleID),
            let tab = BrowserTabReader.activeChromeTab()
        else { return }

        let tabName = "\(tab) · Google Chrome"
        guard tabName != currentSession?.appName else { return }

        closeCurrentSession(at: Date())
        currentAppName = tabName
        currentSession = AppSession(
            appName: tabName,
            bundleIdentifier: bundleID,
            startTime: Date()
        )
    }

    private func startIdleCheck() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
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
        // If we just switched into Chrome, refine to the active tab right away
        refreshBrowserTab()
        refreshTodaySummary()
    }

    private func closeCurrentSession(at endTime: Date) {
        guard let session = currentSession else { return }
        currentSession = nil

        // Sub-second sessions are switch-through noise, not real usage
        guard endTime.timeIntervalSince(session.startTime) >= 1 else { return }

        modelContext.insert(AppSessionModel(
            appName: session.appName,
            bundleIdentifier: session.bundleIdentifier,
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

        var totals: [String: TimeInterval] = [:]
        for session in fetchSessions(since: todayStart) {
            totals[session.appName, default: 0] += session.duration
        }
        if let live = currentSession, isTracking, !isIdle {
            totals[live.appName, default: 0] += live.duration
        }

        todaySummary = totals
            .map { (app: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
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
