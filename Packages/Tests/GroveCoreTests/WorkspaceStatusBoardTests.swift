import Testing
import Foundation
@testable import GroveCore

@Suite("WorkspaceStatus board")
struct WorkspaceStatusBoardTests {

    @Test func rawValuesAreStable() {
        #expect(WorkspaceStatus.backlog.rawValue == "backlog")
        #expect(WorkspaceStatus.inProgress.rawValue == "inProgress")
        #expect(WorkspaceStatus.inReview.rawValue == "inReview")
        #expect(WorkspaceStatus.done.rawValue == "done")
    }

    @Test func codableRoundTrip() throws {
        for status in WorkspaceStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(WorkspaceStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    @Test func workspaceDefaultsToInProgress() {
        let ws = Workspace(projectId: UUID(), branch: "main", worktreePath: "/tmp/x")
        #expect(ws.status == .inProgress)
    }

    /// Workspaces persisted before `status` existed must still decode (defaulting
    /// to `.inProgress`) rather than throwing.
    @Test func decodesLegacyWorkspaceWithoutStatus() throws {
        let json = Data("""
        {"id":"\(UUID().uuidString)","projectId":"\(UUID().uuidString)","branch":"main","worktreePath":"/tmp/x","createdAt":"2024-01-01T00:00:00Z"}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ws = try decoder.decode(Workspace.self, from: json)
        #expect(ws.status == .inProgress)
    }

    @Test func roundTripsExplicitStatus() throws {
        var ws = Workspace(projectId: UUID(), branch: "main", worktreePath: "/tmp/x")
        ws.status = .inReview
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workspace.self, from: encoder.encode(ws))
        #expect(decoded.status == .inReview)
    }
}
