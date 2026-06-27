import Foundation
import GroveCore

/// Workspace (git worktree) CRUD on top of `GitWorktreeService`. Kept in its own
/// file so the core AppState stays focused.
@MainActor
extension AppState {

    /// Workspaces belonging to a project.
    func workspaces(for projectId: UUID) -> [Workspace] {
        workspaces.filter { $0.projectId == projectId }
    }

    /// Create a git worktree on a new branch for the project and record it.
    @discardableResult
    func createWorkspace(projectId: UUID, branch: String, baseRef: String? = nil) async throws -> Workspace {
        guard let project = projects.first(where: { $0.id == projectId }) else {
            throw WorkspaceError.projectNotFound
        }
        let path = try await worktreeService.createWorktree(
            repo: project.path, branch: branch, baseRef: baseRef
        )
        let workspace = Workspace(projectId: projectId, branch: branch, worktreePath: path)
        workspaces.append(workspace)
        try? await persistence.saveWorkspaces(workspaces)
        workspaceChangeCounts[workspace.id] = await WorkspaceStatus.changedFileCount(atPath: path)
        return workspace
    }

    /// New-chat isolation: give a brand-new chat its own git worktree, branched
    /// from the project's remote default on a place-name branch, then select it.
    /// Non-git / empty project folders run in place (no worktree). Best-effort:
    /// on failure the chat falls back to the project root.
    func ensureSessionWorktree(project: Project, in window: WindowState) async {
        let dotGit = URL(fileURLWithPath: project.path).appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: dotGit) else { return }
        let branch = placeBranchName(projectId: project.id)
        // Best-effort: if the worktree can't be created, the chat falls back to
        // the project root (selectedWorkspace stays nil).
        if let workspace = try? await createWorkspace(projectId: project.id, branch: branch) {
            window.selectedWorkspace = workspace
        }
    }

    /// Remove a workspace's worktree and forget it. A `.context` folder in the
    /// worktree (if any) is preserved under `~/Grove/archived-contexts/<repo>/`.
    func deleteWorkspace(_ workspace: Workspace, force: Bool = false) async throws {
        if let project = projects.first(where: { $0.id == workspace.projectId }) {
            archiveContext(of: workspace, project: project)
            try await worktreeService.removeWorktree(
                repo: project.path, path: workspace.worktreePath, force: force
            )
        }
        workspaces.removeAll { $0.id == workspace.id }
        workspaceChangeCounts[workspace.id] = nil
        try? await persistence.saveWorkspaces(workspaces)
    }

    /// Move a worktree's `.context` into `~/Grove/archived-contexts/<repo>/<branch>/`
    /// before the worktree is removed, so shared context survives an archive.
    private func archiveContext(of workspace: Workspace, project: Project) {
        let fm = FileManager.default
        let src = URL(fileURLWithPath: workspace.worktreePath)
            .appendingPathComponent(".context", isDirectory: true)
        guard fm.fileExists(atPath: src.path) else { return }
        let repoName = URL(fileURLWithPath: project.path).lastPathComponent
        let destDir = GroveHome.archivedContexts.appendingPathComponent(repoName, isDirectory: true)
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent(
            workspace.branch.replacingOccurrences(of: "/", with: "-"), isDirectory: true
        )
        try? fm.removeItem(at: dest)
        try? fm.moveItem(at: src, to: dest)
    }

    /// Make a workspace the active context for a window.
    func selectWorkspace(_ workspace: Workspace, in window: WindowState) {
        window.selectedWorkspace = workspace
        if let project = projects.first(where: { $0.id == workspace.projectId }) {
            window.selectedProject = project
        }
    }

    /// Recompute changed-file counts for every workspace (event-driven: called on
    /// launch, on app-activate, and after create/delete — not polled).
    func refreshWorkspaceStatuses() async {
        var counts: [UUID: Int] = [:]
        var stats: [UUID: DiffStat] = [:]
        for ws in workspaces {
            counts[ws.id] = await WorkspaceStatus.changedFileCount(atPath: ws.worktreePath)
            stats[ws.id] = await WorkspaceStatus.diffStat(atPath: ws.worktreePath)
        }
        workspaceChangeCounts = counts
        workspaceDiffStats = stats
        await refreshWorkspacePRStates()
    }

    /// Fetch each workspace's GitHub PR state (open/merged/closed) so the sidebar
    /// branch icon can mirror GitHub's colors. No-op when signed out; skips
    /// workspaces whose project isn't linked to a GitHub repo.
    func refreshWorkspacePRStates() async {
        guard await github.accessToken != nil else { return }
        var states: [UUID: BranchPRState] = [:]
        var prs: [UUID: BranchPR] = [:]
        for ws in workspaces {
            guard let project = projects.first(where: { $0.id == ws.projectId }),
                  let repo = project.gitHubRepo, !repo.isEmpty else { continue }
            if let pr = try? await github.fetchBranchPR(repoFullName: repo, branch: ws.branch) {
                states[ws.id] = pr.state
                prs[ws.id] = pr
            }
        }
        workspacePRStates = states
        workspacePRs = prs
    }

    /// Load persisted workspaces and drop any whose worktree directory is gone
    /// (removed outside the app). Discovery of externally-created worktrees is a
    /// follow-up (see issue #2).
    func loadAndReconcileWorkspaces() async -> [Workspace] {
        let saved = await persistence.loadWorkspaces()
        let fm = FileManager.default
        let alive = saved.filter { fm.fileExists(atPath: $0.worktreePath) }
        // Persist the pruned list only for partial drops. If *every* saved
        // worktree is missing, the storage root likely moved (a migration) rather
        // than the user deleting them all — don't overwrite the file with [] and
        // lose the records. Keep them on disk so they remain recoverable.
        if alive.count != saved.count && !alive.isEmpty {
            try? await persistence.saveWorkspaces(alive)
        }
        return alive
    }

    enum WorkspaceError: LocalizedError {
        case projectNotFound
        var errorDescription: String? {
            switch self {
            case .projectNotFound: return "No project found for that workspace."
            }
        }
    }
}
