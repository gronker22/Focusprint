import SwiftUI

struct MenuBarPopoverView: View {
    private enum ViewMode: String, CaseIterable {
        case today = "Today"
        case week = "Week"
    }

    @EnvironmentObject var watcher: AppWatcher
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var viewMode: ViewMode = .today
    @Namespace private var tabNamespace

    var body: some View {
        Group {
            if hasSeenWelcome {
                mainContent
                    .transition(.opacity)
            } else {
                WelcomeView {
                    withAnimation(.spring(duration: 0.45)) {
                        hasSeenWelcome = true
                    }
                }
            }
        }
        .frame(width: 340)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerView
            modePicker
            Divider()
            content
            Divider()
            footerView
        }
    }

    // MARK: — Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Focusprint")
                        .font(.headline)
                    focusChip
                }
                Text(Date(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(watcher.totalTimeToday))
                    .font(.title2.monospacedDigit().weight(.medium))
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .spring(duration: 0.4),
                               value: watcher.totalTimeToday)
                Text("tracked today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // Today's focus score at a glance (scattrd engine)
    @ViewBuilder
    private var focusChip: some View {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let stats = FocusScore.analyze(watcher.fetchSessions(since: todayStart))
        if stats.hasEnoughData {
            Text("\(stats.score)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(
                        stats.score >= 60 ? Color.green
                            : stats.score >= 30 ? Color.orange : Color.red
                    )
                )
                .bubbleHover(scale: 1.1)
                .help("Focus score — sustain \(Int(stats.sustainScore)), switching \(Int(stats.switchScore)), deep work \(Int(stats.deepWorkScore))")
        }
    }

    // MARK: — Today / Week switch (sliding capsule)

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2)) {
                        viewMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.caption.weight(viewMode == mode ? .semibold : .regular))
                        .foregroundStyle(viewMode == mode ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if viewMode == mode {
                                Capsule()
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "selectedTab", in: tabNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .bubbleHover(scale: 1.05)
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary.opacity(0.5)))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: — Content

    // Fixed-height container with a plain crossfade. Move/slide transitions
    // around a ScrollView break NSPopover's height measurement — the list
    // area collapses to zero after a tab switch.
    private var content: some View {
        ZStack {
            switch viewMode {
            case .today:
                appListView
                    .transition(.opacity)
            case .week:
                ChartView()
                    .transition(.opacity)
            }
        }
        .frame(width: 340, height: 380, alignment: .top)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: viewMode)
    }

    private var appListView: some View {
        Group {
            if watcher.todaySummary.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No sessions yet today")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // Plain VStack on purpose: a LazyVStack loses its rows when
                    // this view is removed/re-inserted by the tab transition
                    VStack(spacing: 0) {
                        ForEach(watcher.todaySummary.prefix(12), id: \.app) { item in
                            AppRowView(
                                appName: item.app,
                                duration: item.duration,
                                totalTime: watcher.totalTimeToday,
                                isActive: item.app == watcher.currentAppName && watcher.isTracking
                            )
                        }
                    }
                    // Rows glide when apps trade places in the ranking
                    .animation(reduceMotion ? nil : .spring(duration: 0.5),
                               value: watcher.todaySummary.map(\.app))
                }
            }
        }
        // Coming back from the Week tab: re-pull from SwiftData immediately
        // instead of waiting for the next 5s tick
        .onAppear { watcher.refreshTodaySummary() }
    }

    // MARK: — Footer

    private var footerView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle()
                    .fill(watcher.isTracking ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(watcher.isTracking ? watcher.currentAppName : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                               value: watcher.currentAppName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FooterButton(symbol: "chart.bar.xaxis") {
                NotificationCenter.default.post(name: .openDashboard, object: nil)
            }

            // Cmd+, doesn't reach a menu-bar-only app (no main menu),
            // so Settings needs an explicit button. openSettings is the
            // only route that works reliably from an accessory app.
            FooterButton(symbol: "gearshape") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }

            FooterButton(title: watcher.isTracking ? "Pause" : "Resume") {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) {
                    watcher.toggleTracking()
                }
            }

            FooterButton(title: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// Borderless footer control with a soft hover highlight
private struct FooterButton: View {
    var symbol: String?
    var title: String?
    let action: () -> Void

    init(symbol: String? = nil, title: String? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.action = action
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                } else if let title {
                    Text(title)
                }
            }
            .font(.caption)
            .foregroundStyle(isHovering ? .primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.quaternary.opacity(isHovering ? 0.6 : 0))
            )
        }
        .buttonStyle(.plain)
        .bubbleHover(scale: 1.12)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
