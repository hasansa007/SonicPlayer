import SwiftUI
import UIKit

/// One item in a list: an optional selection control, a leading tile, a title, a secondary line
/// and an optional trailing accessory (#48).
///
/// **This is the shared Row ADR 0002 deferred out of slice 1.** It now has the second and third
/// consumers that earn it:
///
/// | Consumer | Shape |
/// |---|---|
/// | `CollectionsView` file rows | tile + title + duration/date, selectable |
/// | Home's recent list (`AppView`) | the same, plus the collection label |
/// | `PlayerView`'s queue | position marker instead of a tile, no selection |
///
/// It replaces `MediaFileRowView` and the queue row that #47 deliberately left inline. It also
/// replaces nothing else on purpose: `FileItemRow` — 111 lines, a 56pt tile, a chevron and a
/// press animation — had **zero consumers** and is deleted rather than absorbed.
struct SonicRow<Trailing: View>: View {

    /// What sits in the leading column.
    enum Leading {
        /// An artwork tile, or the gradient placeholder. Files and collections.
        case tile(image: UIImage?, side: CGFloat, fallbackSystemImage: String)
        /// A fixed-width marker. The queue's track number, and the speaker glyph for the one
        /// that is playing — both in the same width so titles stay aligned as it moves.
        case marker(systemImage: String?, text: String?)
    }

    let leading: Leading
    let title: String
    /// Rendered under the title. Already-formatted text — a row does no formatting.
    let secondary: SonicRowSecondary
    var isEmphasised: Bool = false
    var isSelected: Bool = false
    /// `nil` hides the selection control entirely rather than showing an unchecked circle.
    var selection: Bool?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.md) {
            if let selection {
                Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                    .font(.sonicControlGlyph)
                    .foregroundColor(selection ? .sonicPrimary : .sonicTextMuted)
                    .accessibilityHidden(true)
            }

            leadingView

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(isEmphasised ? .subheadline.weight(.semibold) : .body)
                    .foregroundColor(.sonicTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                secondary
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Color.sonicPrimary.opacity(ControlTint.on))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var leadingView: some View {
        switch leading {
        case .tile(let image, let side, let fallback):
            ArtworkView(
                image: image,
                side: side,
                cornerRadius: Radius.sm,
                shadow: nil
            )
            .overlay {
                if image == nil {
                    Image(systemName: fallback)
                        .font(.caption)
                        .foregroundColor(.white)
                        .accessibilityHidden(true)
                }
            }

        case .marker(let systemImage, let text):
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundColor(.sonicPrimary)
                } else if let text {
                    Text(text)
                        .foregroundColor(.sonicTextSecondary)
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .frame(width: Spacing.xxl)
        }
    }
}

extension SonicRow where Trailing == EmptyView {
    init(
        leading: Leading,
        title: String,
        secondary: SonicRowSecondary,
        isEmphasised: Bool = false,
        isSelected: Bool = false,
        selection: Bool? = nil
    ) {
        self.init(
            leading: leading,
            title: title,
            secondary: secondary,
            isEmphasised: isEmphasised,
            isSelected: isSelected,
            selection: selection,
            trailing: { EmptyView() }
        )
    }
}

/// The secondary line, as a small set of shapes rather than an arbitrary view.
///
/// Constrained on purpose: the whole point of a shared Row is that two screens cannot drift into
/// two different secondary lines. A caller that needs something not here should add a case, so
/// the addition is visible in review.
struct SonicRowSecondary: View {

    private let parts: [Part]

    private enum Part {
        case text(String)
        case labelled(systemImage: String, text: String)
    }

    /// Duration alone — the player's queue.
    static func duration(_ text: String) -> SonicRowSecondary {
        SonicRowSecondary(parts: [.text(text)])
    }

    /// Duration and date — the file browser.
    static func durationAndDate(_ duration: String, _ date: String) -> SonicRowSecondary {
        SonicRowSecondary(parts: [.text(duration), .text(date)])
    }

    /// Duration, date and the collection it lives in — Home's recent list.
    static func durationDateAndCollection(
        _ duration: String,
        _ date: String,
        _ collection: String?
    ) -> SonicRowSecondary {
        var parts: [Part] = [.text(duration), .text(date)]
        if let collection {
            parts.append(.labelled(systemImage: "folder.fill", text: collection))
        }
        return SonicRowSecondary(parts: parts)
    }

    private init(parts: [Part]) {
        self.parts = parts
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    // A separator, not a bullet with meaning — VoiceOver reads the parts as one
                    // combined sentence and does not need to hear "middle dot" between them.
                    Text(verbatim: "·").accessibilityHidden(true)
                }

                switch part {
                case .text(let value):
                    Text(value)
                case .labelled(let systemImage, let value):
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: systemImage).font(.caption2)
                        Text(value).lineLimit(1)
                    }
                }
            }
        }
        .font(.caption)
        .foregroundColor(.sonicTextSecondary)
        .monospacedDigit()
    }
}

#Preview("Three consumers") {
    VStack(spacing: 0) {
        SonicRow(
            leading: .tile(image: nil, side: Sizing.thumbnail, fallbackSystemImage: "waveform"),
            title: "Lecture 3 — Neural Networks",
            secondary: .durationAndDate("49:07", "8 Aug 2026"),
            selection: false
        )
        SonicRow(
            leading: .tile(image: nil, side: Sizing.thumbnail, fallbackSystemImage: "waveform"),
            title: "Interview with Sarah",
            secondary: .durationDateAndCollection("1:00:54", "7 Aug 2026", "Interviews"),
            isSelected: true,
            selection: true
        )
        SonicRow(
            leading: .marker(systemImage: "speaker.wave.3.fill", text: nil),
            title: "Now playing in the queue",
            secondary: .duration("49:07"),
            isEmphasised: true,
            isSelected: true
        )
        SonicRow(
            leading: .marker(systemImage: nil, text: "2"),
            title: "Next in the queue",
            secondary: .duration("51:22")
        )
    }
    .padding(Spacing.lg)
}
