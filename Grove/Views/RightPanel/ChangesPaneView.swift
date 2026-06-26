import SwiftUI
import GroveCore

/// Right-panel "Changes" tab: lists the changed files in the selected workspace's
/// worktree and opens the existing diff view on tap. Bound to `worktreePath`.
struct ChangesPaneView: View {
    @Environment(WindowState.self) private var windowState
    let worktreePath: String?

    @State private var files: [ChangedFile] = []
    @State private var loading = false

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
            Text(files.isEmpty ? "No changes" : "\(files.count) changed")
                .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                .foregroundStyle(files.isEmpty ? ClaudeTheme.statusSuccess : ClaudeTheme.textSecondary)
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
        if worktreePath == nil {
            placeholder("Select a workspace to see its changes")
        } else if files.isEmpty {
            placeholder(loading ? "Loading…" : "Working tree clean")
        } else {
            List(files) { file in
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
                        if !file.folder.isEmpty {
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
            .listStyle(.plain)
        }
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
