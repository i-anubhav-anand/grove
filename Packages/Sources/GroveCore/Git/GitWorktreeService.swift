import Foundation

/// Per-workspace git worktree isolation. This is the core trick that lets N Claude
/// Code agents work the *same* repository on *different* branches in parallel without
/// colliding — the thing that turns a single-session chat client into a parallel
/// agent manager.
///
/// A "workspace" in our app = one worktree + one branch + (later) one Claude session.
public actor GitWorktreeService {

    public struct Worktree: Sendable, Equatable {
        public let path: String
        public let branch: String?
        public let head: String
    }

    public enum WorktreeError: LocalizedError {
        case gitFailed(command: String, status: Int32, stderr: String)
        case notAGitRepo(String)

        public var errorDescription: String? {
            switch self {
            case let .gitFailed(command, status, stderr):
                return "git \(command) failed (status \(status)): \(stderr)"
            case let .notAGitRepo(path):
                return "Not a git repository: \(path)"
            }
        }
    }

    /// Base directory where all workspace worktrees live. Each repo gets a
    /// subfolder; each branch a worktree.
    private let baseDir: URL

    public init(baseDir: URL? = nil) {
        self.baseDir = baseDir ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".grove/worktrees", isDirectory: true)
    }

    // MARK: - Public API

    /// Create an isolated worktree for `branch` off the given repo.
    /// Returns the absolute path of the new worktree (the agent's working directory).
    ///
    /// When `baseRef` is nil (the default), the worktree branches from the repo's
    /// remote default branch (`origin/HEAD`) so it always starts from a clean tree
    /// matching the remote, independent of whatever the main checkout currently has
    /// checked out. Pass an explicit ref to override.
    @discardableResult
    public func createWorktree(repo: String, branch: String, baseRef: String? = nil) async throws -> String {
        try await ensureGitRepo(repo)

        let base: String
        if let baseRef {
            base = baseRef
        } else {
            base = await resolveBaseRef(repo: repo)
        }

        let repoName = URL(fileURLWithPath: repo).lastPathComponent
        let dest = baseDir
            .appendingPathComponent(repoName, isDirectory: true)
            .appendingPathComponent(branch.replacingOccurrences(of: "/", with: "-"), isDirectory: true)

        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // `git worktree add -b <branch> <path> <baseRef>` creates the branch and
        // checks it out into an isolated directory in one atomic step.
        _ = try await runGit(
            ["worktree", "add", "-b", branch, dest.path, base],
            cwd: repo
        )
        return dest.path
    }

    /// Pick the best base for a new worktree: the remote default branch
    /// (`origin/HEAD`), falling back through common remote names and finally local
    /// `HEAD` for repos without a remote. Branching from the remote default keeps
    /// new workspaces clean and independent of the main checkout's current state —
    /// the same strategy Claude Code's own worktrees use.
    private func resolveBaseRef(repo: String) async -> String {
        for ref in ["origin/HEAD", "origin/main", "origin/master"] {
            if (try? await runGit(["rev-parse", "--verify", "--quiet", ref], cwd: repo)) != nil {
                return ref
            }
        }
        return "HEAD"
    }

    /// List every worktree attached to the repo (parses `--porcelain` output).
    public func listWorktrees(repo: String) async throws -> [Worktree] {
        try await ensureGitRepo(repo)
        let output = try await runGit(["worktree", "list", "--porcelain"], cwd: repo)
        return Self.parsePorcelain(output)
    }

    /// Remove a worktree and (optionally) delete its branch. `force` discards
    /// uncommitted changes — the archive-cleanup path.
    public func removeWorktree(repo: String, path: String, force: Bool = false) async throws {
        var args = ["worktree", "remove", path]
        if force { args.append("--force") }
        _ = try await runGit(args, cwd: repo)
    }

    // MARK: - Porcelain parsing

    /// Parse `git worktree list --porcelain`. Records are separated by blank lines;
    /// each starts with `worktree <path>`, then optional `HEAD <sha>` and `branch <ref>`.
    static func parsePorcelain(_ text: String) -> [Worktree] {
        var result: [Worktree] = []
        var path: String?
        var head = ""
        var branch: String?

        func flush() {
            if let path { result.append(Worktree(path: path, branch: branch, head: head)) }
            path = nil; head = ""; branch = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { flush(); continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            switch parts.first {
            case "worktree": path = parts.count > 1 ? parts[1] : nil
            case "HEAD":     head = parts.count > 1 ? parts[1] : ""
            case "branch":   branch = parts.count > 1 ? parts[1].replacingOccurrences(of: "refs/heads/", with: "") : nil
            default:         break
            }
        }
        flush()
        return result
    }

    // MARK: - Process plumbing

    private func ensureGitRepo(_ repo: String) async throws {
        var isDir: ObjCBool = false
        let dotGit = URL(fileURLWithPath: repo).appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir) else {
            throw WorktreeError.notAGitRepo(repo)
        }
    }

    @discardableResult
    private func runGit(_ args: [String], cwd: String) async throws -> String {
        let proc = Process()
        let out = Pipe()
        let err = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.standardOutput = out
        proc.standardError = err

        try proc.run()
        // Read pipes fully before awaiting exit to avoid deadlock on large output.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            throw WorktreeError.gitFailed(
                command: args.joined(separator: " "),
                status: proc.terminationStatus,
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
