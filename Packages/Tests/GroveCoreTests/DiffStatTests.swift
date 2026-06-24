import Testing
@testable import GroveCore

@Suite("DiffStat")
struct DiffStatTests {
    @Test func parsesNumstat() {
        let numstat = "12\t3\ta.swift\n0\t5\tb.txt\n7\t0\tc.md\n"
        let stat = WorkspaceStatus.diffStat(numstat: numstat)
        #expect(stat.added == 19)
        #expect(stat.deleted == 8)
        #expect(!stat.isEmpty)
    }

    @Test func emptyIsZero() {
        #expect(WorkspaceStatus.diffStat(numstat: "").isEmpty)
        #expect(WorkspaceStatus.diffStat(numstat: "\n  \n").isEmpty)
    }

    @Test func ignoresBinaryAndMalformedRows() {
        // git emits "-\t-\tbinary" for binaries; malformed rows are skipped.
        let numstat = "-\t-\timage.png\n5\t2\treal.swift\ngarbage\n"
        let stat = WorkspaceStatus.diffStat(numstat: numstat)
        #expect(stat.added == 5)
        #expect(stat.deleted == 2)
    }
}
