import SwiftUI

struct WaveformView: View {
    let isPlaying: Bool
    let barCount: Int
    let barWidth: CGFloat
    let baseHeight: CGFloat
    let amplitudeRange: ClosedRange<CGFloat>

    @State private var phases: [CGFloat] // Initialized based on barCount
    
    init(isPlaying: Bool, barCount: Int = 14, barWidth: CGFloat = 8, baseHeight: CGFloat = 30, amplitudeRange: ClosedRange<CGFloat> = 10...50) {
        self.isPlaying = isPlaying
        self.barCount = barCount
        self.barWidth = barWidth
        self.baseHeight = baseHeight
        self.amplitudeRange = amplitudeRange
        _phases = State(initialValue: Array(repeating: 0, count: barCount))
    }

    var body: some View {
        HStack(spacing: barWidth / 2) { // Adjusted spacing
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 4) // Dynamic corner radius
                    .frame(width: barWidth, height: baseHeight + phases[index])
                    .animation(
                        isPlaying ? 
                            .easeInOut(duration: 0.4).repeatForever().delay(Double(index) * 0.1) : 
                            .easeOut(duration: 0.2), 
                        value: phases[index]
                    )
            }
        }
        .onAppear {
            if isPlaying { startAnimation() }
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue { startAnimation() } else { stopAnimation() }
        }
    }
    
    func startAnimation() {
        for i in 0..<barCount {
            phases[i] = CGFloat.random(in: amplitudeRange)
        }
    }
    
    func stopAnimation() {
        for i in 0..<barCount {
            phases[i] = 0
        }
    }
}
