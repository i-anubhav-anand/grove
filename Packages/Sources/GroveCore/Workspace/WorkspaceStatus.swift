import Foundation

/// Added/deleted line totals for a worktree's working changes.
public struct DiffStat: Equatable, Sendable {
    public let added: Int
    public let deleted: Int
    public init(added: Int = 0, deleted: Int = 0) {
        self.added = added
        self.deleted = deleted
    }
    public var isEmpty: Bool { added == 0 && deleted == 0 }
}

/// Board status for a workspace — backlog / in-progress / in-review / done.
///
/// Also namespaces the lightweight git helpers: the "is running" half of status
/// is derived from active streams in AppState; these statics cover changed-file
/// count and +/- line stats.
public enum WorkspaceStatus: String, Codable, Sendable, CaseIterable {
    case backlog
    case inProgress
    case inReview
    case done

    /// Title-cased label for section headers and menus.
    public var label: String {
        switch self {
        case .backlog: return "Backlog"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .done: return "Done"
        }
    }

    // MARK: - Changed-file count

    public static func changedFileCount(porcelain: String) -> Int {
        porcelain
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    public static func changedFileCount(atPath path: String) async -> Int {
        let out = await runGit(["-C", path, "status", "--porcelain"], cwd: path)
        return changedFileCount(porcelain: out)
    }

    // MARK: - Diff stats

    /// Sum `git diff --numstat` output into added/deleted line totals.
    public static func diffStat(numstat: String) -> DiffStat {
        var added = 0, deleted = 0
        for line in numstat.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 2 else { continue }
            added += Int(cols[0]) ?? 0
            deleted += Int(cols[1]) ?? 0
        }
        return DiffStat(added: added, deleted: deleted)
    }

    /// Working-tree changes (staged + unstaged vs HEAD) for a worktree.
    public static func diffStat(atPath path: String) async -> DiffStat {
        let out = await runGit(["-C", path, "diff", "--numstat", "HEAD"], cwd: path)
        return diffStat(numstat: out)
    }

    // MARK: - git plumbing

    private static func runGit(_ args: [String], cwd: String) async -> String {
        await Task.detached {
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = args
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            guard (try? proc.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 ? (String(data: data, encoding: .utf8) ?? "") : ""
        }.value
    }
}
