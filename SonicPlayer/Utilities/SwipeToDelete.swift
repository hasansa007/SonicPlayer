import SwiftUI

/// A swipe-to-delete wrapper for non-List rows.
/// Swipe left to reveal a delete action.
struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @GestureState private var drag: CGFloat = 0

    private let deleteWidth: CGFloat = 80
    private let activationThreshold: CGFloat = 50

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            Button {
                performDelete()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "trash.fill")
                        .font(.body)
                    Text("Delete")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(width: deleteWidth)
                .frame(maxHeight: .infinity)
                .background(Color.red)
            }
            .opacity(revealProgress)

            // Foreground content
            content()
                .background(Color.sonicBackground)
                .offset(x: currentOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .updating($drag) { value, state, _ in
                            // Only allow horizontal swipe
                            if abs(value.translation.width) > abs(value.translation.height) {
                                state = min(0, value.translation.width)
                            }
                        }
                        .onEnded { value in
                            if value.translation.width < -activationThreshold {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    offset = -deleteWidth
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    offset = 0
                                }
                            }
                        }
                )
        }
        .clipped()
    }

    private var currentOffset: CGFloat {
        // While dragging, combine gesture offset with state
        let combined = offset + drag
        return max(-deleteWidth, min(0, combined))
    }

    private var revealProgress: Double {
        min(1.0, abs(Double(currentOffset)) / Double(deleteWidth))
    }

    private func performDelete() {
        withAnimation(.easeOut(duration: 0.2)) {
            offset = 0
        }
        onDelete()
    }
}
