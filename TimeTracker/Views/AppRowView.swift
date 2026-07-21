import SwiftUI
import AppKit

struct AppRowView: View {
    let appName: String
    let duration: TimeInterval
    let totalTime: TimeInterval
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var pulsing = false

    private var percentage: Double {
        guard totalTime > 0 else { return 0 }
        return min(duration / totalTime, 1.0)
    }

    // Icons are looked up through a cache: scanning every running app, for
    // every row, on every render was a real cost with the popover open
    private var appIcon: NSImage? { AppIconCache.icon(for: appName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                // App icon (falls back to a generic one)
                Group {
                    if let icon = appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 18, height: 18)

                Text(appName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isActive {
                    liveDot
                }

                Spacer()

                Text(formatDuration(duration))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .spring(duration: 0.4), value: duration)
            }

            // Time-as-a-proportion bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barFill)
                        .frame(width: geo.size.width * percentage, height: 3)
                        .animation(reduceMotion ? nil : .spring(duration: 0.5), value: percentage)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(.quaternary.opacity(isHovering ? 0.4 : 0))
        )
        .padding(.horizontal, 6)
        .bubbleHover(scale: 1.02)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var barFill: some ShapeStyle {
        isActive
            ? AnyShapeStyle(LinearGradient(
                colors: [.accentColor, .accentColor.opacity(0.6)],
                startPoint: .leading,
                endPoint: .trailing
              ))
            : AnyShapeStyle(Color.secondary.opacity(0.5))
    }

    // Green dot with an expanding "sonar" ring while the app is active
    private var liveDot: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(Color.green.opacity(0.6), lineWidth: 1.5)
                    .scaleEffect(pulsing ? 2.6 : 1)
                    .opacity(pulsing ? 0 : 0.8)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}
