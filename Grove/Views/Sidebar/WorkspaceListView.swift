import SwiftUI
import GroveCore

/// Sidebar that groups **Project → Workspaces → Sessions**. Each workspace is a
/// git worktree on its own branch; selecting one sets `windowState.selectedWorkspace`.
/// Floating (legacy) sessions with no workspace appear directly under their project.
///
/// Includes a minimal "+ workspace" create affordance so the feature is usable now;
/// the fuller create/manage flow (repo picker, archive guards) is issue #5.
struct WorkspaceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    @State private var creatingForProject: Project?
    @State private var newBranch = ""
    @State private var isCreating = false

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
                                ForEach(sessions(workspaceId: ws.id, projectId: project.id)) { s in
                                    sessionRow(s, indented: true)
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
            createSheet(project)
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
                newBranch = ""
                creatingForProject = project
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: ClaudeTheme.size(10)))
            }
            .buttonStyle(.borderless)
            .help("New workspace (git worktree)")
        }
    }

    // MARK: - Rows

    private func workspaceRow(_ ws: Workspace, project: Project) -> some View {
        let isSelected = windowState.selectedWorkspace?.id == ws.id
        return HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: ClaudeTheme.size(10)))
                .foregroundStyle(ClaudeTheme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(ws.displayName)
                    .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                    .lineLimit(1)
                Text(URL(fileURLWithPath: ws.worktreePath).lastPathComponent)
                    .font(.system(size: ClaudeTheme.size(10)))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            // Status slot — issue #4 fills this with running/changes badges.
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
            Button(role: .destructive) {
                Task { try? await appState.deleteWorkspace(ws, force: true) }
            } label: { Label("Archive workspace", systemImage: "archivebox") }
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

    // MARK: - Create sheet (minimal — full flow is #5)

    private func createSheet(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New workspace in \(project.name)")
                .font(.headline)
            Text("Creates a git worktree on a new branch.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Branch name (e.g. feature/login)", text: $newBranch)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { creatingForProject = nil }
                Button("Create") { create(in: project) }
                    .keyboardShortcut(.return)
                    .disabled(newBranch.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func create(in project: Project) {
        let branch = newBranch.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else { return }
        isCreating = true
        Task {
            do {
                let ws = try await appState.createWorkspace(projectId: project.id, branch: branch)
                appState.selectWorkspace(ws, in: windowState)
                creatingForProject = nil
            } catch {
                windowState.errorMessage = error.localizedDescription
                windowState.showError = true
            }
            isCreating = false
        }
    }

    // MARK: - Data

    private var visibleProjects: [Project] {
        if let selected = windowState.selectedProject,
           windowState.isProjectWindow {
            return [selected]
        }
        return appState.projects
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
