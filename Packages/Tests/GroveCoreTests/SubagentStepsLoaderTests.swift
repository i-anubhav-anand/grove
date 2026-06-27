import Testing
import Foundation
@testable import GroveCore

@Suite("SubagentStepsLoader")
struct SubagentStepsLoaderTests {

    /// Builds a temp `<dir>/<sid>.jsonl` + `<dir>/<sid>/subagents/agent-x.{jsonl,meta.json}`
    /// layout mirroring the CLI, then asserts the loader links steps by toolUseId.
    @Test func loadsStepsLinkedByToolUseId() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("subagent-test-\(UUID().uuidString)")
        let sid = "11111111-1111-1111-1111-111111111111"
        let mainJSONL = root.appendingPathComponent("\(sid).jsonl")
        let subDir = root.appendingPathComponent(sid).appendingPathComponent("subagents")
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try Data("{}".utf8).write(to: mainJSONL)

        let meta = #"{"toolUseId":"toolu_ABC","agentType":"Explore","description":"Find config"}"#
        try Data(meta.utf8).write(to: subDir.appendingPathComponent("agent-x.meta.json"))

        let lines = [
            #"{"type":"user","isSidechain":true,"message":{"content":"go"}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"Searching the repo"}]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"t1","name":"Grep","input":{"pattern":"inspectorWidth"}}]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/a/b/MainView.swift"}}]}}"#,
        ].joined(separator: "\n")
        try Data(lines.utf8).write(to: subDir.appendingPathComponent("agent-x.jsonl"))

        let runs = SubagentStepsLoader.load(mainSessionJSONL: mainJSONL)

        let run = try #require(runs["toolu_ABC"])
        #expect(run.agentType == "Explore")
        #expect(run.description == "Find config")
        #expect(run.steps.count == 3)
        #expect(run.steps[0].kind == .text)
        #expect(run.steps[0].label == "Searching the repo")
        #expect(run.steps[1].label == "Grep inspectorWidth")
        #expect(run.steps[2].label == "Read MainView.swift")
    }

    @Test func returnsEmptyWhenNoSubagentsDir() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).jsonl")
        #expect(SubagentStepsLoader.load(mainSessionJSONL: url).isEmpty)
    }
}
