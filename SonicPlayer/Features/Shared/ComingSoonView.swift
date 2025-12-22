import SwiftUI

struct ComingSoonView: View {
    let feature: String
    let icon: String
    let description: String

    var body: some View {
        ZStack {
            Color.sonicBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Icon with gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.sonicPrimary.opacity(0.2), Color.sonicPrimary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)

                    Image(systemName: icon)
                        .font(.system(size: 60))
                        .foregroundStyle(LinearGradient.sonicGradient)
                        .symbolEffect(.pulse)
                }

                // Text content
                VStack(spacing: 16) {
                    Text("Coming Soon")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient.sonicGradient)

                    Text(feature)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)

                    Text(description)
                        .font(.body)
                        .foregroundColor(.sonicTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .lineSpacing(4)
                }

                Spacer()
                Spacer()
            }
        }
        .navigationTitle(feature)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sharing Coming Soon View

struct SharingComingSoonView: View {
    var body: some View {
        ComingSoonView(
            feature: "Sharing",
            icon: "shareplay",
            description: "Share your favorite folders and playlists with friends. Export, import, and sync across devices."
        )
    }
}
