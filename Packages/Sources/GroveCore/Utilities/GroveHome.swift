import Foundation

/// Grove's visible home on disk, mirroring Conductor's `~/conductor/{repos,workspaces}`
/// layout:
///
/// ```
/// ~/Grove/
/// ├── repos/<project>/                 base clones (canonical checkout, stays on default branch)
/// ├── workspaces/<project>/<branch>/   per-session git worktrees, grouped by repo
/// └── archived-contexts/<project>/     .context dirs preserved when a worktree is removed
/// ```
public enum GroveHome {
    /// `~/Grove`
    public static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Grove", isDirectory: true)
    }

    /// `~/Grove/repos` — base clones / quick-start projects.
    public static var repos: URL { root.appendingPathComponent("repos", isDirectory: true) }

    /// `~/Grove/workspaces` — per-session worktrees (`<repo>/<branch>`).
    public static var workspaces: URL { root.appendingPathComponent("workspaces", isDirectory: true) }

    /// `~/Grove/archived-contexts` — `.context` folders kept after a worktree is removed.
    public static var archivedContexts: URL { root.appendingPathComponent("archived-contexts", isDirectory: true) }

    /// Whether `path` lives inside `~/Grove/repos` (i.e. Grove created/owns it, so it's
    /// safe to delete on disk — as opposed to an externally "opened" folder).
    public static func isManagedRepo(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path
            .hasPrefix(repos.standardizedFileURL.path + "/")
    }

    /// Create the directory tree if missing. Call once on launch.
    public static func bootstrap() {
        for dir in [repos, workspaces, archivedContexts] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
