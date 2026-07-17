import SwiftUI
import SwiftData
import ServiceManagement

// Opened with Cmd+, or the popover gear
struct SettingsView: View {
    @AppStorage("idleThresholdMinutes") private var idleThresholdMinutes: Int = 2
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("showMenuBarTotal") private var showMenuBarTotal: Bool = false
    @AppStorage("showMenuBarScore") private var showMenuBarScore: Bool = true
    @AppStorage("streakGoal") private var streakGoal: Int = 60

    // Recent sessions feed the category list (Settings scene has the container)
    @Query(sort: \AppSessionModel.startTime, order: .reverse)
    private var recentSessions: [AppSessionModel]
    @State private var categoryRefresh = 0

    @State private var excludedBundleIDs: [String] = []
    @State private var newExclusion: String = ""
    @State private var loginItemError: String?
    // Prevents the error-revert of the toggle from re-triggering onChange
    @State private var isSyncingLoginItem = false

    var body: some View {
        Form {
            trackingSection
            focusSection
            categoriesSection
            exclusionsSection
            systemSection
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .navigationTitle("Settings")
        .onAppear(perform: load)
    }

    // MARK: — Focus

    private var focusSection: some View {
        Section("Focus") {
            Picker("Streak goal", selection: $streakGoal) {
                Text("Score 40+").tag(40)
                Text("Score 50+").tag(50)
                Text("Score 60+").tag(60)
                Text("Score 70+").tag(70)
            }
            .pickerStyle(.menu)
            Text("Days at or above this focus score extend your streak.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: — Categories

    // Top keys (apps/domains) from the last 7 days, heaviest first
    private var recentCategoryKeys: [(key: String, category: AppCategory)] {
        _ = categoryRefresh
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var totals: [String: TimeInterval] = [:]
        var categories: [String: AppCategory] = [:]
        for session in recentSessions where session.startTime >= weekAgo {
            totals[session.categoryKey, default: 0] += session.duration
            categories[session.categoryKey] = session.category
        }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { (key: $0.key, category: categories[$0.key] ?? .neutral) }
    }

    private var categoriesSection: some View {
        Section("Categories") {
            if recentCategoryKeys.isEmpty {
                Text("Apps and sites you use will appear here for labeling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentCategoryKeys, id: \.key) { item in
                    Picker(selection: Binding(
                        get: { item.category },
                        set: { newCategory in
                            CategoryOverrides.apply(key: item.key, category: newCategory)
                            categoryRefresh += 1
                        }
                    )) {
                        ForEach(AppCategory.allCases, id: \.self) { category in
                            Text(category.label).tag(category)
                        }
                    } label: {
                        Text(item.key)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .pickerStyle(.menu)
                }
                Text("Labels drive the focus score — only Distraction counts as a context switch. Changes apply to all history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: — Sections

    private var trackingSection: some View {
        Section("Tracking") {
            Picker("Idle timeout", selection: $idleThresholdMinutes) {
                Text("1 minute").tag(1)
                Text("2 minutes").tag(2)
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
            }
            .pickerStyle(.menu)
            Text("Stop counting time after this many minutes of no input.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var exclusionsSection: some View {
        Section("Excluded apps") {
            ForEach(excludedBundleIDs, id: \.self) { bundleID in
                HStack {
                    Text(bundleID)
                        .font(.callout.monospaced())
                    Spacer()
                    Button {
                        excludedBundleIDs.removeAll { $0 == bundleID }
                        saveExclusions()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Bundle ID, e.g. com.apple.Safari", text: $newExclusion)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addExclusion)
                Button("Add", action: addExclusion)
                    .disabled(newExclusion.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Time in these apps is not tracked.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var systemSection: some View {
        Section("System") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    applyLaunchAtLogin(enabled)
                }
            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("Show focus score in the menu bar", isOn: $showMenuBarScore)
            Toggle("Show today's total in the menu bar", isOn: $showMenuBarTotal)
        }
    }

    // MARK: — Actions

    private func load() {
        excludedBundleIDs = UserDefaults.standard
            .stringArray(forKey: "excludedBundleIDs") ?? ["com.apple.finder"]

        // The OS is the source of truth for login-item state (the user can
        // change it in System Settings behind our back)
        isSyncingLoginItem = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isSyncingLoginItem = false
    }

    private func saveExclusions() {
        UserDefaults.standard.set(excludedBundleIDs, forKey: "excludedBundleIDs")
    }

    private func addExclusion() {
        let bundleID = newExclusion.trimmingCharacters(in: .whitespaces)
        guard !bundleID.isEmpty, !excludedBundleIDs.contains(bundleID) else { return }
        excludedBundleIDs.append(bundleID)
        saveExclusions()
        newExclusion = ""
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard !isSyncingLoginItem else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't update login item: \(error.localizedDescription)"
            isSyncingLoginItem = true
            launchAtLogin = !enabled
            isSyncingLoginItem = false
        }
    }
}
