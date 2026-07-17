import SwiftUI

// The scattrd side of the merged app: focus score, streak, golden hours and
// the monthly App Villain — rendered in Timeprint's card language
// Pure view: all analytics are computed once in DashboardModel and passed in,
// so scrolling never re-runs them
struct FocusCardsView: View {
    let focus: FocusDayStats
    let streakCurrent: Int
    let streakBest: Int
    let streakGoal: Int
    let golden: FocusFeatures.GoldenWindow
    let villain: FocusFeatures.Villain

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                scoreCard(focus)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    streakCard
                    goldenHoursCard(golden)
                }
                .frame(width: 260)
            }
            villainCard(villain)
        }
    }

    // MARK: — Card scaffold (matches DashboardView styling)

    private func card<Content: View>(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        .bubbleHover(scale: 1.01)
    }

    // MARK: — Focus score

    private func scoreCard(_ stats: FocusDayStats) -> some View {
        card("Focus today", subtitle: "40% sustain · 35% switching · 25% deep work") {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 2) {
                    Text(stats.hasEnoughData ? "\(stats.score)" : "—")
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                        .foregroundStyle(scoreColor(stats.score, hasData: stats.hasEnoughData))
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    subScoreRow("Sustain", stats.sustainScore)
                    subScoreRow("Switching", stats.switchScore)
                    subScoreRow("Deep work", stats.deepWorkScore)
                }
            }
            HStack(spacing: 16) {
                miniStat("\(stats.switches)", "distraction switches")
                miniStat("\(stats.deepWorkBlocks)", "focus blocks (12m+)")
                miniStat(formatDuration(stats.longestFocusMinutes * 60), "longest block")
            }
            .padding(.top, 4)
        }
    }

    private func subScoreRow(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.4))
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: geo.size.width * min(value / 100, 1))
                }
            }
            .frame(height: 6)
            Text("\(Int(value))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .bubbleHover(scale: 1.03)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .bubbleHover(scale: 1.04)
    }

    private func scoreColor(_ score: Int, hasData: Bool) -> Color {
        guard hasData else { return .secondary }
        return score >= 60 ? .green : score >= 30 ? .orange : .red
    }

    // MARK: — Streak

    private var streakCard: some View {
        card("Focus streak", subtitle: "days scoring \(streakGoal)+") {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(streakCurrent > 0 ? .orange : .secondary)
                Text("\(streakCurrent)")
                    .font(.title.monospacedDigit().weight(.bold))
                Text(streakCurrent == 1 ? "day" : "days")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("best \(streakBest)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: — Golden hours

    private func goldenHoursCard(_ window: FocusFeatures.GoldenWindow) -> some View {
        card("Golden hours", subtitle: "your recurring peak-focus window") {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(window.valid ? .yellow : .secondary)
                Text(window.valid ? window.label : "Not enough history")
                    .font(window.valid ? .title3.weight(.semibold) : .callout)
                    .foregroundStyle(window.valid ? .primary : .secondary)
                Spacer()
            }
        }
    }

    // MARK: — App Villain

    private func villainCard(_ villain: FocusFeatures.Villain) -> some View {
        card("App villain", subtitle: villain.periodLabel) {
            if villain.valid {
                HStack(spacing: 14) {
                    Image(systemName: "theatermasks.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(villain.tie
                             ? "\(villain.app) & \(villain.runnerUp ?? "")"
                             : villain.app)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        Text(villain.tie
                             ? "neck and neck — each ~\(villain.pct)% of your \(villain.totalSwitches) context switches"
                             : "pulled you away \(villain.switchIns) times — \(villain.pct)% of your \(villain.totalSwitches) context switches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !villain.tie, let runnerUp = villain.runnerUp {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("runner-up")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(runnerUp) (\(villain.runnerUpPct)%)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                Text("No villain yet — once you log some distraction switches, the month's biggest attention thief is exposed here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
