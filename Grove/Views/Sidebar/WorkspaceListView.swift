import SwiftUI
import GroveCore

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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleProjects) { project in
                            VStack(alignment: .leading, spacing: 8) {
                                projectHeader(project)

                                // Sessions nest under the project as sub-items.
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(sessions(for: project.id)) { summary in
                                        let workspace = summary.workspaceId.flatMap { wid in
                                            appState.workspaces.first { $0.id == wid }
                                        }
                                        SessionCardRow(
                                            summary: summary,
                                            workspace: workspace,
                                            isCurrent: appState.currentSession(in: windowState)?.id == summary.id,
                                            isStreaming: appState.isStreaming(summary.id),
                                            prState: workspace.flatMap { appState.workspacePRStates[$0.id] },
                                            diffStat: workspace.flatMap { appState.workspaceDiffStats[$0.id] },
                                            onTap: { appState.selectSession(id: summary.id, in: windowState) },
                                            onArchive: { ws in archive(ws) },
                                            onDelete: { pendingDeleteSession = summary }
                                        )
                                    }
                                }
                                .padding(.leading, 10)
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                    .padding(.vertical, 8)
                }
                // Scroll-fade: fades top and bottom edges like `scroll-fade` CSS class
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear,  location: 0.00),
                            .init(color: .black,  location: 0.06),
                            .init(color: .black,  location: 0.94),
                            .init(color: .clear,  location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
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
            Text("The worktree for \"\(ws.displayName)\" has uncommitted changes (or couldn't be removed cleanly). Force-remove it and discard those changes?")
        }
        .alert("Delete session?", isPresented: deleteSessionAlertBinding, presenting: pendingDeleteSession) { summary in
            Button("Delete", role: .destructive) {
                Task { await deleteSessionAndWorktree(summary) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { summary in
            Text("Delete \"\(summary.title)\" and its worktree? The chat history and any uncommitted changes in the worktree are removed. This can't be undone.")
        }
        .alert("Delete workspace?", isPresented: deleteProjectAlertBinding, presenting: pendingDeleteProject) { project in
            Button("Delete", role: .destructive) {
                Task { await appState.deleteProject(project, in: windowState) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("Remove \"\(project.name)\" and its sessions? Worktrees are deleted. If Grove created this repo (under ~/Grove/repos) the folder is removed too; an externally opened folder is left in place.")
        }
    }

    // MARK: - Header

    private func projectHeader(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: ClaudeTheme.size(15)))
                .foregroundStyle(ClaudeTheme.accent)
            Text(project.name)
                .font(.system(size: ClaudeTheme.size(16), weight: .bold))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .lineLimit(1)
            let count = sessions(for: project.id).count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(ClaudeTheme.surfaceSecondary, in: Capsule())
            }
            Spacer()
            Button {
                creatingForProject = project
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
            .buttonStyle(.borderless)
            .help("New session")
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button(role: .destructive) {
                pendingDeleteProject = project
            } label: {
                Label("Delete workspace", systemImage: "trash")
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

    private func sessions(for projectId: UUID) -> [ChatSession.Summary] {
        appState.allSessionSummaries
            .filter { $0.projectId == projectId }
            .sorted { ($0.isPinned ? 1 : 0, $0.updatedAt) > ($1.isPinned ? 1 : 0, $1.updatedAt) }
    }
}

// MARK: - Session Card Row

private struct SessionCardRow: View {
    let summary: ChatSession.Summary
    let workspace: Workspace?
    let isCurrent: Bool
    let isStreaming: Bool
    let prState: BranchPRState?
    let diffStat: DiffStat?
    let onTap: () -> Void
    let onArchive: (Workspace) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var pulsing = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                // Grip handle
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary.opacity(isHovered ? 0.8 : 0.3))
                    .frame(width: 16)

                // Media — state-driven leading icon (spinner while running)
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(state.tint.opacity(0.15))
                        .frame(width: 28, height: 28)
                    if state == .running {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: state.icon)
                            .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                            .foregroundStyle(state.tint)
                    }
                }

                // Content — title + state description
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                        .foregroundStyle(ClaudeTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        if let ws = workspace {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: ClaudeTheme.size(9)))
                            Text(ws.branch)
                        } else {
                            Text(state.description)
                        }
                    }
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Actions — state badge + diff stat
                VStack(alignment: .trailing, spacing: 3) {
                    Text(state.description)
                        .font(.system(size: ClaudeTheme.size(10), weight: .medium))
                        .foregroundStyle(state.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(state.tint.opacity(0.12), in: Capsule())

                    if let d = diffStat, !d.isEmpty {
                        HStack(spacing: 3) {
                            Text("+\(d.added)").foregroundStyle(ClaudeTheme.statusSuccess)
                            Text("-\(d.deleted)").foregroundStyle(ClaudeTheme.statusError)
                        }
                        .font(.system(size: ClaudeTheme.size(10), weight: .medium, design: .monospaced))
                    }
                }
            }
            .padding(12)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(cardBorder, lineWidth: isStreaming ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onChange(of: isStreaming) { _, streaming in
            if streaming {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            } else {
                pulsing = false
            }
        }
        .contextMenu {
            if let ws = workspace {
                Button { onArchive(ws) } label: {
                    Label("Archive worktree", systemImage: "archivebox")
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete session", systemImage: "trash")
            }
        }
    }

    // MARK: - State (Attachment-style: running / prOpen / merged / closed / status)

    private enum CardState: Equatable {
        case running        // streaming — progress loading
        case prOpen         // PR raised
        case merged         // PR merged
        case closed         // PR closed without merge
        case inProgress
        case inReview
        case done
        case backlog

        var icon: String {
            switch self {
            case .running:    return "circle.dashed"        // (covered by spinner)
            case .prOpen:     return "arrow.triangle.pull"  // PR raised
            case .merged:     return "checkmark.seal.fill"  // PR merged
            case .closed:     return "xmark.circle.fill"
            case .inProgress: return "bolt.fill"
            case .inReview:   return "eye.fill"
            case .done:       return "checkmark.circle.fill"
            case .backlog:    return "clock"
            }
        }

        var description: String {
            switch self {
            case .running:    return "Running"
            case .prOpen:     return "PR open"
            case .merged:     return "Merged"
            case .closed:     return "Closed"
            case .inProgress: return "In Progress"
            case .inReview:   return "In Review"
            case .done:       return "Done"
            case .backlog:    return "Backlog"
            }
        }

        @MainActor var tint: Color {
            switch self {
            case .running:    return ClaudeTheme.statusRunning
            case .prOpen:     return ClaudeTheme.statusSuccess
            case .merged:     return Color(red: 0.54, green: 0.34, blue: 0.90)
            case .closed:     return ClaudeTheme.statusError
            case .inProgress: return .blue
            case .inReview:   return .orange
            case .done:       return ClaudeTheme.statusSuccess
            case .backlog:    return ClaudeTheme.textTertiary
            }
        }
    }

    private var state: CardState {
        if isStreaming { return .running }
        switch prState {
        case .open:   return .prOpen
        case .merged: return .merged
        case .closed: return .closed
        case nil:
            switch workspace?.status {
            case .inProgress: return .inProgress
            case .inReview:   return .inReview
            case .done:       return .done
            default:          return .backlog
            }
        }
    }

    // MARK: - Appearance

    private var cardBackground: Color {
        if isCurrent  { return ClaudeTheme.accent.opacity(0.10) }
        if isStreaming { return ClaudeTheme.accent.opacity(pulsing ? 0.06 : 0.02) }
        if isHovered   { return ClaudeTheme.accent.opacity(0.05) }
        return ClaudeTheme.surfaceSecondary.opacity(0.6)
    }

    private var cardBorder: Color {
        if isCurrent   { return ClaudeTheme.accent.opacity(0.45) }
        if isStreaming  { return ClaudeTheme.accent.opacity(pulsing ? 0.5 : 0.2) }
        return Color.primary.opacity(0.10)
    }
}
