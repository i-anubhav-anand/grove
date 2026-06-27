import SwiftUI
import GroveCore

/// Left-aligned activity marker: icon + text, shimmer while running.
struct ChatMarker: View {
    var icon: String? = nil
    var isRunning: Bool = false
    let label: String
    /// Optional greyish truncated preview shown next to the label (e.g. thinking text).
    var preview: String? = nil
    /// When true, show a +/- affordance reflecting `isExpanded`.
    var expandable: Bool = false
    var isExpanded: Bool = false

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
                .fixedSize()
                .overlay(isRunning ? shimmerOverlay : nil)

            if let preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: ClaudeTheme.messageSize(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(ClaudeTheme.surfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            }

            Spacer(minLength: 4)

            if expandable {
                Image(systemName: isExpanded ? "minus" : "plus")
                    .font(.system(size: ClaudeTheme.messageSize(9), weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
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
