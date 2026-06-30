import SwiftUI
import GroveCore

public struct FileDiffView: View {
    public let filePath: String
    public let fileName: String
    public let editHunks: [PreviewFile.EditHunk]
    @Environment(WindowState.self) private var windowState
    @State private var diffLines: [DiffLine] = []
    @State private var isLoading = true
    @State private var isCopied = false
    @State private var selectedLineIndex: Int?
    @State private var commentText = ""

    public init(filePath: String, fileName: String, editHunks: [PreviewFile.EditHunk] = []) {
        self.filePath = filePath
        self.fileName = fileName
        self.editHunks = editHunks
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeThemeDivider()
            contentArea
            if !isLoading && !diffLines.isEmpty {
                ClaudeThemeDivider()
                commentBar
            }
        }
        .background(ClaudeTheme.background)
        .background {
            Button("") { windowState.diffFile = nil }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
        }
        .task(id: filePath) { await loadDiff() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: ClaudeTheme.messageSize(13)))
                .foregroundStyle(ClaudeTheme.accent)

            Text(fileName)
                .font(.system(size: ClaudeTheme.messageSize(13), weight: .semibold, design: .monospaced))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("Diff", bundle: .module)
                .font(.system(size: ClaudeTheme.messageSize(10), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(ClaudeTheme.surfaceSecondary, in: Capsule())

            if !diffLines.isEmpty {
                Button {
                    let raw = diffLines.map(\.text).joined(separator: "\n")
                    copyToClipboard(raw, feedback: $isCopied)
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: ClaudeTheme.messageSize(12)))
                        .foregroundStyle(isCopied ? ClaudeTheme.statusSuccess : ClaudeTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .help(isCopied ? "Copied" : "Copy")
            }

            Button { windowState.diffFile = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(ClaudeTheme.surfaceSecondary, in: Circle())
            }
            .buttonStyle(.borderless)
            .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ClaudeTheme.surfacePrimary)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(ClaudeTheme.codeBackground)
        } else if diffLines.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "checkmark.circle")
                    .font(.system(size: ClaudeTheme.messageSize(24)))
                    .foregroundStyle(ClaudeTheme.statusSuccess)
                Text("No changes", bundle: .module)
                    .font(.system(size: ClaudeTheme.messageSize(13)))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(ClaudeTheme.codeBackground)
        } else {
            diffContentView
        }
    }

    private var diffContentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { index, line in
                    DiffLineRow(
                        line: line,
                        isSelected: selectedLineIndex == index,
                        onTap: {
                            let commentable = line.kind != .hunk && line.kind != .meta
                            selectedLineIndex = commentable ? (selectedLineIndex == index ? nil : index) : nil
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClaudeTheme.codeBackground)
    }

    // MARK: - Comment Bar

    private var selectedDisplayLine: Int? {
        guard let index = selectedLineIndex, let line = diffLines[safe: index] else { return nil }
        return line.lineNumber ?? (index + 1)
    }

    @ViewBuilder
    private var commentBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: ClaudeTheme.messageSize(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)

            if let displayLine = selectedDisplayLine {
                Text("Line \(displayLine)", bundle: .module)
                    .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium, design: .monospaced))
                    .foregroundStyle(ClaudeTheme.accent)
                    .fixedSize()

                TextField(text: $commentText) {
                    Text("Comment on this line…", bundle: .module)
                }
                .textFieldStyle(.plain)
                .font(.system(size: ClaudeTheme.messageSize(12)))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .onSubmit(submitComment)

                Button(action: submitComment) {
                    Text("Send to chat", bundle: .module)
                        .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text("Click a line in the diff to comment", bundle: .module)
                    .font(.system(size: ClaudeTheme.messageSize(12)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ClaudeTheme.surfacePrimary)
    }

    private func submitComment() {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let displayLine = selectedDisplayLine else { return }
        let prompt = "Address this: \(fileName):\(displayLine) — \(trimmed)"
        if windowState.inputText.isEmpty {
            windowState.inputText = prompt
        } else {
            windowState.inputText += "\n" + prompt
        }
        windowState.requestInputFocus = true
        commentText = ""
        windowState.diffFile = nil
    }

    // MARK: - Diff Sources

    private func loadDiff() async {
        isLoading = true
        selectedLineIndex = nil
        defer { isLoading = false }

        if !editHunks.isEmpty {
            let hunks = editHunks
            diffLines = await Task.detached(priority: .userInitiated) {
                FileDiffView.buildEditDiffLines(from: hunks)
            }.value
            return
        }

        let workDir = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        let raw: String
        if let r1 = await GitHelper.run(["diff", "HEAD", "--", filePath], at: workDir) {
            raw = r1
        } else if let r2 = await GitHelper.run(["diff", "--", filePath], at: workDir) {
            raw = r2
        } else {
            raw = await GitHelper.run(["show", "HEAD", "--", filePath], at: workDir) ?? ""
        }
        diffLines = await Task.detached(priority: .userInitiated) {
            FileDiffView.parseDiff(raw)
        }.value
    }

    nonisolated static func buildEditDiffLines(from hunks: [PreviewFile.EditHunk]) -> [DiffLine] {
        var lines: [DiffLine] = []
        for (index, hunk) in hunks.enumerated() {
            if hunks.count > 1 {
                lines.append(DiffLine(text: "@@ edit \(index + 1) of \(hunks.count) @@", kind: .hunk))
            }
            let (trimmedOld, trimmedNew) = stripCommonIndent(
                old: hunk.oldString.components(separatedBy: .newlines),
                new: hunk.newString.components(separatedBy: .newlines)
            )
            lines.append(contentsOf: trimmedOld.map { DiffLine(text: "-" + $0, kind: .removed) })
            lines.append(contentsOf: trimmedNew.map { DiffLine(text: "+" + $0, kind: .added) })
        }
        return lines
    }

    nonisolated static func parseDiff(_ raw: String) -> [DiffLine] {
        guard !raw.isEmpty else { return [] }
        var lines = raw.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var oldLine = 0
        var newLine = 0
        var result: [DiffLine] = []
        for line in lines {
            if line.hasPrefix("@@") {
                let (o, n) = parseHunkHeader(line)
                oldLine = o
                newLine = n
                result.append(DiffLine(text: line, kind: .hunk))
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                result.append(DiffLine(text: line, kind: .added, lineNumber: newLine))
                newLine += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                result.append(DiffLine(text: line, kind: .removed, lineNumber: oldLine))
                oldLine += 1
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("---") || line.hasPrefix("+++") {
                result.append(DiffLine(text: line, kind: .meta))
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" — not a real source line.
                result.append(DiffLine(text: line, kind: .context))
            } else {
                result.append(DiffLine(text: line, kind: .context, lineNumber: newLine))
                oldLine += 1
                newLine += 1
            }
        }
        return result
    }

    /// Parse `@@ -oldStart,oldCount +newStart,newCount @@` into starting line numbers.
    nonisolated static func parseHunkHeader(_ header: String) -> (old: Int, new: Int) {
        var old = 0
        var new = 0
        for part in header.split(separator: " ") {
            if part.hasPrefix("-") {
                old = Int(part.dropFirst().split(separator: ",").first ?? "") ?? 0
            } else if part.hasPrefix("+") {
                new = Int(part.dropFirst().split(separator: ",").first ?? "") ?? 0
            }
        }
        return (old, new)
    }
}

// MARK: - Diff Line Model

struct DiffLine {
    enum Kind {
        case added, removed, hunk, meta, context
    }

    let text: String
    let kind: Kind
    /// Actual file line number (new-file side for added/context, old-file side
    /// for removed). Nil for hunk/meta headers and synthetic edit-preview diffs.
    var lineNumber: Int? = nil
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Shared Indent Utility

nonisolated func stripCommonIndent(old: [String], new: [String]) -> (old: [String], new: [String]) {
    let combined = old + new
    let commonIndent = combined
        .filter { !$0.allSatisfy(\.isWhitespace) }
        .map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }
        .min() ?? 0
    guard commonIndent > 0 else { return (old, new) }
    func strip(_ line: String) -> String {
        line.count >= commonIndent ? String(line.dropFirst(commonIndent)) : line
    }
    return (old.map(strip), new.map(strip))
}

// MARK: - Diff Line Row

/// Shared single-line renderer used by both FileDiffView (sheet) and DiffViewerCard (inline).
struct DiffLineRow: View {
    let line: DiffLine
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    private var isAdded:   Bool { line.kind == .added }
    private var isRemoved: Bool { line.kind == .removed }
    private var isSpecial: Bool { line.kind == .hunk || line.kind == .meta }

    private var bg: Color {
        if isSelected { return ClaudeTheme.accent.opacity(0.15) }
        if isAdded    { return ClaudeTheme.statusSuccess.opacity(0.10) }
        if isRemoved  { return ClaudeTheme.statusError.opacity(0.10) }
        return .clear
    }

    private var codeText: String {
        let t = line.text
        guard !isSpecial, t.first == "+" || t.first == "-" else { return t }
        return String(t.dropFirst())
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isSpecial {
                Group {
                    if let num = line.lineNumber {
                        Text("\(num)")
                            .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))
                            .foregroundStyle(ClaudeTheme.textTertiary.opacity(0.5))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 38, alignment: .trailing)
                .padding(.trailing, 6)

                Text(isAdded ? "+" : isRemoved ? "−" : " ")
                    .font(.system(size: ClaudeTheme.messageSize(11), weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        isAdded   ? ClaudeTheme.statusSuccess :
                        isRemoved ? ClaudeTheme.statusError   : Color.clear
                    )
                    .frame(width: 16, alignment: .center)
            }

            Text(codeText.isEmpty ? " " : codeText)
                .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
                .foregroundStyle(isSpecial ? ClaudeTheme.textTertiary : ClaudeTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, isSpecial ? 10 : 6)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(bg)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

