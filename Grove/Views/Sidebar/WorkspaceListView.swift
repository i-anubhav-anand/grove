import SwiftUI
import GroveCore

/// Sidebar that groups **Project → Workspaces → Sessions**. Each workspace is a
/// git worktree on its own branch; selecting one sets `windowState.selectedWorkspace`.
/// Floating (legacy) sessions with no workspace appear directly under their project.
struct WorkspaceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    @State private var creatingForProject: Project?
    @State private var pendingArchive: Workspace?

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
                            ForEach(appState.workspaces(for: project.id)) { ws in
                                workspaceRow(ws, project: project)
                                // Sessions only expand under the selected workspace —
                                // keeps the list flat and uncluttered otherwise.
                                if windowState.selectedWorkspace?.id == ws.id {
                                    ForEach(sessions(workspaceId: ws.id, projectId: project.id)) { s in
                                        sessionRow(s, indented: true)
                                    }
                                }
                            }
                            ForEach(floatingSessions(projectId: project.id)) { s in
                                sessionRow(s, indented: false)
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
            .help("New workspace (git worktree)")
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

    private func workspaceRow(_ ws: Workspace, project: Project) -> some View {
        let isSelected = windowState.selectedWorkspace?.id == ws.id
        return HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: ClaudeTheme.size(11)))
                .foregroundStyle(branchColor(ws))
                .help(prStateHelp(ws))
            Text(ws.displayName)
                .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                .lineLimit(1)
            Spacer()
            if let d = appState.workspaceDiffStats[ws.id], !d.isEmpty {
                HStack(spacing: 3) {
                    Text("+\(d.added)").foregroundStyle(ClaudeTheme.statusSuccess)
                    Text("-\(d.deleted)").foregroundStyle(ClaudeTheme.statusError)
                }
                .font(.system(size: ClaudeTheme.size(9), weight: .medium, design: .monospaced))
            }
            if workspaceIsStreaming(ws) {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background(isSelected ? ClaudeTheme.accent.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
        .onTapGesture { appState.selectWorkspace(ws, in: windowState) }
        .contextMenu {
            Button {
                appState.selectWorkspace(ws, in: windowState)
                appState.startNewChat(in: windowState)
            } label: { Label("New session here", systemImage: "square.and.pencil") }
            Divider()
            Menu {
                ForEach(WorkspaceStatus.allCases, id: \.self) { status in
                    Button {
                        appState.setStatus(status, for: ws)
                    } label: {
                        if ws.status == status {
                            Label(status.label, systemImage: "checkmark")
                        } else {
                            Text(status.label)
                        }
                    }
                }
            } label: { Label("Status", systemImage: "circle.dashed") }
            Divider()
            Button(role: .destructive) { archive(ws) } label: {
                Label("Archive workspace", systemImage: "archivebox")
            }
        }
    }

    private func sessionRow(_ summary: ChatSession.Summary, indented: Bool) -> some View {
        let isCurrent = appState.currentSession(in: windowState)?.id == summary.id
        let streaming = appState.backgroundStreamingSessionIds(in: windowState).contains(summary.id)
        return HStack(spacing: 4) {
            Text(summary.title)
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)
            Spacer()
            if streaming { ProgressView().controlSize(.mini) }
            if summary.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: ClaudeTheme.size(8)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
        }
        .padding(.vertical, 1)
        .padding(.leading, indented ? 18 : 0)
        .contentShape(Rectangle())
        .background(isCurrent ? ClaudeTheme.accent.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
        .onTapGesture { appState.selectSession(id: summary.id, in: windowState) }
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

    // MARK: - Data

    private var visibleProjects: [Project] {
        if let selected = windowState.selectedProject, windowState.isProjectWindow {
            return [selected]
        }
        return appState.projects
    }

    private func workspaces(for projectId: UUID, status: WorkspaceStatus) -> [Workspace] {
        appState.workspaces(for: projectId).filter { $0.status == status }
    }

    private func sessions(workspaceId: UUID, projectId: UUID) -> [ChatSession.Summary] {
        appState.allSessionSummaries
            .filter { $0.projectId == projectId && $0.workspaceId == workspaceId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func floatingSessions(projectId: UUID) -> [ChatSession.Summary] {
        appState.allSessionSummaries
            .filter { $0.projectId == projectId && $0.workspaceId == nil }
            .sorted { ($0.isPinned ? 1 : 0, $0.updatedAt) > ($1.isPinned ? 1 : 0, $1.updatedAt) }
    }

    private func workspaceIsStreaming(_ ws: Workspace) -> Bool {
        let streaming = appState.backgroundStreamingSessionIds(in: windowState)
        return appState.allSessionSummaries.contains {
            $0.workspaceId == ws.id && streaming.contains($0.id)
        }
    }
}
