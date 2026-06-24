import Foundation

/// Lightweight git change-count for a workspace's worktree. The "is running"
/// half of status is derived from active streams in AppState; this covers the
/// "how many files changed" half.
public enum WorkspaceStatus {

    /// Count changed files from `git status --porcelain` output.
    public static func changedFileCount(porcelain: String) -> Int {
        porcelain
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    /// Run `git status --porcelain` for a path and return the changed-file count.
    /// Returns 0 if the path is not a git repo or the call fails.
    public static func changedFileCount(atPath path: String) async -> Int {
        await Task.detached {
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", path, "status", "--porcelain"]
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            guard (try? proc.run()) != nil else { return 0 }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0,
                  let out = String(data: data, encoding: .utf8) else { return 0 }
            return changedFileCount(porcelain: out)
        }.value
    }
}
