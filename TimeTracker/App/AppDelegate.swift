import AppKit
import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var labelTimer: Timer?
    private var dashboardWindow: NSWindow?

    // Shared watcher — created in didFinishLaunching (not as a property
    // initializer) because mainContext must be touched on the main actor
    private(set) var watcher: AppWatcher!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from the Dock — menu bar only
        NSApp.setActivationPolicy(.accessory)

        watcher = AppWatcher(modelContext: PersistenceController.shared.container.mainContext)

        setupStatusItem()
        setupPopover()
        startMenuBarLabelUpdates()

        NotificationCenter.default.addObserver(
            forName: .openDashboard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showDashboard()
        }
    }

    // MARK: — Analytics dashboard window

    private func showDashboard() {
        if dashboardWindow == nil {
            let hosting = NSHostingController(
                rootView: DashboardView().environmentObject(watcher)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Focusprint Analytics"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 920, height: 680))
            // Keep the window (and its view state) alive across closes
            window.isReleasedWhenClosed = false
            window.center()
            dashboardWindow = window
        }
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: — Status bar icon

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Focusprint")
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    // MARK: — Menu bar total label

    private func startMenuBarLabelUpdates() {
        updateMenuBarLabel()

        labelTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenuBarLabel() }
        }

        // React immediately when the Settings toggle flips
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateMenuBarLabel()
        }
    }

    private func updateMenuBarLabel() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let title = NSMutableAttributedString()

        // Focus score first, colored, so it's readable without opening anything
        let showScore = defaults.object(forKey: "showMenuBarScore") as? Bool ?? true
        if showScore {
            let todayStart = Calendar.current.startOfDay(for: Date())
            let stats = FocusScore.analyze(watcher.fetchSessions(since: todayStart))
            if stats.hasEnoughData {
                let color: NSColor = stats.score >= 60 ? .systemGreen
                    : stats.score >= 30 ? .systemOrange : .systemRed
                title.append(NSAttributedString(
                    string: " \(stats.score)",
                    attributes: [
                        .foregroundColor: color,
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    ]
                ))
            }
        }
        if defaults.bool(forKey: "showMenuBarTotal") {
            title.append(NSAttributedString(
                string: " \(formatDuration(watcher.totalTimeToday))",
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                ]
            ))
        }
        button.attributedTitle = title
        // Keeps the title from overlapping the clock symbol
        button.imagePosition = .imageLeading
    }

    // MARK: — Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient  // closes when you click elsewhere
        popover.animates = true

        let rootView = MenuBarPopoverView()
            .environmentObject(watcher)

        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring popover to front so keyboard shortcuts work immediately
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
