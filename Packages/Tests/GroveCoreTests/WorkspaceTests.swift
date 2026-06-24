import Testing
import Foundation
@testable import GroveCore

@Suite("Workspace model")
struct WorkspaceModelTests {
    @Test func codableRoundTrip() throws {
        let ws = Workspace(projectId: UUID(), branch: "feature/x", worktreePath: "/tmp/wt")
        let data = try JSONEncoder().encode(ws)
        let back = try JSONDecoder().decode(Workspace.self, from: data)
        #expect(back == ws)
        #expect(back.displayName == "feature/x")
    }

    @Test func displayNamePrefersTitle() {
        let ws = Workspace(projectId: UUID(), branch: "main", worktreePath: "/tmp", title: "Prod")
        #expect(ws.displayName == "Prod")
    }
}

@Suite("ChatSession workspace binding")
struct ChatSessionWorkspaceTests {
    @Test func decodesLegacyJSONWithoutWorkspaceId() throws {
        // Old on-disk session has no workspaceId — must still decode.
        let json = """
        {"id":"s1","projectId":"\(UUID().uuidString)","title":"t","messages":[],
         "createdAt":0,"updatedAt":0,"isPinned":false,"origin":"cliBacked"}
        """
        let session = try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
        #expect(session.workspaceId == nil)
    }

    @Test func roundTripsWorkspaceId() throws {
        let wid = UUID()
        let session = ChatSession(id: "s1", projectId: UUID(), workspaceId: wid)
        let data = try JSONEncoder().encode(session)
        let back = try JSONDecoder().decode(ChatSession.self, from: data)
        #expect(back.workspaceId == wid)
        #expect(back.summary.workspaceId == wid)
    }
}

@Suite("GitWorktreeService")
struct GitWorktreeServiceTests {
    @Test func createsListsAndRemovesAWorktree() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString.prefix(8))")
        let repo = tmp.appendingPathComponent("repo")
        let base = tmp.appendingPathComponent("worktrees")
        try fm.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        func git(_ args: String) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "cd \(repo.path) && \(args)"]
            try p.run(); p.waitUntilExit()
        }
        try git("git init -q && git config user.email t@t.co && git config user.name t && echo hi > a.txt && git add -A && git commit -qm init")

        let svc = GitWorktreeService(baseDir: base)
        let path = try await svc.createWorktree(repo: repo.path, branch: "feature/x")
        #expect(fm.fileExists(atPath: path))

        let list = try await svc.listWorktrees(repo: repo.path)
        #expect(list.contains { $0.branch == "feature/x" })

        try await svc.removeWorktree(repo: repo.path, path: path, force: true)
        let after = try await svc.listWorktrees(repo: repo.path)
        #expect(!after.contains { $0.branch == "feature/x" })
    }
}
