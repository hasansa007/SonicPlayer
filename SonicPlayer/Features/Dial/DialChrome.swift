import SwiftUI

/// A screen's top line: where you are on the left, Settings in the corner (#6).
///
/// **It says nothing about playback any more.** The `20:34 ▸ playing` label that used to sit at the
/// trailing edge is on the Now Playing row now — a row has the width to name the track *and* carry
/// the clock, which is the whole reason the label lost that argument. What is left up here is
/// navigation plus the recording dot, and the dot stays because a live take has no row of its own.
///
/// With no breadcrumb the row centres, which is the same rule read honestly rather than a special
/// case — whatever is up there is the only thing up there, so it belongs in the middle.
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

            // Before Settings, so the gear keeps the corner it was given.
            if chrome.isRecording {
                recordingDot
            }

            if chrome.showsSettings {
                Button {
                    onCommand(.action("settings"))
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundColor(.sonicTextSecondary)
                        .frame(width: Sizing.tapTarget, height: Sizing.compactControl, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Settings"))
            }
        }
        .frame(maxWidth: .infinity, alignment: hasBreadcrumb ? .leading : .center)
        // `.contain`, not `.combine`. Combining flattens the children into one label, which would
        // swallow the Back chevron and the gear now that both of them are controls.
        .accessibilityElement(children: .contain)
    }

    /// The only thing up here that is neither navigation nor a label: something is being captured
    /// right now, on a screen that may be nowhere near the recorder.
    private var recordingDot: some View {
        Circle()
            .fill(Color.red)
            .frame(width: Spacing.sm, height: Spacing.sm)
            // Opacity *and* scale, because a dot that only dims reads as a rendering artefact at
            // this size while one that also breathes reads as alive.
            .opacity(isPulsing ? Self.pulseFloor : 1)
            .scaleEffect(isPulsing ? Self.pulseFloor : 1)
            .animation(Motion.recordPulse, value: isPulsing)
            .onAppear { isPulsing = true }
            .accessibilityElement()
            .accessibilityLabel(Text("Recording"))
    }

    private static let pulseFloor: Double = 0.45
}
