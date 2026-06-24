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
    /// Board status. Workspaces persisted before this field existed decode as
    /// `.inProgress` (see `init(from:)`).
    public var status: WorkspaceStatus

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        branch: String,
        worktreePath: String,
        createdAt: Date = Date(),
        title: String? = nil,
        status: WorkspaceStatus = .inProgress
    ) {
        self.id = id
        self.projectId = projectId
        self.branch = branch
        self.worktreePath = worktreePath
        self.createdAt = createdAt
        self.title = title
        self.status = status
    }

    /// Display name for the sidebar.
    public var displayName: String { title ?? branch }

    private enum CodingKeys: String, CodingKey {
        case id, projectId, branch, worktreePath, createdAt, title, status
    }

    // Custom decode so older `workspaces.json` (no `status` key) stays loadable.
    // `encode(to:)` is left synthesized.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        branch = try c.decode(String.self, forKey: .branch)
        worktreePath = try c.decode(String.self, forKey: .worktreePath)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        status = try c.decodeIfPresent(WorkspaceStatus.self, forKey: .status) ?? .inProgress
    }
}
