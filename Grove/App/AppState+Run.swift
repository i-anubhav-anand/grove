import Foundation
import GroveCore

// MARK: - Run Script

/// State and logic backing the Run pane (⌘R). Resolves the working directory,
/// reads/writes the per-project run script, and persists changes.
extension AppState {

    /// Directory the run script executes in: the selected workspace's worktree,
    /// falling back to the selected project's root.
    func runWorkingDirectory(in window: WindowState) -> String? {
        window.selectedWorkspace?.worktreePath ?? window.selectedProject?.path
    }

    /// The run script configured for the window's selected project, if any.
    func runScript(in window: WindowState) -> String? {
        window.selectedProject?.runScript
    }

    /// Update the selected project's run script and persist it. An empty/blank
    /// string clears the script (stored as nil).
    func setRunScript(_ script: String?, in window: WindowState) {
        guard let projectId = window.selectedProject?.id else { return }

        let trimmed = script?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed

        if let idx = projects.firstIndex(where: { $0.id == projectId }) {
            projects[idx].runScript = value
        }
        // Keep the window's cached copy in sync so the UI reflects the change immediately.
        window.selectedProject?.runScript = value

        let snapshot = projects
        Task { try? await persistence.saveProjects(snapshot) }
    }
}
