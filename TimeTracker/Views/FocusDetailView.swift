import SwiftUI

// Opened by clicking the "Focus today" card: relabel apps/sites as
// deep work / communication / distraction (chip grid, like scattrd's
// customize-categories panel) and see this month's distraction leaderboard
struct FocusDetailView: View {
    @EnvironmentObject var watcher: AppWatcher
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var entries: [Entry] = []
    @State private var leaderboard: [FocusFeatures.DistractionEntry] = []

    struct Entry: Identifiable {
        let key: String
        let duration: TimeInterval
        var category: AppCategory
        var hasOverride: Bool
        var id: String { key }
    }

    private var filteredEntries: [Entry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.key.lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Customize categories")
                        .font(.title3.weight(.semibold))
                    Text("Labels drive the focus score — only Distraction counts against you. Changes apply to all history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            TextField("Search apps & sites you've visited…", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FlowLayout(spacing: 8) {
                        ForEach(filteredEntries) { chip($0) }
                    }
                    leaderboardSection
                }
                .padding(.vertical, 2)
            }

            Label("All data stays on your Mac — nothing leaves this device", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 680, height: 560)
        .onAppear(perform: load)
    }

    // MARK: — Chips

    private func chip(_ entry: Entry) -> some View {
        Menu {
            ForEach(AppCategory.allCases, id: \.self) { category in
                Button {
                    setCategory(category, for: entry.key)
                } label: {
                    if category == entry.category {
                        Label(category.label, systemImage: "checkmark")
                    } else {
                        Text(category.label)
                    }
                }
            }
            if entry.hasOverride {
                Divider()
                Button("Reset to automatic") { resetCategory(for: entry.key) }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: entry.category))
                    .frame(width: 7, height: 7)
                Text(entry.key)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(entry.category.label)
                    .font(.caption)
                    .foregroundStyle(color(for: entry.category))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.35), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .bubbleHover(scale: 1.05)
    }

    private func color(for category: AppCategory) -> Color {
        switch category {
        case .deepWork: return .green
        case .communication: return .yellow
        case .distraction: return .red
        case .neutral: return .secondary
        }
    }

    // MARK: — Leaderboard

    @ViewBuilder
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distraction leaderboard — this month")
                .font(.headline)
            if leaderboard.isEmpty {
                Text("Clean sheet so far — nothing labeled Distraction has pulled you away this month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(leaderboard.prefix(8).enumerated()), id: \.element.id) { rank, entry in
                    HStack(spacing: 10) {
                        Text("\(rank + 1)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(rank == 0 ? .red : .secondary)
                            .frame(width: 18)
                        Text(entry.key)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text("\(entry.switchIns)× switched in")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(formatDuration(entry.seconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(rank == 0 ? 0.4 : 0.2), in: RoundedRectangle(cornerRadius: 7))
                    .bubbleHover(scale: 1.02)
                }
            }
        }
    }

    // MARK: — Data

    private func load() {
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let sessions = watcher.fetchSessions(since: monthAgo)

        var totals: [String: TimeInterval] = [:]
        var categories: [String: AppCategory] = [:]
        for session in sessions {
            totals[session.categoryKey, default: 0] += session.duration
            categories[session.categoryKey] = session.category
        }
        let overrides = CategoryOverrides.map
        entries = totals
            .sorted { $0.value > $1.value }
            .map { Entry(key: $0.key, duration: $0.value,
                         category: categories[$0.key] ?? .neutral,
                         hasOverride: overrides[$0.key] != nil) }

        leaderboard = FocusFeatures.distractionLeaderboard(
            byDay: FocusFeatures.sessionsByDay(watcher.fetchSessions(since: .distantPast))
        )
    }

    private func setCategory(_ category: AppCategory, for key: String) {
        CategoryOverrides.apply(key: key, category: category)
        applyLocal(key: key, category: category, hasOverride: true)
    }

    private func resetCategory(for key: String) {
        CategoryOverrides.remove(key: key)
        load()
        NotificationCenter.default.post(name: .categoriesChanged, object: nil)
    }

    private func applyLocal(key: String, category: AppCategory, hasOverride: Bool) {
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index].category = category
            entries[index].hasOverride = hasOverride
        }
        leaderboard = FocusFeatures.distractionLeaderboard(
            byDay: FocusFeatures.sessionsByDay(watcher.fetchSessions(since: .distantPast))
        )
        NotificationCenter.default.post(name: .categoriesChanged, object: nil)
    }
}

// Minimal wrapping layout for the category chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
