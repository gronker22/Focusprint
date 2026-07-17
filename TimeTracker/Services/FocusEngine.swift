import Foundation

// A merged, categorized block of continuous same-app time
struct FocusBlock {
    let appName: String
    let categoryKey: String
    let category: AppCategory
    let start: Date
    let end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct FocusDayStats {
    var score: Int
    var switches: Int
    var longestFocusMinutes: Double
    var deepWorkBlocks: Int
    var activeMinutes: Double
    var hasEnoughData: Bool
    var sustainScore: Double
    var switchScore: Double
    var deepWorkScore: Double
    var blocks: [FocusBlock]

    static let empty = FocusDayStats(
        score: 0, switches: 0, longestFocusMinutes: 0, deepWorkBlocks: 0,
        activeMinutes: 0, hasEnoughData: false,
        sustainScore: 0, switchScore: 0, deepWorkScore: 0, blocks: []
    )
}

// scattrd's FocusScore engine (scoring v7), ported verbatim onto Focusprint's
// SwiftData sessions. Score = 40% sustain + 35% switching + 25% deep work.
enum FocusScore {

    // --- Tunable constants (identical to scattrd) ---------------------------
    static let sustainTargetMinutes = 10.0
    static let switchDecay = 30.0
    static let totalSwitchDecay = 60.0
    static let distractionSwitchWeight = 0.7
    static let totalSwitchWeight = 0.3
    static let deepWorkTargetMinutes = 25.0
    static let deepWorkTotalTargetMinutes = 45.0
    static let deepWorkLongestWeight = 0.6
    static let deepWorkTotalWeight = 0.4
    static let deepWorkMinMinutes = 12.0
    static let minActiveSeconds = 180.0
    static let mergeMaxGapSeconds = 120.0
    // -------------------------------------------------------------------------

    // THE single definition of a counted context switch: you landed in a
    // distraction. Everything else is treated as productive.
    static func isContextSwitch(_ category: AppCategory) -> Bool {
        category == .distraction
    }

    static func workBlocks(in blocks: [FocusBlock]) -> [FocusBlock] {
        blocks.filter {
            $0.category != .distraction && $0.duration >= deepWorkMinMinutes * 60
        }
    }

    static func medianMinutes(_ blocks: [FocusBlock]) -> Double {
        let mins = blocks.map { $0.duration / 60 }.sorted()
        guard !mins.isEmpty else { return 0 }
        let n = mins.count
        return n % 2 == 1 ? mins[n / 2] : (mins[n / 2 - 1] + mins[n / 2]) / 2
    }

    // Merge consecutive same-app sessions across short gaps (v7: never across
    // long idle gaps, so idle wall-clock time is never counted as focus)
    static func blocks(from sessions: [AppSessionModel]) -> [FocusBlock] {
        var blocks: [FocusBlock] = []
        for session in sessions {
            let end = session.endTime ?? Date()
            guard end.timeIntervalSince(session.startTime) >= 1 else { continue }
            if let last = blocks.last, last.appName == session.appName,
               session.startTime.timeIntervalSince(last.end) <= mergeMaxGapSeconds {
                blocks[blocks.count - 1] = FocusBlock(
                    appName: last.appName, categoryKey: last.categoryKey,
                    category: last.category, start: last.start, end: end
                )
            } else {
                blocks.append(FocusBlock(
                    appName: session.appName, categoryKey: session.categoryKey,
                    category: session.category, start: session.startTime, end: end
                ))
            }
        }
        return blocks
    }

    static func analyze(_ sessions: [AppSessionModel]) -> FocusDayStats {
        let blocks = blocks(from: sessions)
        let activeSeconds = blocks.reduce(0) { $0 + $1.duration }
        guard activeSeconds >= minActiveSeconds, !blocks.isEmpty else {
            return .empty
        }

        var switches = 0
        for i in 1..<max(1, blocks.count) where isContextSwitch(blocks[i].category) {
            switches += 1
        }

        let activeHours = activeSeconds / 3600
        let distractionSwitchesPerHour = activeHours > 0 ? Double(switches) / activeHours : 0

        // Fragmentation transitions: only changes that TOUCH a distraction
        // count — switching between productive contexts is free
        var fragTransitions = 0
        for i in 1..<max(1, blocks.count)
        where isContextSwitch(blocks[i].category) || isContextSwitch(blocks[i - 1].category) {
            fragTransitions += 1
        }
        let fragSwitchesPerHour = activeHours > 0 ? Double(fragTransitions) / activeHours : 0

        let medianBlockMinutes = medianMinutes(blocks)
        let longestMinutes = (blocks.map { $0.duration }.max() ?? 0) / 60

        let dw = workBlocks(in: blocks)
        let longestDeepWorkMinutes = (dw.map { $0.duration }.max() ?? 0) / 60
        let totalDeepWorkMinutes = dw.reduce(0) { $0 + $1.duration } / 60

        // Sustain: median block length, so one long block can't mask fragmentation
        let sustain = min(100, medianBlockMinutes / sustainTargetMinutes * 100)

        // Switching: blend distraction-only switching with distraction-involved
        // fragmentation
        let distractionSwitching = 100 * exp(-distractionSwitchesPerHour / switchDecay)
        let totalSwitching = 100 * exp(-fragSwitchesPerHour / totalSwitchDecay)
        let switchScore = distractionSwitchWeight * distractionSwitching
                        + totalSwitchWeight * totalSwitching

        // Focus work: longest qualifying block blended with total qualifying time
        let longestComponent = min(100, longestDeepWorkMinutes / deepWorkTargetMinutes * 100)
        let totalComponent = min(100, totalDeepWorkMinutes / deepWorkTotalTargetMinutes * 100)
        let deepWork = deepWorkLongestWeight * longestComponent
                     + deepWorkTotalWeight * totalComponent

        let score = Int((0.40 * sustain + 0.35 * switchScore + 0.25 * deepWork).rounded())

        return FocusDayStats(
            score: max(0, min(100, score)),
            switches: switches,
            longestFocusMinutes: longestMinutes,
            deepWorkBlocks: dw.count,
            activeMinutes: activeSeconds / 60,
            hasEnoughData: true,
            sustainScore: sustain,
            switchScore: switchScore,
            deepWorkScore: deepWork,
            blocks: blocks
        )
    }
}
