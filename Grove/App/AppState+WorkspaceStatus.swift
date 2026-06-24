import Foundation
import GroveCore

/// Board-status mutation for workspaces. Kept separate from the worktree CRUD in
/// AppState+Workspaces so the status board (issue #7) owns its own surface.
@MainActor
extension AppState {

    /// Set a workspace's board status and persist the workspace list.
    func setStatus(_ status: WorkspaceStatus, for workspace: Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }),
              workspaces[idx].status != status else { return }
        workspaces[idx].status = status
        let snapshot = workspaces
        Task { try? await persistence.saveWorkspaces(snapshot) }
    }
}
