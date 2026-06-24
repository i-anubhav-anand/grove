import Foundation

public struct Project: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var path: String
    public var gitHubRepo: String?
    public var lastSessionId: String?
    /// Shell command run by the Run pane (⌘R) in the selected worktree. nil when unset.
    public var runScript: String?

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        gitHubRepo: String? = nil,
        lastSessionId: String? = nil,
        runScript: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.gitHubRepo = gitHubRepo
        self.lastSessionId = lastSessionId
        self.runScript = runScript
    }
}
