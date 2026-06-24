import SwiftUI
import GroveCore

/// Sidebar that groups **Workspace (repo/folder) → Sessions**. Each session is one
/// chat backed by its own git worktree; the row shows the worktree's branch icon
/// (PR-colored) and diff stats. Selecting a session restores its worktree.
struct WorkspaceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    @State private var creatingForProject: Project?
    @State private var pendingArchive: Workspace?
    @State private var pendingDeleteSession: ChatSession.Summary?
    @State private var pendingDeleteProject: Project?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if visibleProjects.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(visibleProjects) { project in
                        Section {
                            ForEach(sessions(for: project.id)) { summary in
                                sessionRow(summary, project: project)
                            }
                        } header: {
                            projectHeader(project)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .sheet(item: $creatingForProject) { project in
            NewWorkspaceSheet(preselectedProject: project)
        }
        .alert("Archive workspace?", isPresented: archiveAlertBinding, presenting: pendingArchive) { ws in
            Button("Force archive", role: .destructive) {
                Task { try? await appState.deleteWorkspace(ws, force: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { ws in
            Text("The worktree for “\(ws.displayName)” has uncommitted changes (or couldn't be removed cleanly). Force-remove it and discard those changes?")
        }
        .alert("Delete session?", isPresented: deleteSessionAlertBinding, presenting: pendingDeleteSession) { summary in
            Button("Delete", role: .destructive) {
                Task { await deleteSessionAndWorktree(summary) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { summary in
            Text("Delete “\(summary.title)” and its worktree? The chat history and any uncommitted changes in the worktree are removed. This can't be undone.")
        }
        .alert("Delete workspace?", isPresented: deleteProjectAlertBinding, presenting: pendingDeleteProject) { project in
            Button("Delete", role: .destructive) {
                Task { await appState.deleteProject(project, in: windowState) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("Remove “\(project.name)” and its sessions? Worktrees are deleted. If Grove created this repo (under ~/Grove/repos) the folder is removed too; an externally opened folder is left in place.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Workspaces")
                .font(.system(size: ClaudeTheme.size(12), weight: .semibold))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .textCase(.uppercase)
            Spacer()
        }
    }

    private func projectHeader(_ project: Project) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: ClaudeTheme.size(10)))
                .foregroundStyle(ClaudeTheme.accent.opacity(0.8))
            Text(project.name)
                .font(.system(size: ClaudeTheme.size(11), weight: .semibold))
                .lineLimit(1)
            Spacer()
            Button {
                creatingForProject = project
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: ClaudeTheme.size(10)))
            }
            .buttonStyle(.borderless)
            .help("New session")
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeleteProject = project
            } label: {
                Label("Delete workspace", systemImage: "trash")
            }
        }
    }

    /// Status subsection header (one per non-empty status within a project).
    private func statusHeader(_ status: WorkspaceStatus, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 7, height: 7)
            Text(status.label)
                .font(.system(size: ClaudeTheme.size(10), weight: .semibold))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .textCase(.uppercase)
            Spacer()
            Text("\(count)")
                .font(.system(size: ClaudeTheme.size(10)))
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .padding(.top, 4)
        .padding(.leading, 4)
    }

    /// Branch-icon color mirroring GitHub's PR state: green open, purple merged,
    /// red closed, neutral when the branch has no PR (or we're signed out).
    private func branchColor(_ ws: Workspace) -> Color {
        switch appState.workspacePRStates[ws.id] {
        case .open:   return ClaudeTheme.statusSuccess
        case .merged: return Color(red: 0.54, green: 0.34, blue: 0.90) // GitHub merged purple
        case .closed: return ClaudeTheme.statusError
        case nil:     return ClaudeTheme.textSecondary
        }
    }

    private func prStateHelp(_ ws: Workspace) -> String {
        switch appState.workspacePRStates[ws.id] {
        case .open:   return "PR open"
        case .merged: return "PR merged"
        case .closed: return "PR closed"
        case nil:     return ws.branch
        }
    }

    /// Dot color per board status.
    private func statusColor(_ status: WorkspaceStatus) -> Color {
        switch status {
        case .backlog: return .secondary
        case .inProgress: return .blue
        case .inReview: return .orange
        case .done: return .green
        }
    }

    // MARK: - Rows

    /// One row per chat session. Shows the worktree's branch icon (PR-colored) and
    /// diff stats when the session is backed by a worktree; click selects it.
    private func sessionRow(_ summary: ChatSession.Summary, project: Project) -> some View {
        let workspace = summary.workspaceId.flatMap { wid in appState.workspaces.first { $0.id == wid } }
        let isCurrent = appState.currentSession(in: windowState)?.id == summary.id
        let streaming = appState.backgroundStreamingSessionIds(in: windowState).contains(summary.id)
        return HStack(spacing: 8) {
            if let ws = workspace {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(branchColor(ws))
                    .help(prStateHelp(ws))
            }
            Text(summary.title)
                .font(.system(size: ClaudeTheme.size(12), weight: isCurrent ? .medium : .regular))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let ws = workspace, let d = appState.workspaceDiffStats[ws.id], !d.isEmpty {
                HStack(spacing: 3) {
                    Text("+\(d.added)").foregroundStyle(ClaudeTheme.statusSuccess)
                    Text("-\(d.deleted)").foregroundStyle(ClaudeTheme.statusError)
                }
                .font(.system(size: ClaudeTheme.size(9), weight: .medium, design: .monospaced))
            }
            if streaming { ProgressView().controlSize(.mini) }
            if summary.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: ClaudeTheme.size(8)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(isCurrent ? ClaudeTheme.accent.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
        .onTapGesture { appState.selectSession(id: summary.id, in: windowState) }
        .contextMenu {
            if let ws = workspace {
                Button { archive(ws) } label: {
                    Label("Archive worktree", systemImage: "archivebox")
                }
            }
            Button(role: .destructive) {
                pendingDeleteSession = summary
            } label: {
                Label("Delete session", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: ClaudeTheme.size(20)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            Text("No projects yet")
                .font(.system(size: ClaudeTheme.size(13)))
                .foregroundStyle(ClaudeTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    /// Try a clean archive first; if the worktree is dirty (or removal fails),
    /// surface a force-confirm alert.
    private func archive(_ ws: Workspace) {
        Task {
            do {
                try await appState.deleteWorkspace(ws, force: false)
            } catch {
                pendingArchive = ws
            }
        }
    }

    private var archiveAlertBinding: Binding<Bool> {
        Binding(get: { pendingArchive != nil }, set: { if !$0 { pendingArchive = nil } })
    }

    private var deleteSessionAlertBinding: Binding<Bool> {
        Binding(get: { pendingDeleteSession != nil }, set: { if !$0 { pendingDeleteSession = nil } })
    }

    private var deleteProjectAlertBinding: Binding<Bool> {
        Binding(get: { pendingDeleteProject != nil }, set: { if !$0 { pendingDeleteProject = nil } })
    }

    /// Delete a session's chat history and, if it has one, its worktree.
    private func deleteSessionAndWorktree(_ summary: ChatSession.Summary) async {
        if let wid = summary.workspaceId, let ws = appState.workspaces.first(where: { $0.id == wid }) {
            try? await appState.deleteWorkspace(ws, force: true)
        }
        await appState.deleteSession(summary.makeSession(), in: windowState)
    }

    // MARK: - Data

    private var visibleProjects: [Project] {
        if let selected = windowState.selectedProject, windowState.isProjectWindow {
            return [selected]
        }
        return appState.projects
    }

    /// All chat sessions for a project, pinned first then most-recent.
    private func sessions(for projectId: UUID) -> [ChatSession.Summary] {
        appState.allSessionSummaries
            .filter { $0.projectId == projectId }
            .sorted { ($0.isPinned ? 1 : 0, $0.updatedAt) > ($1.isPinned ? 1 : 0, $1.updatedAt) }
    }
}
