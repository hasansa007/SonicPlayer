import SwiftUI

/// A screen's top line: where you are on the left, what is happening on the right (#6).
///
/// **With no breadcrumb the status centres**, which is not a special case so much as the same rule
/// read honestly — the status is the only thing there, so it belongs in the middle. That is what
/// gives the recording screen its centred `● RECORDING` without the contract needing a field for it.
struct DialChrome: View {

    let chrome: DialScreen.Chrome
    /// Back is navigation, so it lives up here with the breadcrumb it pops.
    var onCommand: (DialCommand) -> Void = { _ in }

    @State private var isPulsing = false

    private var hasBreadcrumb: Bool { !chrome.breadcrumb.isEmpty }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if chrome.canGoBack {
                Button {
                    onCommand(.action("back"))
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicPrimary)
                        // A hit area the size of a real target, drawn as a small chevron. The glyph
                        // is chrome; the thing you press is not allowed to be chrome-sized.
                        .frame(width: Sizing.tapTarget, height: Sizing.compactControl, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Back"))
            }

            if hasBreadcrumb {
                Text(chrome.breadcrumb.joined(separator: " ▸ "))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(DialFont.breadcrumbTracking)
                    .foregroundColor(.sonicTextMuted)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer(minLength: Spacing.sm)
            }

            if chrome.isRecording || chrome.status != nil {
                // Tappable, and that is the point: `hold` jumps to Now Playing from anywhere and
                // has no affordance at all. This line is already on screen saying something is
                // playing, so making it the way in costs nothing and finally gives that gesture a
                // visible partner.
                Button { onCommand(.action("nowPlaying")) } label: { status }
                    .accessibilityLabel(Text("Now playing"))
                    .accessibilityHint(Text(chrome.status ?? ""))
            }
        }
        .frame(maxWidth: .infinity, alignment: hasBreadcrumb ? .leading : .center)
        // `.contain`, not `.combine`. Combining flattens the children into one label — which was
        // right when this row was three pieces of text, and silently swallows the Back chevron and
        // the status button now that two of them are controls.
        .accessibilityElement(children: .contain)
    }

    private var status: some View {
        HStack(spacing: Spacing.sm) {
            if chrome.isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: Spacing.sm, height: Spacing.sm)
                    // Opacity *and* scale, because a dot that only dims reads as a rendering
                    // artefact at this size while one that also breathes reads as alive.
                    .opacity(isPulsing ? Self.pulseFloor : 1)
                    .scaleEffect(isPulsing ? Self.pulseFloor : 1)
                    .animation(Motion.recordPulse, value: isPulsing)
                    .onAppear { isPulsing = true }
                    .accessibilityHidden(true)
            }

            if let status = chrome.status {
                Text(status)
                    .font(.caption2)
                    .fontWeight(chrome.isRecording ? .semibold : .medium)
                    .tracking(chrome.isRecording ? DialFont.breadcrumbTracking : 0)
                    .monospacedDigit()
                    .foregroundColor(chrome.isRecording ? .red : .sonicPrimary)
                    .lineLimit(1)
            }
        }
    }

    private static let pulseFloor: Double = 0.45
}
