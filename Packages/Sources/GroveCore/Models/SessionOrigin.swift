import Foundation

/// Where the session's message content lives on disk.
public enum SessionOrigin: String, Codable, Sendable {
    /// Legacy Grove-owned JSON at `~/Library/Application Support/Grove/sessions/{projectId}/{sid}.json`.
    /// Read-only going forward; will not appear in the CLI's `~/.claude/projects/...` directory.
    case legacyGrove

    /// Backed by Claude Code CLI's `~/.claude/projects/{enc(cwd)}/{sid}.jsonl`.
    /// Source of truth is the CLI; Grove keeps Grove-only metadata in a sidecar.
    case cliBacked
}
