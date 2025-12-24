import Foundation
import SwiftUI

struct QuickstartView: View {
    @Binding var hasSeenQuickstart: Bool
    @State private var selection = 0
    private let pages: [QuickstartPageModel]

    init(hasSeenQuickstart: Binding<Bool>) {
        _hasSeenQuickstart = hasSeenQuickstart
        self.pages = QuickstartView.loadPages()
    }

    var body: some View {
        ZStack {
            LinearGradient.sonic(colors: [Color.sonicBackground, Color.sonicSurface])
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button("Skip") {
                        hasSeenQuickstart = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                TabView(selection: $selection) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        QuickstartPage(model: page)
                            .tag(index)
                            .padding(.horizontal, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                QuickstartPageControl(count: pages.count, selection: selection)
                    .padding(.top, 6)
                    .padding(.bottom, 6)

                Button {
                    if selection < pages.count - 1 {
                        withAnimation(.easeInOut) {
                            selection += 1
                        }
                    } else {
                        hasSeenQuickstart = true
                    }
                } label: {
                    Text(selection < pages.count - 1 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .sonicGradientBackground(colors: Color.sonicTealColors, cornerRadius: 18)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private static func loadPages() -> [QuickstartPageModel] {
        guard let url = Bundle.main.url(forResource: "Quickstart", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(QuickstartConfig.self, from: data) else {
            return []
        }

        let mapped = config.pages.compactMap { payload -> QuickstartPageModel? in
            guard let demo = QuickstartDemo(rawValue: payload.demo.lowercased()) else { return nil }
            return QuickstartPageModel(
                title: payload.title,
                message: payload.message,
                systemImage: payload.systemImage,
                colors: colors(from: payload.colors),
                demo: demo,
                actions: payload.actions
            )
        }

        return mapped.isEmpty ? [] : mapped
    }

    private static func colors(from tokens: [String]) -> [Color] {
        if tokens.count == 1 {
            switch tokens[0].lowercased() {
            case "teal":
                return Color.sonicTealColors
            case "blue":
                return Color.sonicBlueColors
            case "orange":
                return Color.sonicOrangeColors
            case "green":
                return Color.sonicGreenColors
            case "purple":
                return Color.sonicPurpleColors
            default:
                break
            }
        }

        let mapped = tokens.compactMap { colorForToken($0) }
        return mapped.isEmpty ? Color.sonicTealColors : mapped
    }

    private static func colorForToken(_ token: String) -> Color? {
        switch token.lowercased() {
        case "sonicprimary":
            return .sonicPrimary
        case "sonicprimarydark":
            return .sonicPrimaryDark
        case "sonicprimarylight":
            return .sonicPrimaryLight
        case "sonicpurple":
            return .sonicPurple
        case "sonicpurpledark":
            return .sonicPurpleDark
        case "sonicpurplelight":
            return .sonicPurpleLight
        case "sonicorange":
            return .sonicOrange
        case "sonicorangedark":
            return .sonicOrangeDark
        case "sonicorangelight":
            return .sonicOrangeLight
        case "sonicgreen":
            return .sonicGreen
        case "sonicgreendark":
            return .sonicGreenDark
        case "sonicgreenlight":
            return .sonicGreenLight
        case "sonicblue":
            return .sonicBlue
        case "sonicbluedark":
            return .sonicBlueDark
        case "sonicbluelight":
            return .sonicBlueLight
        default:
            return nil
        }
    }
}

struct QuickstartPageModel {
    let title: String
    let message: String
    let systemImage: String
    let colors: [Color]
    let demo: QuickstartDemo
    let actions: [QuickstartAction]
}

struct QuickstartPageControl: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == selection ? Color.sonicPrimary : Color.sonicBorder)
                    .frame(width: index == selection ? 8 : 6, height: index == selection ? 8 : 6)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
        .accessibilityLabel("Page \(selection + 1) of \(count)")
    }
}

struct QuickstartPage: View {
    let model: QuickstartPageModel
    @State private var animate = false
    @State private var pulse = false
    private let demoHeight: CGFloat = 170
    private let actionsHeight: CGFloat = 110

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LinearGradient.sonic(colors: model.colors))
                    .frame(width: 105, height: 105)
                    .opacity(0.25)
                    .scaleEffect(animate ? 1.05 : 0.92)

                Circle()
                    .stroke(LinearGradient.sonic(colors: model.colors), lineWidth: 2)
                    .frame(width: 110, height: 110)
                    .opacity(animate ? 0.2 : 0.6)
                    .scaleEffect(animate ? 1.08 : 0.95)

                Image(systemName: model.systemImage)
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(LinearGradient.sonic(colors: model.colors))
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
            }
            
            QuickstartDemoView(demo: model.demo, colors: model.colors)
                .frame(height: demoHeight)


            Text(LocalizedStringKey(model.title))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.sonicTextPrimary)
                .multilineTextAlignment(.center)

            Text(LocalizedStringKey(model.message))
                .font(.body)
                .foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            QuickstartActionsView(actions: model.actions, colors: model.colors)
                .frame(height: actionsHeight)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                animate = true
            }
            if model.demo == .recording || model.demo == .library {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

enum QuickstartDemo: String {
    case home
    case library
    case recording
    case settings
}

struct QuickstartDemoView: View {
    let demo: QuickstartDemo
    let colors: [Color]
    @State private var pulse = false

    private var title: String {
        switch demo {
        case .home:
            return "Home"
        case .library:
            return "Library"
        case .recording:
            return "Recording"
        case .settings:
            return "Settings"
        }
    }

    private var subtitle: String {
        switch demo {
        case .home:
            return "Suggested folders + last played"
        case .library:
            return "Browse folders and import"
        case .recording:
            return "Waveform + trim tools"
        case .settings:
            return "Playback + language"
        }
    }

    private var highlightIcon: String {
        switch demo {
        case .home:
            return "play.fill"
        case .library:
            return "plus"
        case .recording:
            return "record.circle"
        case .settings:
            return "slider.horizontal.3"
        }
    }

    private var tabIcon: String {
        switch demo {
        case .home:
            return "house.fill"
        case .library:
            return "square.stack.3d.up.fill"
        case .recording:
            return "mic.fill"
        case .settings:
            return "gearshape.fill"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                HStack {
                    Text(LocalizedStringKey(title))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)
                    Spacer()
                    ZStack {
                        Image(systemName: highlightIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LinearGradient.sonic(colors: colors))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())

                        if demo == .library || demo == .recording {
                            Circle()
                                .stroke(LinearGradient.sonic(colors: colors), lineWidth: 1.5)
                                .frame(width: 30, height: 30)
                                .scaleEffect(pulse ? 1.5 : 0.9)
                                .opacity(pulse ? 0.0 : 0.5)
                        }
                    }
                }

                demoContent
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient.sonic(colors: colors.map { $0.opacity(0.12) }))
            )

            HStack(spacing: 6) {
                Image(systemName: tabIcon)
                    .font(.caption2)
                    .foregroundColor(.sonicTextSecondary)
                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if demo == .library || demo == .recording {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
    }

    @ViewBuilder
    private var demoContent: some View {
        switch demo {
        case .home:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    demoPill(text: "Library", icon: "square.stack.3d.up.fill", fill: colors)
                    demoPill(text: "Recordings", icon: "mic.fill", fill: colors.reversed())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sonicSurface)
                    .frame(height: 60)
                    .overlay(
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundColor(.sonicPrimary)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder)
                                    .frame(width: 150, height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder.opacity(0.8))
                                    .frame(width: 110, height: 6)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    )
            }
        case .library:
            VStack(spacing: 10) {
                HStack {
                    demoPill(text: "Import", icon: "square.and.arrow.down", fill: colors)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.sonicPrimary)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sonicSurface)
                    .frame(height: 60)
                    .overlay(
                        HStack(spacing: 10) {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundColor(.sonicPrimary)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder)
                                    .frame(width: 140, height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder.opacity(0.8))
                                    .frame(width: 90, height: 6)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    )
            }
        case .recording:
            VStack(spacing: 12) {
                HStack {
                    Text("00:12.48")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextSecondary)
                    Spacer()
                    demoPill(text: "Stop", icon: "stop.fill", fill: [Color.red, Color.red.opacity(0.8)])
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.5), lineWidth: 6)
                                .scaleEffect(pulse ? 1.4 : 0.8)
                                .opacity(pulse ? 0.0 : 0.8)
                        )

                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.sonicSurface)
                        .frame(height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.sonicBorder.opacity(0.6))
                                .frame(width: 160, height: 10),
                            alignment: .leading
                        )
                }
            }
        case .settings:
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sonicSurface)
                    .frame(height: 54)
                    .overlay(
                        HStack(spacing: 10) {
                            Image(systemName: "speedometer")
                                .font(.caption)
                                .foregroundColor(.sonicPrimary)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder)
                                    .frame(width: 140, height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder.opacity(0.8))
                                    .frame(width: 100, height: 6)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    )
            }
        }
    }

    private func demoPill(text: String, icon: String, fill: [Color]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(LocalizedStringKey(text))
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.sonicTextPrimary)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(LinearGradient.sonic(colors: fill.map { $0.opacity(0.18) }), in: Capsule())
    }
}

struct QuickstartAction: Identifiable, Decodable {
    let title: String
    let systemImage: String
    var id: String { "\(title)|\(systemImage)" }
}

struct QuickstartActionsView: View {
    let actions: [QuickstartAction]
    let colors: [Color]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(actions) { action in
                HStack(spacing: 8) {
                    Image(systemName: action.systemImage)
                        .font(.caption)
                        .foregroundStyle(LinearGradient.sonic(colors: colors))
                    Text(LocalizedStringKey(action.title))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct QuickstartConfig: Decodable {
    let pages: [QuickstartPagePayload]
}

struct QuickstartPagePayload: Decodable {
    let title: String
    let message: String
    let systemImage: String
    let colors: [String]
    let demo: String
    let actions: [QuickstartAction]
}
