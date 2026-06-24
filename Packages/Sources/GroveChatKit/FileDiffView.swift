import SwiftUI
import AppKit
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
        DiffTextRenderer(lines: diffLines) { index in
            // Only commentable on real source lines, not hunk/meta headers.
            if let index, let line = diffLines[safe: index],
               line.kind != .hunk, line.kind != .meta {
                selectedLineIndex = index
            } else {
                selectedLineIndex = nil
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

        var foregroundColor: Color {
            switch self {
            case .added:   return ClaudeTheme.statusSuccess
            case .removed: return ClaudeTheme.statusError
            case .hunk:    return ClaudeTheme.textTertiary
            case .meta:    return ClaudeTheme.textTertiary
            case .context: return ClaudeTheme.textPrimary
            }
        }
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

// MARK: - NSTextView-based Renderer (TextKit2)

private struct DiffTextRenderer: NSViewRepresentable {
    let lines: [DiffLine]
    /// Reports the index of the diff line containing the selection/caret (nil if none).
    var onSelectLine: (Int?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        // Disable auto horizontal resize: forces NSTextView to lay out the entire
        // document up front to compute frame width. We size the container manually
        // so TextKit2's viewport-based vertical layout stays lazy.
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        if let container = textView.textContainer {
            // Bounded width = TextKit2 keeps vertical layout lazy (viewport-only),
            // long lines wrap to fit visible area, no full-document layout pass.
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            container.containerSize = NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude
            )
            container.lineFragmentPadding = 0
        }

        scrollView.documentView = textView
        textView.delegate = context.coordinator
        context.coordinator.onSelectLine = onSelectLine
        context.coordinator.attach(textView: textView, lines: lines)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onSelectLine = onSelectLine
        context.coordinator.update(textView: textView, lines: lines)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private weak var textView: NSTextView?
        private var lastLines: [DiffLine] = []
        private var lastFingerprint: Int = 0
        /// Character range of each diff line in the rendered string, for caret→line mapping.
        private var lineRanges: [NSRange] = []
        private var lastReportedLine: Int?
        var onSelectLine: (Int?) -> Void = { _ in }
        nonisolated(unsafe) private var themeObserver: NSObjectProtocol?

        deinit {
            if let observer = themeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(textView: NSTextView, lines: [DiffLine]) {
            self.textView = textView
            apply(lines: lines, to: textView)
            registerThemeObserver()
        }

        func update(textView: NSTextView, lines: [DiffLine]) {
            let fp = fingerprint(of: lines)
            if fp == lastFingerprint, textView === self.textView { return }
            self.textView = textView
            apply(lines: lines, to: textView)
        }

        private func registerThemeObserver() {
            guard themeObserver == nil else { return }
            themeObserver = NotificationCenter.default.addObserver(
                forName: .groveThemeDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let tv = self.textView else { return }
                    self.apply(lines: self.lastLines, to: tv)
                }
            }
        }

        private func apply(lines: [DiffLine], to textView: NSTextView) {
            let (attributed, ranges) = Self.buildAttributedString(lines: lines)
            textView.textStorage?.setAttributedString(attributed)
            lineRanges = ranges
            lastReportedLine = nil
            lastLines = lines
            lastFingerprint = fingerprint(of: lines)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let location = textView.selectedRange().location
            let index = lineRanges.firstIndex { NSLocationInRange(location, $0) }
                ?? (location >= (lineRanges.last.map { $0.location + $0.length } ?? 0) ? lineRanges.indices.last : nil)
            guard index != lastReportedLine else { return }
            lastReportedLine = index
            onSelectLine(index)
        }

        private func fingerprint(of lines: [DiffLine]) -> Int {
            var hasher = Hasher()
            hasher.combine(lines.count)
            if let first = lines.first {
                hasher.combine(first.text)
                hasher.combine(first.kind)
            }
            if let last = lines.last, lines.count > 1 {
                hasher.combine(last.text)
                hasher.combine(last.kind)
            }
            return hasher.finalize()
        }

        private static func buildAttributedString(lines: [DiffLine]) -> (NSAttributedString, [NSRange]) {
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let gutterColor = NSColor(ClaudeTheme.textTertiary).withAlphaComponent(0.6)
            let maxNumber = lines.compactMap(\.lineNumber).max() ?? lines.count
            let gutterDigits = max(String(maxNumber).count, 2)
            let blankPrefix = String(repeating: " ", count: gutterDigits) + "  "

            let result = NSMutableAttributedString()
            var ranges: [NSRange] = []
            for (index, line) in lines.enumerated() {
                let lineStart = result.length
                let prefix: String
                if line.kind == .meta || line.kind == .hunk {
                    prefix = blankPrefix
                } else {
                    let n = String(line.lineNumber ?? (index + 1))
                    prefix = String(repeating: " ", count: max(0, gutterDigits - n.count)) + n + "  "
                }
                result.append(NSAttributedString(string: prefix, attributes: [
                    .font: font,
                    .foregroundColor: gutterColor,
                ]))

                let bodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(line.kind.foregroundColor),
                ]
                let bodyText = (line.text.isEmpty ? " " : line.text) + "\n"
                result.append(NSAttributedString(string: bodyText, attributes: bodyAttrs))
                ranges.append(NSRange(location: lineStart, length: result.length - lineStart))
            }
            return (result, ranges)
        }
    }
}
