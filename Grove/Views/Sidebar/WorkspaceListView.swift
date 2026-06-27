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

    private func projectHeader(_ project: Project) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: ClaudeTheme.size(10)))
                .foregroundStyle(ClaudeTheme.accent.opacity(0.8))
            Text(project.name)
                .font(.system(size: ClaudeTheme.size(11), weight: .medium))
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

    private func sessionRow(_ summary: ChatSession.Summary, project: Project) -> some View {
        let workspace = summary.workspaceId.flatMap { wid in appState.workspaces.first { $0.id == wid } }
        let isCurrent = appState.currentSession(in: windowState)?.id == summary.id
        let streaming = appState.isStreaming(summary.id)
        let prState = workspace.flatMap { appState.workspacePRStates[$0.id] }
        let diffStat = workspace.flatMap { appState.workspaceDiffStats[$0.id] }
        let status = workspace?.status ?? .inProgress

        return SessionCardRow(
            summary: summary,
            workspace: workspace,
            isCurrent: isCurrent,
            isStreaming: streaming,
            status: status,
            prState: prState,
            diffStat: diffStat
        ) {
            appState.selectSession(id: summary.id, in: windowState)
        }
        .contextMenu {
            if let ws = workspace {
                Button { archive(ws) } label: {
                    Label("Archive worktree", systemImage: "archivebox")
                }
            }
            Button(role: .destructive) { pendingDeleteSession = summary } label: {
                Label("Delete session", systemImage: "trash")
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
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

// MARK: - Session Card Row

/// Card-style session row inspired by sortable list pattern:
/// [status icon] | title + branch subtitle | [status badge] [diff stats]
private struct SessionCardRow: View {
    let summary: ChatSession.Summary
    let workspace: Workspace?
    let isCurrent: Bool
    let isStreaming: Bool
    let status: WorkspaceStatus
    let prState: BranchPRState?
    let diffStat: DiffStat?
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {

            // Status icon box
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(statusColor)
                }
            }

            // Title + branch subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(ClaudeTheme.textPrimary)
                    .lineLimit(1)

                if let branch = workspace?.branch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                            .foregroundStyle(branchColor)
                        Text(branch)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: status badge + diff stats
            VStack(alignment: .trailing, spacing: 4) {
                // Status badge
                Text(status.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15), in: Capsule())

                // Diff stats
                if let d = diffStat, !d.isEmpty {
                    HStack(spacing: 3) {
                        Text("+\(d.added)")
                            .foregroundStyle(ClaudeTheme.statusSuccess)
                        Text("-\(d.deleted)")
                            .foregroundStyle(ClaudeTheme.statusError)
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isCurrent
                        ? ClaudeTheme.accent.opacity(0.1)
                        : isHovered ? ClaudeTheme.surfacePrimary.opacity(0.7) : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isCurrent
                        ? ClaudeTheme.accent.opacity(0.35)
                        : isHovered ? ClaudeTheme.border : Color.clear,
                    lineWidth: 0.5
                )
        )
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }

    private var statusColor: Color {
        switch status {
        case .backlog:    return ClaudeTheme.textTertiary
        case .inProgress: return ClaudeTheme.accent
        case .inReview:   return .orange
        case .done:       return ClaudeTheme.statusSuccess
        }
    }

    private var statusIcon: String {
        switch status {
        case .backlog:    return "clock"
        case .inProgress: return "bolt.fill"
        case .inReview:   return "eye.fill"
        case .done:       return "checkmark"
        }
    }

    private var branchColor: Color {
        switch prState {
        case .open:   return ClaudeTheme.statusSuccess
        case .merged: return Color(red: 0.54, green: 0.34, blue: 0.90)
        case .closed: return ClaudeTheme.statusError
        case nil:     return ClaudeTheme.textTertiary
        }
    }
}
