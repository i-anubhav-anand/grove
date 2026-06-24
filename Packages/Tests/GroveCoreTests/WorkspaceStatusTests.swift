import Testing
@testable import GroveCore

@Suite("WorkspaceStatus")
struct WorkspaceStatusTests {
    @Test func countsChangedLines() {
        let porcelain = " M a.swift\n?? b.txt\n D c.md\n"
        #expect(WorkspaceStatus.changedFileCount(porcelain: porcelain) == 3)
    }

    @Test func cleanTreeIsZero() {
        #expect(WorkspaceStatus.changedFileCount(porcelain: "") == 0)
        #expect(WorkspaceStatus.changedFileCount(porcelain: "\n  \n") == 0)
    }
}
