import SwiftUI
import GroveCore

/// Shared 20×20 icon button used across the inspector chrome (tab bar contextual actions, terminal
/// dock controls, Changes header). One size, one hover affordance, one help-tooltip pattern.
///
/// Pass `tint` to pin a colour (e.g. accent when a toggle is active); leave it nil for the default
/// secondary colour that brightens to `textPrimary` on hover.
struct InspectorIconButton: View {
    let systemName: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                .foregroundStyle(tint ?? (hovered ? ClaudeTheme.textPrimary : ClaudeTheme.textSecondary))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovered = $0 }
    }
}
