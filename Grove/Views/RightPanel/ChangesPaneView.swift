import SwiftUI
import GroveCore

/// Right-panel "Changes" tab: lists the changed files in the selected workspace's
/// worktree and opens the existing diff view on tap. Bound to `worktreePath`.
struct ChangesPaneView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(\.openURL) private var openURL
    let worktreePath: String?
    /// Shared PR state — drives the eye (review comments) toggle and the kebab's "Open PR".
    var prModel: PRReviewModel? = nil

    @State private var files: [ChangedFile] = []
    @State private var loading = false
    @State private var showComments = false
    @State private var groupByFolder = false

    struct ChangedFile: Identifiable, Equatable {
        let id = UUID()
        let status: String
        let relativePath: String
        var name: String { URL(fileURLWithPath: relativePath).lastPathComponent }
        var folder: String { URL(fileURLWithPath: relativePath).deletingLastPathComponent().path }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeThemeDivider()
            content
        }
        .task(id: worktreePath) { await reload() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(showComments ? "Review" : (files.isEmpty ? "No changes" : "\(files.count) changed"))
                .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                .foregroundStyle(files.isEmpty && !showComments ? ClaudeTheme.statusSuccess : ClaudeTheme.textSecondary)

            Spacer()

            // Review comments (eye) — only when the branch has an open PR.
            if prModel?.pullRequest != nil {
                iconButton(showComments ? "eye.fill" : "eye",
                           help: "Review comments",
                           tint: showComments ? ClaudeTheme.accent : ClaudeTheme.textSecondary) {
                    showComments.toggle()
                }
            }

            // Flat list ⇄ folder grouping.
            iconButton(groupByFolder ? "list.bullet.indent" : "list.bullet",
                       help: groupByFolder ? "Flat list" : "Group by folder",
                       tint: ClaudeTheme.textSecondary) {
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

    private func iconButton(_ systemName: String, help: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var content: some View {
        if showComments, let prModel {
            PRCommentsView(comments: prModel.comments)
        } else if worktreePath == nil {
            placeholder("Select a workspace to see its changes")
        } else if files.isEmpty {
            placeholder(loading ? "Loading…" : "Working tree clean")
        } else if groupByFolder {
            List {
                ForEach(groupedFiles, id: \.folder) { group in
                    Section(group.label) {
                        ForEach(group.files) { fileRow($0) }
                    }
                }
            }
            .listStyle(.sidebar)
        } else {
            List(files) { fileRow($0) }
                .listStyle(.plain)
        }
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        Button { open(file) } label: {
            HStack(spacing: 8) {
                Text(badge(file.status))
                    .font(.system(size: ClaudeTheme.size(10), weight: .bold, design: .monospaced))
                    .foregroundStyle(color(file.status))
                    .frame(width: 16, alignment: .leading)
                Text(file.name)
                    .font(.system(size: ClaudeTheme.size(12)))
                    .lineLimit(1)
                Spacer()
                if !groupByFolder, !file.folder.isEmpty {
                    Text(file.folder)
                        .font(.system(size: ClaudeTheme.size(10)))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        if t.contains("D") { return ClaudeTheme.statusError }
        if t == "??" || t.contains("A") { return ClaudeTheme.statusSuccess }
        return ClaudeTheme.accent
    }

    private func reload() async {
        guard let root = worktreePath else { files = []; return }
        loading = true
        let output = await Self.runGitStatus(cwd: root)
        files = output.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard line.count > 3 else { return nil }
            let status = String(line.prefix(2))
            var path = String(line.dropFirst(3))
            if status.contains("R"), let arrow = path.range(of: " -> ") {
                path = String(path[arrow.upperBound...])
            }
            return ChangedFile(status: status, relativePath: path)
        }
        loading = false
    }

    static func runGitStatus(cwd: String) async -> String {
        await Task.detached {
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", cwd, "status", "--porcelain"]
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            guard (try? proc.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}
