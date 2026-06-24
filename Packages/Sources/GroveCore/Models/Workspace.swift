import Foundation

/// A workspace = one git worktree (an isolated checkout of a project on its own
/// branch) plus the chat sessions that run inside it. This is what lets multiple
/// agents work the same repo on different branches in parallel without colliding.
public struct Workspace: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let projectId: UUID
    /// Branch checked out in this worktree (e.g. "main", "feature/x").
    public var branch: String
    /// Absolute path to the worktree directory (the agent's working directory).
    public var worktreePath: String
    public let createdAt: Date
    /// Optional user-facing name; falls back to the branch when nil.
    public var title: String?

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        branch: String,
        worktreePath: String,
        createdAt: Date = Date(),
        title: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.branch = branch
        self.worktreePath = worktreePath
        self.createdAt = createdAt
        self.title = title
    }

    /// Display name for the sidebar.
    public var displayName: String { title ?? branch }
}
