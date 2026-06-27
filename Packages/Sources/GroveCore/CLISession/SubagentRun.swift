import Foundation

/// A subagent (Task/Agent) run, reconstructed from the CLI's per-agent jsonl so
/// the UI can show the depth of what each agent did. Keyed to the parent
/// `Agent`/`Task` tool call by `toolUseId` (from the agent's meta.json).
public struct SubagentRun: Sendable, Identifiable {
    public let toolUseId: String
    public let agentType: String?
    public let description: String?
    public let steps: [SubagentStep]

    public var id: String { toolUseId }

    public init(toolUseId: String, agentType: String?, description: String?, steps: [SubagentStep]) {
        self.toolUseId = toolUseId
        self.agentType = agentType
        self.description = description
        self.steps = steps
    }
}

/// One step in a subagent's run — a tool it called, a line of reasoning text, or
/// its final summary.
public struct SubagentStep: Sendable, Identifiable {
    public enum Kind: String, Sendable { case text, tool }

    public let id: String
    public let kind: Kind
    public let label: String
    public let icon: String

    public init(id: String, kind: Kind, label: String, icon: String) {
        self.id = id
        self.kind = kind
        self.label = label
        self.icon = icon
    }
}

// MARK: - Loader

public enum SubagentStepsLoader {

    /// Given a main session's jsonl URL, load every subagent run recorded under
    /// its sibling `<sessionId>/subagents/` directory, keyed by parent toolUseId.
    /// Returns an empty map when there are no subagents (the common case).
    public static func load(mainSessionJSONL url: URL) -> [String: SubagentRun] {
        let fm = FileManager.default
        // <dir>/<sessionId>.jsonl  →  <dir>/<sessionId>/subagents/
        let subagentsDir = url.deletingPathExtension().appendingPathComponent("subagents")
        guard let entries = try? fm.contentsOfDirectory(
            at: subagentsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [:] }

        var runs: [String: SubagentRun] = [:]
        for metaURL in entries where metaURL.pathExtension == "json" && metaURL.lastPathComponent.hasSuffix(".meta.json") {
            guard let meta = try? JSONDecoder().decode(Meta.self, from: Data(contentsOf: metaURL)),
                  !meta.toolUseId.isEmpty else { continue }

            // agent-<id>.meta.json  →  agent-<id>.jsonl
            let base = metaURL.lastPathComponent.replacingOccurrences(of: ".meta.json", with: "")
            let jsonlURL = subagentsDir.appendingPathComponent("\(base).jsonl")
            let steps = parseSteps(at: jsonlURL)

            runs[meta.toolUseId] = SubagentRun(
                toolUseId: meta.toolUseId,
                agentType: meta.agentType,
                description: meta.description,
                steps: steps
            )
        }
        return runs
    }

    private struct Meta: Decodable {
        let toolUseId: String
        let agentType: String?
        let description: String?
    }

    private static func parseSteps(at url: URL) -> [SubagentStep] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        var steps: [SubagentStep] = []
        var index = 0

        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = raw.data(using: .utf8),
                  let line = try? decoder.decode(CLISessionLine.self, from: lineData),
                  case .assistant(let assistant) = line else { continue }

            for part in assistant.message.content {
                switch part {
                case .text(let t):
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !CLIMetaEnvelope.isNoResponseRequested(trimmed) else { continue }
                    steps.append(SubagentStep(
                        id: "s\(index)", kind: .text,
                        label: snippet(trimmed), icon: "text.alignleft"
                    ))
                    index += 1
                case .toolUse(_, let name, let input):
                    steps.append(SubagentStep(
                        id: "s\(index)", kind: .tool,
                        label: toolLabel(name: name, input: input), icon: toolIcon(name: name)
                    ))
                    index += 1
                case .thinking, .redactedThinking, .skip:
                    continue
                }
            }
        }
        return steps
    }

    // MARK: - Labels

    private static func snippet(_ s: String, max: Int = 100) -> String {
        let firstLine = s.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? s
        return firstLine.count > max ? String(firstLine.prefix(max)) + "…" : firstLine
    }

    private static func filename(_ input: [String: JSONValue]) -> String {
        guard let path = input["file_path"]?.stringValue else { return "" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func toolLabel(name: String, input: [String: JSONValue]) -> String {
        switch name.lowercased() {
        case "read":
            let f = filename(input); return f.isEmpty ? "Read" : "Read \(f)"
        case "write":
            let f = filename(input); return f.isEmpty ? "Write" : "Write \(f)"
        case "edit", "multiedit", "multi_edit":
            let f = filename(input); return f.isEmpty ? "Edit" : "Edit \(f)"
        case "bash":
            if let cmd = input["command"]?.stringValue {
                return "$ " + snippet(cmd.trimmingCharacters(in: .whitespacesAndNewlines), max: 60)
            }
            return "Run command"
        case "grep":
            if let p = input["pattern"]?.stringValue { return "Grep \(snippet(p, max: 40))" }
            return "Search"
        case "glob":
            if let p = (input["pattern"] ?? input["path"])?.stringValue { return "Glob \(snippet(p, max: 40))" }
            return "Find files"
        case "webfetch":
            if let u = input["url"]?.stringValue { return "Fetch \(snippet(u, max: 50))" }
            return "Fetch"
        case "websearch":
            if let q = input["query"]?.stringValue { return "Search \(snippet(q, max: 50))" }
            return "Web search"
        case "task", "agent":
            return "Subagent: " + (input["description"]?.stringValue ?? "run")
        default:
            return name
        }
    }

    private static func toolIcon(name: String) -> String {
        switch name.lowercased() {
        case "read":                            return "doc.text"
        case "write":                           return "square.and.pencil"
        case "edit", "multiedit", "multi_edit": return "pencil"
        case "bash":                            return "terminal"
        case "grep", "glob":                    return "magnifyingglass"
        case "webfetch", "websearch":           return "globe"
        case "task", "agent":                   return "cpu"
        default:                                return "wrench"
        }
    }
}
