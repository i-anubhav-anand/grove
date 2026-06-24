import SwiftUI
import GroveCore

/// Horizontal chat-tab strip above the chat: the selected project's (and, when a
/// workspace is selected, that workspace's) sessions as tabs with active
/// highlight, close, and a "+". ⌘T opens a new chat; ⌘⇧W closes the active one.
struct WorkspaceChatTabs: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(chatTabs) { tab(for: $0) }
                    if windowState.currentSessionId == nil {
                        newDraftPill
                    }
                }
            }
            Spacer(minLength: 4)
            Button { appState.startNewChat(in: windowState) } label: {
                Image(systemName: "plus")
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("New chat (⌘T)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(ClaudeTheme.surfaceElevated)
        .background {
            Button("") { appState.startNewChat(in: windowState) }
                .keyboardShortcut("t", modifiers: .command).hidden()
            Button("") { closeActive() }
                .keyboardShortcut("w", modifiers: [.command, .shift]).hidden()
        }
    }

    private var chatTabs: [ChatSession.Summary] {
        guard let pid = windowState.selectedProject?.id else { return [] }
        let ws = windowState.selectedWorkspace
        return appState.allSessionSummaries
            .filter { s in
                guard s.projectId == pid else { return false }
                // If a workspace is selected, prefer its sessions but keep the
                // project's unbound (floating) sessions visible too.
                guard let ws else { return true }
                return s.workspaceId == nil || s.workspaceId == ws.id
            }
            .sorted { ($0.isPinned ? 1 : 0, $0.updatedAt) > ($1.isPinned ? 1 : 0, $1.updatedAt) }
            .prefix(12)
            .map { $0 }
    }

    private func tab(for s: ChatSession.Summary) -> some View {
        let isActive = windowState.currentSessionId == s.id
        return HStack(spacing: 6) {
            Text(s.title.isEmpty ? "New Session" : s.title)
                .font(.system(size: ClaudeTheme.size(11), weight: isActive ? .medium : .regular))
                .lineLimit(1)
            Button {
                Task { await appState.deleteSession(s.makeSession(), in: windowState) }
            } label: {
                Image(systemName: "xmark").font(.system(size: ClaudeTheme.size(8)))
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(isActive ? ClaudeTheme.accent.opacity(0.18) : ClaudeTheme.surfacePrimary,
                    in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(isActive ? ClaudeTheme.textPrimary : ClaudeTheme.textSecondary)
        .contentShape(Rectangle())
        .onTapGesture { appState.selectSession(id: s.id, in: windowState) }
        .help(s.title)
    }

    private var newDraftPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.and.pencil").font(.system(size: ClaudeTheme.size(9)))
            Text("New").font(.system(size: ClaudeTheme.size(11), weight: .medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(ClaudeTheme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(ClaudeTheme.textPrimary)
    }

    private func closeActive() {
        guard let id = windowState.currentSessionId,
              let s = appState.allSessionSummaries.first(where: { $0.id == id }) else { return }
        Task { await appState.deleteSession(s.makeSession(), in: windowState) }
    }
}
