import SwiftUI
import GroveCore

/// Right-panel "Changes" tab: lists the changed files in the selected workspace's
/// worktree and opens the existing diff view on tap. Bound to `worktreePath`.
struct ChangesPaneView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.openURL) private var openURL
    let worktreePath: String?
    /// Shared PR state — drives the eye (review comments) toggle and the kebab's "Open PR".
    var prModel: PRReviewModel? = nil

    @State private var files: [ChangedFile] = []
    @State private var loading = false
    @State private var showComments = false
    @State private var groupByFolder = false
    @State private var commitsBehind = 0

    struct ChangedFile: Identifiable, Equatable {
        let id = UUID()
        let status: String
        let relativePath: String
        var added: Int = 0
        var deleted: Int = 0
        var name: String { URL(fileURLWithPath: relativePath).lastPathComponent }
        var folder: String { URL(fileURLWithPath: relativePath).deletingLastPathComponent().path }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeThemeDivider()
            content
        }
        .task(id: worktreePath) {
            // Poll while the pane is mounted (i.e. the inspector is open) so the
            // list stays current instead of showing a stale empty state.
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(showComments ? "Review" : (files.isEmpty ? "No changes" : "\(files.count) changed"))
                .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                .foregroundStyle(files.isEmpty && !showComments ? ClaudeTheme.statusSuccess : ClaudeTheme.textSecondary)

            Spacer()

            // Review comments (eye) — only when the branch has an open PR.
            if prModel?.pullRequest != nil {
                InspectorIconButton(systemName: showComments ? "eye.fill" : "eye",
                                    help: "Review comments",
                                    tint: showComments ? ClaudeTheme.accent : nil) {
                    showComments.toggle()
                }
            }

            // Flat list ⇄ folder grouping.
            InspectorIconButton(systemName: groupByFolder ? "list.bullet.indent" : "list.bullet",
                                help: groupByFolder ? "Flat list" : "Group by folder") {
                groupByFolder.toggle()
            }

            // Overflow.
            Menu {
                Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                if let pr = prModel?.pullRequest, let url = URL(string: pr.htmlUrl) {
                    Button { openURL(url) } label: { Label("Open PR #\(pr.number)", systemImage: "arrow.up.right.square") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: ClaudeTheme.size(12)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if showComments, let prModel {
            PRCommentsView(comments: prModel.comments)
        } else if worktreePath == nil {
            placeholder("Select a workspace to see its changes")
        } else if files.isEmpty {
            emptyChangesState
        } else if groupByFolder {
            List {
                ForEach(groupedFiles, id: \.folder) { group in
                    Section(group.label) {
                        ForEach(group.files) { fileRow($0) }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        } else {
            List(files) { fileRow($0) }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
        }
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        Button { open(file) } label: {
            HStack(spacing: 8) {
                Text(badge(file.status))
                    .font(.system(size: ClaudeTheme.size(10), weight: .bold, design: .monospaced))
                    .foregroundStyle(color(file.status))
                    .frame(width: 14, alignment: .leading)
                Image(systemName: icon(for: file.name))
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                Text(file.name)
                    .font(.system(size: ClaudeTheme.size(12)))
                    .lineLimit(1)
                if file.added > 0 {
                    Text(verbatim: "+\(file.added)")
                        .font(.system(size: ClaudeTheme.size(10), design: .monospaced))
                        .foregroundStyle(ClaudeTheme.statusSuccess)
                }
                if file.deleted > 0 {
                    Text(verbatim: "-\(file.deleted)")
                        .font(.system(size: ClaudeTheme.size(10), design: .monospaced))
                        .foregroundStyle(ClaudeTheme.statusError)
                }
                Spacer(minLength: 8)
                if !groupByFolder, !file.folder.isEmpty {
                    Text(file.folder)
                        .font(.system(size: ClaudeTheme.size(10)))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift":                                   return "swift"
        case "md", "markdown", "txt", "rtf":            return "doc.text"
        case "json", "yml", "yaml", "toml", "plist":    return "curlybraces"
        case "sh", "bash", "zsh", "fish":               return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg", "pdf": return "photo"
        default:                                        return "doc"
        }
    }

    private struct FileGroup: Identifiable { let folder: String; let files: [ChangedFile]; var id: String { folder }; var label: String { folder.isEmpty ? "." : folder } }

    private var groupedFiles: [FileGroup] {
        Dictionary(grouping: files, by: \.folder)
            .sorted { $0.key < $1.key }
            .map { FileGroup(folder: $0.key, files: $0.value) }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Empty state for a clean working tree — with a "pull latest" affordance
    /// when the branch is behind its base.
    private var emptyChangesState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: ClaudeTheme.size(30)))
                .foregroundStyle(ClaudeTheme.textTertiary.opacity(0.5))
            Text(loading ? "Loading…" : "No file changes yet")
                .font(.system(size: ClaudeTheme.size(14), weight: .medium))
                .foregroundStyle(ClaudeTheme.textSecondary)
            Text("Changes appear here.")
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            if commitsBehind > 0 {
                Button(action: pullLatest) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down")
                        Text("Pull latest from main (\(commitsBehind) commit\(commitsBehind == 1 ? "" : "s"))")
                    }
                    .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                    .foregroundStyle(ClaudeTheme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Ask the agent to bring the base branch's latest commits into this branch.
    private func pullLatest() {
        windowState.inputText = "Pull the latest changes from the base branch (origin/main) into this branch with `git pull --rebase origin main` (or merge), and resolve any conflicts."
        Task { await appState.send(in: windowState) }
    }

    private func open(_ file: ChangedFile) {
        guard let root = worktreePath else { return }
        let full = (root as NSString).appendingPathComponent(file.relativePath)
        windowState.diffFile = PreviewFile(path: full, name: file.name)
    }

    private func badge(_ status: String) -> String {
        let t = status.trimmingCharacters(in: .whitespaces)
        if t == "??" { return "U" }
        return String(t.prefix(1))
    }

    private func color(_ status: String) -> Color {
        let t = status.trimmingCharacters(in: .whitespaces)
        if t.contains("D") { return ClaudeTheme.statusError }       // deleted → red
        if t == "??" || t.contains("A") { return ClaudeTheme.statusSuccess } // added → green
        if t.contains("R") { return .blue }                        // renamed → blue
        return ClaudeTheme.statusWarning                           // modified → yellow
    }

    private func reload() async {
        guard let root = worktreePath else { files = []; return }
        loading = true
        let output = await Self.runGit(cwd: root, args: ["status", "--porcelain"])
        let counts = await Self.runGitNumstat(cwd: root)  // tracked-file line changes vs HEAD
        files = output.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard line.count > 3 else { return nil }
            let status = String(line.prefix(2))
            var path = String(line.dropFirst(3))
            if status.contains("R"), let arrow = path.range(of: " -> ") {
                path = String(path[arrow.upperBound...])
            }
            let (added, deleted) = counts[path] ?? (0, 0)
            return ChangedFile(status: status, relativePath: path, added: added, deleted: deleted)
        }
        commitsBehind = await Self.commitsBehind(cwd: root)
        loading = false
    }

    /// Commits on the base branch that this branch doesn't have yet.
    static func commitsBehind(cwd: String) async -> Int {
        for base in ["origin/HEAD", "origin/main", "origin/master"] {
            let out = await runGit(cwd: cwd, args: ["rev-list", "--count", "HEAD..\(base)"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty, let n = Int(out) { return n }
        }
        return 0
    }

    /// Per-path (added, deleted) line counts for tracked changes vs HEAD.
    /// Untracked files aren't in the diff, so they report zero (counts hidden).
    static func runGitNumstat(cwd: String) async -> [String: (Int, Int)] {
        let out = await runGit(cwd: cwd, args: ["diff", "--numstat", "HEAD"])
        var map: [String: (Int, Int)] = [:]
        for raw in out.split(separator: "\n") {
            let parts = raw.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3, let added = Int(parts[0]), let deleted = Int(parts[1]) else { continue }
            map[String(parts[2])] = (added, deleted)
        }
        return map
    }

    static func runGit(cwd: String, args: [String]) async -> String {
        await Task.detached {
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", cwd] + args
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            guard (try? proc.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}
