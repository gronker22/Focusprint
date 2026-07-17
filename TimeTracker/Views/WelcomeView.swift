import SwiftUI

// First-launch screen shown inside the popover until the user starts tracking
struct WelcomeView: View {
    let onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconVisible = false
    @State private var ringProgress: CGFloat = 0
    @State private var visibleFeatures = 0
    @State private var buttonVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            icon
            Text("Focusprint")
                .font(.title2.weight(.semibold))
                .padding(.top, 18)
            Text("The print your time leaves behind")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 14) {
                feature(0, symbol: "chart.bar.fill",
                        title: "Automatic tracking",
                        detail: "Every app switch is recorded — no timers to start.")
                feature(1, symbol: "moon.zzz.fill",
                        title: "Idle aware",
                        detail: "Time stops counting when you step away.")
                feature(2, symbol: "square.and.arrow.up",
                        title: "Your data, yours",
                        detail: "Stored locally, exportable to CSV anytime.")
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)

            Spacer(minLength: 20)

            Button(action: onStart) {
                Text("Start Tracking")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .bubbleHover(scale: 1.03)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .opacity(buttonVisible ? 1 : 0)
            .offset(y: buttonVisible ? 0 : 12)
        }
        .frame(width: 340, height: 470)
        .background(backgroundWash)
        .onAppear(perform: runIntro)
    }

    // MARK: — Pieces

    private var icon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.9), .accentColor.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 74, height: 74)
                .shadow(color: .accentColor.opacity(0.35), radius: 16, y: 6)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 52, height: 52)
            Image(systemName: "clock.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
        }
        .scaleEffect(iconVisible ? 1 : 0.5)
        .opacity(iconVisible ? 1 : 0)
    }

    private func feature(_ index: Int, symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(visibleFeatures > index ? 1 : 0)
        .offset(x: visibleFeatures > index ? 0 : 14)
        .bubbleHover(scale: 1.03)
    }

    private var backgroundWash: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.10), .clear],
            startPoint: .top,
            endPoint: .center
        )
    }

    // MARK: — Intro choreography

    private func runIntro() {
        guard !reduceMotion else {
            iconVisible = true
            ringProgress = 1
            visibleFeatures = 3
            buttonVisible = true
            return
        }
        withAnimation(.spring(duration: 0.55, bounce: 0.35)) {
            iconVisible = true
        }
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            ringProgress = 1
        }
        for index in 0..<3 {
            withAnimation(.spring(duration: 0.45).delay(0.45 + Double(index) * 0.13)) {
                visibleFeatures = index + 1
            }
        }
        withAnimation(.spring(duration: 0.5).delay(0.95)) {
            buttonVisible = true
        }
    }
}
