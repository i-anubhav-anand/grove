import SwiftUI
import GroveCore

/// Right-panel "Checks" tab: shows the CI checks / statuses / deployments for the
/// pull request on the selected workspace's branch (via `gh pr checks`), plus a
/// "Fix failing checks" button that seeds the chat composer with the failing logs.
struct ChecksPaneView: View {
    @Environment(WindowState.self) private var windowState
    let worktreePath: String?
    let branch: String?

    @State private var checks: [Check] = []
    @State private var loading = false
    @State private var status: LoadStatus = .idle
    @State private var seeding = false

    enum LoadStatus: Equatable {
        case idle
        case loaded
        case noPR
        case error(String)
    }

    /// One row from `gh pr checks --json …`. Buckets: pass / fail / pending /
    /// skipping / cancel. Deployment statuses surface here too (as check rows).
    struct Check: Identifiable, Equatable, Decodable {
        let name: String
        let state: String
        let bucket: String
        let description: String
        let link: String
        let workflow: String

        var id: String { "\(workflow)/\(name)/\(link)" }
        var isFailing: Bool { bucket == "fail" || bucket == "cancel" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            state = (try? c.decode(String.self, forKey: .state)) ?? ""
            bucket = (try? c.decode(String.self, forKey: .bucket)) ?? ""
            description = (try? c.decode(String.self, forKey: .description)) ?? ""
            link = (try? c.decode(String.self, forKey: .link)) ?? ""
            workflow = (try? c.decode(String.self, forKey: .workflow)) ?? ""
        }

        enum CodingKeys: String, CodingKey {
            case name, state, bucket, description, link, workflow
        }
    }

    private var failingChecks: [Check] { checks.filter(\.isFailing) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeThemeDivider()
            content
            if !failingChecks.isEmpty {
                ClaudeThemeDivider()
                fixButton
            }
        }
        .task(id: taskKey) { await reload() }
    }

    private var taskKey: String { "\(worktreePath ?? "")|\(branch ?? "")" }

    private var header: some View {
        HStack(spacing: 8) {
            Text(summary)
                .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                .foregroundStyle(headerColor)
            Spacer()
            Button { Task { await reload() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: ClaudeTheme.size(11)))
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if worktreePath == nil || (branch ?? "").isEmpty {
            placeholder("Select a workspace to see its checks")
        } else if loading && checks.isEmpty {
            placeholder("Loading…")
        } else {
            switch status {
            case .noPR:
                placeholder("No pull request for this branch")
            case .error(let message):
                placeholder(message)
            case .idle, .loaded:
                if checks.isEmpty {
                    placeholder("No checks reported")
                } else {
                    checkList
                }
            }
        }
    }

    private var checkList: some View {
        List(checks) { check in
            HStack(spacing: 8) {
                Image(systemName: icon(check.bucket))
                    .font(.system(size: ClaudeTheme.size(12)))
                    .foregroundStyle(color(check.bucket))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(check.name.isEmpty ? check.workflow : check.name)
                        .font(.system(size: ClaudeTheme.size(12)))
                        .lineLimit(1)
                    if !check.workflow.isEmpty && !check.name.isEmpty {
                        Text(check.workflow)
                            .font(.system(size: ClaudeTheme.size(10)))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !check.link.isEmpty, let url = URL(string: check.link) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: ClaudeTheme.size(10)))
                            .foregroundStyle(.tertiary)
                    }
                    .help("Open on GitHub")
                }
            }
            .contentShape(Rectangle())
        }
        .listStyle(.plain)
    }

    private var fixButton: some View {
        Button {
            Task { await seedFixPrompt() }
        } label: {
            HStack(spacing: 6) {
                if seeding {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "wrench.and.screwdriver")
                }
                Text("Fix failing checks")
                    .font(.system(size: ClaudeTheme.size(12), weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ClaudeTheme.textOnAccent)
        .background(ClaudeTheme.accent, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
        .disabled(seeding)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary / styling

    private var summary: String {
        guard status == .loaded || status == .idle, !checks.isEmpty else {
            return "Checks"
        }
        let fail = checks.filter(\.isFailing).count
        let pending = checks.filter { $0.bucket == "pending" }.count
        let pass = checks.filter { $0.bucket == "pass" }.count
        var parts: [String] = []
        if fail > 0 { parts.append("\(fail) failing") }
        if pending > 0 { parts.append("\(pending) running") }
        if pass > 0 { parts.append("\(pass) passed") }
        return parts.isEmpty ? "\(checks.count) checks" : parts.joined(separator: " · ")
    }

    private var headerColor: Color {
        if !failingChecks.isEmpty { return ClaudeTheme.statusError }
        if !checks.isEmpty && checks.allSatisfy({ $0.bucket == "pass" }) { return ClaudeTheme.statusSuccess }
        return ClaudeTheme.textSecondary
    }

    private func icon(_ bucket: String) -> String {
        switch bucket {
        case "pass": "checkmark.circle.fill"
        case "fail": "xmark.circle.fill"
        case "pending": "clock"
        case "cancel": "exclamationmark.octagon.fill"
        case "skipping": "minus.circle"
        default: "circle"
        }
    }

    private func color(_ bucket: String) -> Color {
        switch bucket {
        case "pass": ClaudeTheme.statusSuccess
        case "fail": ClaudeTheme.statusError
        case "pending": ClaudeTheme.statusRunning
        case "cancel": ClaudeTheme.statusWarning
        default: ClaudeTheme.textTertiary
        }
    }

    private func rank(_ check: Check) -> Int {
        switch check.bucket {
        case "fail": 0
        case "cancel": 1
        case "pending": 2
        case "pass": 3
        default: 4
        }
    }

    // MARK: - Data

    private func reload() async {
        guard let cwd = worktreePath, let branch, !branch.isEmpty else {
            checks = []; status = .idle; return
        }
        loading = true
        defer { loading = false }

        let result = await Self.runGH(
            ["pr", "checks", branch, "--json", "name,state,bucket,description,link,workflow"],
            cwd: cwd
        )

        // `gh pr checks` exits non-zero when checks are failing or pending, but
        // still prints the JSON array — so parse stdout regardless of exit code.
        if let data = result.stdout.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Check].self, from: data) {
            checks = decoded.sorted { rank($0) < rank($1) }
            status = .loaded
            return
        }

        checks = []
        let stderr = result.stderr.lowercased()
        if stderr.contains("no pull request") || stderr.contains("no open pull request") {
            status = .noPR
        } else if stderr.contains("no checks reported") {
            status = .loaded
        } else if result.code == -1 {
            status = .error("`gh` not found. Install the GitHub CLI to see checks.")
        } else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            status = message.isEmpty ? .noPR : .error(message)
        }
    }

    private func seedFixPrompt() async {
        guard let cwd = worktreePath else { return }
        let failing = failingChecks
        guard !failing.isEmpty else { return }
        seeding = true
        defer { seeding = false }

        var sections: [String] = []
        for check in failing {
            let title = check.workflow.isEmpty ? check.name : "\(check.name) (\(check.workflow))"
            var section = "### \(title)\nState: \(check.state)"
            if !check.link.isEmpty { section += "\n\(check.link)" }

            var appendedLogs = false
            if let runID = Self.runID(from: check.link) {
                let logs = await Self.runGH(["run", "view", runID, "--log-failed"], cwd: cwd)
                let trimmed = logs.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let snippet = String(trimmed.suffix(4000))
                    section += "\n\n```\n\(snippet)\n```"
                    appendedLogs = true
                }
            }
            if !appendedLogs && !check.description.isEmpty {
                section += "\n\(check.description)"
            }
            sections.append(section)
        }

        let branchName = branch ?? "this branch"
        let prompt = """
        The following CI checks are failing on `\(branchName)`. Investigate the logs below and fix the underlying problems.

        \(sections.joined(separator: "\n\n"))
        """

        if windowState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            windowState.inputText = prompt
        } else {
            windowState.inputText += "\n\n" + prompt
        }
        windowState.requestInputFocus = true
    }

    /// Extract the Actions run ID from a check `link`
    /// (e.g. ".../actions/runs/123456/job/789" → "123456").
    private static func runID(from link: String) -> String? {
        guard let range = link.range(of: #"/runs/(\d+)"#, options: .regularExpression) else { return nil }
        return link[range].split(separator: "/").last.map(String.init)
    }

    private struct GHResult {
        let stdout: String
        let stderr: String
        let code: Int32
    }

    private static func runGH(_ args: [String], cwd: String) async -> GHResult {
        await Task.detached {
            let proc = Process()
            let out = Pipe()
            let err = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["gh"] + args
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
            proc.standardOutput = out
            proc.standardError = err

            // `gh` lives in Homebrew paths that aren't on a sandboxed app's PATH.
            var environment = ProcessInfo.processInfo.environment
            let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
            if let existing = environment["PATH"], !existing.isEmpty {
                environment["PATH"] = "\(existing):\(extraPaths)"
            } else {
                environment["PATH"] = extraPaths
            }
            proc.environment = environment

            guard (try? proc.run()) != nil else {
                return GHResult(stdout: "", stderr: "gh not found", code: -1)
            }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return GHResult(
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errData, encoding: .utf8) ?? "",
                code: proc.terminationStatus
            )
        }.value
    }
}
