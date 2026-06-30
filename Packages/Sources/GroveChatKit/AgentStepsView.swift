import SwiftUI
import GroveCore

/// Depth view for a subagent run — the steps it took, shown as an indented rail
/// under the parent Agent/Task row. Adapted from the prompt-kit Steps component.
struct AgentStepsView: View {
    let run: SubagentRun

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let type = run.agentType, !type.isEmpty, !run.steps.isEmpty {
                Text(type.uppercased())
                    .font(.system(size: ClaudeTheme.messageSize(9), weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .padding(.bottom, 4)
            }

            ForEach(run.steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: step.icon)
                        .font(.system(size: ClaudeTheme.messageSize(9)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                        .frame(width: 14)
                    Text(step.label)
                        .font(.system(
                            size: ClaudeTheme.messageSize(11),
                            design: step.kind == .tool ? .monospaced : .default
                        ))
                        .foregroundStyle(step.kind == .text ? ClaudeTheme.textSecondary : ClaudeTheme.textTertiary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            // Left rail connecting the steps.
            Rectangle()
                .fill(ClaudeTheme.border)
                .frame(width: 1)
        }
    }
}
