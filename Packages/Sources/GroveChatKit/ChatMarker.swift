import SwiftUI
import GroveCore

/// Left-aligned activity marker: icon + text, shimmer while running.
struct ChatMarker: View {
    var icon: String? = nil
    var isRunning: Bool = false
    let label: String

    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            if isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .tint(ClaudeTheme.textTertiary)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: ClaudeTheme.messageSize(10), weight: .medium))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }

            Text(label)
                .font(.system(size: ClaudeTheme.messageSize(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .lineLimit(1)
                .overlay(isRunning ? shimmerOverlay : nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    // Sweeping shimmer: a bright band moves left→right over the text.
    @ViewBuilder
    private var shimmerOverlay: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: ClaudeTheme.textTertiary.opacity(0.9), location: 0.5),
                    .init(color: .clear, location: 0.75),
                ],
                startPoint: .init(x: shimmerPhase - 0.5, y: 0),
                endPoint:   .init(x: shimmerPhase + 0.5, y: 0)
            )
            .blendMode(.sourceAtop)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            shimmerPhase = -0.5
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.5
            }
        }
    }
}
