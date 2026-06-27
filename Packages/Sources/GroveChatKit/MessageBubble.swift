import SwiftUI
import AppKit
import GroveCore

struct MessageBubble: View {
    @Environment(ChatBridge.self) private var chatBridge
    @Environment(WindowState.self) private var windowState
    let message: ChatMessage
    @State private var isCopied = false
    @State private var cursorVisible = true
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isEditFocused: Bool
    @State private var isLongTextExpanded = false
    @State private var hoveredBlockId: String? = nil
    @State private var isHoveringUserBubble = false

    /// Threshold (character count) for collapsing long text
    private static let longTextThreshold = 500

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Show attachments
                if !message.attachmentPaths.isEmpty {
                    attachmentPreview
                }

                if message.role == .user {
                    // User message: single text bubble
                    if !message.content.isEmpty {
                        textBubble
                    }
                } else if message.isCompactBoundary {
                    compactBoundaryBubble
                } else if message.isError {
                    // Error message: warning-style bubble
                    errorBubble
                } else {
                    // Render blocks in order. During streaming show everything;
                    // after completion show only blocks with content/results.
                    let visibleBlocks = Self.mergeAdjacentTextBlocks(
                        in: message.blocks.filter { block in
                            if let text = block.text { return !text.isEmpty }
                            if let toolCall = block.toolCall {
                                if message.isStreaming { return true }
                                if toolCall.isKeepAlways { return true }
                                return toolCall.result != nil || toolCall.isError
                            }
                            if block.isThinking { return true }
                            return false
                        }
                    )
                    ForEach(visibleBlocks) { block in
                        blockView(block)
                    }
                }

                // Response complete indicator + elapsed time
                if message.role == .assistant && !message.isStreaming,
                   let duration = message.duration {
                    HStack(spacing: 4) {
                        if message.isResponseComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: ClaudeTheme.messageSize(11)))
                                .foregroundStyle(ClaudeTheme.statusSuccess)
                        }
                        Text(duration.formattedDuration)
                            .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                    }
                }

                // Files changed this turn — pills with diff stats, always visible
                // even when the process is folded. Click to open the diff.
                if message.role == .assistant && !message.isStreaming {
                    let edits = fileEdits
                    if !edits.isEmpty {
                        ChangedFilesCard(edits: edits) { edit in
                            windowState.diffFile = PreviewFile(
                                path: edit.path, name: edit.name, editHunks: edit.hunks
                            )
                        }
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MessageBlock) -> some View {
        if let text = block.text, !text.isEmpty {
            assistantTextBubble(text: text, blockId: block.id)
        }
        if let toolCall = block.toolCall {
            if toolCall.name == "AskUserQuestion" {
                AskUserQuestionView(toolCall: toolCall)
            } else {
                PlainActivityRow(item: .toolCall(toolCall), isMessageStreaming: message.isStreaming)
            }
        }
        if block.isThinking, let text = block.thinking, !text.isEmpty {
            PlainActivityRow(item: .thinking(id: block.id, text: text, duration: block.thinkingDuration), isMessageStreaming: message.isStreaming)
        }
    }

    // MARK: - Compact Boundary Bubble

    private var compactBoundaryBubble: some View {
        ChatMarker(icon: "arrow.trianglehead.2.clockwise", label: message.content)
    }

    // MARK: - Error Bubble

    private var errorBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: ClaudeTheme.messageSize(13)))
                .foregroundStyle(ClaudeTheme.statusWarning)
            Text(message.content)
                .font(.system(size: ClaudeTheme.messageSize(14)))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .textSelection(.enabled)
        }
        .bubbleStyle(.error)
    }

    // MARK: - User Text Bubble

    @ViewBuilder
    private var textBubble: some View {
        if isEditing {
            VStack(alignment: .trailing, spacing: 8) {
                TextField(String(localized: "Edit message...", bundle: .module), text: $editText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: ClaudeTheme.messageSize(14)))
                    .foregroundStyle(ClaudeTheme.userBubbleText)
                    .focused($isEditFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(ClaudeTheme.userBubble, in: bubbleShape)
                    .overlay(
                        bubbleShape
                            .strokeBorder(ClaudeTheme.accent, lineWidth: 1.5)
                    )
                    .onKeyPress(.return, phases: .down) { keyPress in
                        guard !keyPress.modifiers.contains(.shift) else { return .ignored }
                        submitEdit()
                        return .handled
                    }
                    .onKeyPress(.escape, phases: .down) { _ in
                        isEditing = false
                        return .handled
                    }

                HStack(spacing: 8) {
                    Button(String(localized: "Cancel", bundle: .module)) {
                        isEditing = false
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: ClaudeTheme.messageSize(12)))
                    .foregroundStyle(ClaudeTheme.textSecondary)

                    Button(String(localized: "Send", bundle: .module)) {
                        submitEdit()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                    .foregroundStyle(ClaudeTheme.accent)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                let isLong = message.content.count > Self.longTextThreshold
                Text(message.content)
                    .font(.system(size: ClaudeTheme.messageSize(14)))
                    .foregroundStyle(ClaudeTheme.userBubbleText)
                    .textSelection(.enabled)
                    .lineLimit(isLong && !isLongTextExpanded ? 5 : nil)
                if isLong {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLongTextExpanded.toggle()
                        }
                    } label: {
                        if isLongTextExpanded {
                            Text("Collapse", bundle: .module)
                        } else {
                            Text("Show more", bundle: .module)
                        }
                    }
                    .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                    .foregroundStyle(ClaudeTheme.accent)
                    .buttonStyle(.plain)
                }
            }
            .bubbleStyle(.user)
            .overlay(alignment: .bottomTrailing) {
                if isHoveringUserBubble {
                    HStack(spacing: 3) {
                        userActionButton(systemName: isCopied ? "checkmark" : "doc.on.doc") {
                            copyToClipboard(message.content, feedback: $isCopied)
                        }
                        userActionButton(systemName: "pencil") {
                            editText = message.content
                            isEditing = true
                        }
                    }
                    .padding(5)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
            .onHover { isHoveringUserBubble = $0 }
            .onChange(of: isEditing) { _, editing in
                if editing { isEditFocused = true }
            }
        }
    }

    // MARK: - Assistant Text Bubble

    private func assistantTextBubble(text: String, blockId: String) -> some View {
        // "Last block" for cursor purposes means the last TEXT block — a trailing
        // thinking block (rare but possible) must not strip the streaming cursor.
        let lastText = message.blocks.last(where: \.isText)
        let isLastBlock = lastText?.id == blockId && lastText?.text == text

        return HStack(alignment: .bottom, spacing: 0) {
            if message.isStreaming && isLastBlock {
                Text(text)
                    .font(.system(size: ClaudeTheme.messageSize(12)))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownContentView(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.asymmetric(
                        insertion: .modifier(
                            active: EmergeModifier(progress: 0),
                            identity: EmergeModifier(progress: 1)
                        ),
                        removal: .identity
                    ))
            }
            if message.isStreaming && isLastBlock {
                Text("|")
                    .font(.system(size: ClaudeTheme.messageSize(12), weight: .light))
                    .foregroundStyle(ClaudeTheme.accent)
                    .opacity(cursorVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorVisible)
                    .onAppear { cursorVisible = false }
            }
        }
        .animation(.spring(duration: 0.7, bounce: 0.1), value: message.isStreaming)
        .foregroundStyle(ClaudeTheme.textPrimary)
        .bubbleStyle(.assistant)
        .overlay(alignment: .bottomTrailing) {
            if hoveredBlockId == blockId && !message.isStreaming {
                HStack(spacing: 4) {
                    copyButton(for: text)
                    forkButton()
                }
                .padding(6)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .onHover { hoveredBlockId = $0 ? blockId : nil }
        .accessibilityLabel("Assistant: \(text)")
    }

    // MARK: - Copy Button

    @ViewBuilder
    private func copyButton(for text: String) -> some View {
        Button {
            copyToClipboard(text, feedback: $isCopied)
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(ClaudeTheme.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func forkButton() -> some View {
        Button {
            Task { await chatBridge.forkFromHere(messageId: message.id) }
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .frame(width: 26, height: 26)
                .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(ClaudeTheme.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(String(localized: "Fork from here", bundle: .module))
    }

    @ViewBuilder
    private func userActionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .frame(width: 24, height: 24)
                .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(ClaudeTheme.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .opacity(0.8)
    }

    private static func mergeAdjacentTextBlocks(in blocks: [MessageBlock]) -> [MessageBlock] {
        var result: [MessageBlock] = []
        for block in blocks {
            if block.isText,
               let lastIdx = result.indices.last,
               result[lastIdx].isText {
                let prev = result[lastIdx].text ?? ""
                let curr = block.text ?? ""
                let needsSpace = !(prev.last?.isWhitespace ?? true) && !(curr.first?.isWhitespace ?? true)
                let joined = needsSpace ? prev + " " + curr : prev + curr
                // Preserve original block id to ensure ForEach diff stability
                result[lastIdx] = .text(joined, id: result[lastIdx].id)
            } else {
                result.append(block)
            }
        }
        return result
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 4,
            bottomLeadingRadius: 4,
            bottomTrailingRadius: 4,
            topTrailingRadius: 4
        )
    }

    private func submitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isEditing = false
        Task { await chatBridge.editAndResend(messageId: message.id, newContent: trimmed) }
    }

    // MARK: - Attachment Preview

    private var attachmentPreview: some View {
        HStack(spacing: 6) {
            ForEach(message.attachmentPaths, id: \.path) { info in
                HStack(spacing: 4) {
                    if info.isImage, let nsImage = NSImage(contentsOfFile: info.path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
                    } else {
                        Image(systemName: info.isImage ? "photo" : "doc")
                            .font(.system(size: ClaudeTheme.messageSize(14)))
                            .foregroundStyle(ClaudeTheme.accent)
                    }
                    Text(info.name)
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(6)
                .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
            }
        }
    }

    /// Converts bare URLs to clickable links (without full markdown rendering)
    private func linkifiedAttributedString(_ text: String) -> AttributedString {
        let autoLinked = autoLinkURLs(text)
        return (try? AttributedString(
            markdown: autoLinked,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    // MARK: - File Edit Pills

    private func lineCount(_ s: String) -> Int {
        s.isEmpty ? 0 : s.components(separatedBy: "\n").count
    }

    /// Aggregate every file-modifying tool call in the message by file path.
    private var fileEdits: [FileEdit] {
        var map: [String: FileEdit] = [:]
        var order: [String] = []
        for block in message.blocks {
            guard let tc = block.toolCall,
                  let path = tc.input["file_path"]?.stringValue else { continue }
            var added = 0, removed = 0
            var hunks: [PreviewFile.EditHunk] = []
            var status: FileEdit.Status = .modified
            switch tc.name.lowercased() {
            case "write":
                let content = tc.input["content"]?.stringValue ?? ""
                added = lineCount(content)
                hunks = [PreviewFile.EditHunk(oldString: "", newString: content)]
                status = .added
            case "edit":
                let old = tc.input["old_string"]?.stringValue ?? ""
                let new = tc.input["new_string"]?.stringValue ?? ""
                removed = lineCount(old); added = lineCount(new)
                hunks = [PreviewFile.EditHunk(oldString: old, newString: new)]
            case "multiedit", "multi_edit":
                for entry in tc.input["edits"]?.arrayValue ?? [] {
                    guard let obj = entry.objectValue else { continue }
                    let old = obj["old_string"]?.stringValue ?? ""
                    let new = obj["new_string"]?.stringValue ?? ""
                    removed += lineCount(old); added += lineCount(new)
                    hunks.append(PreviewFile.EditHunk(oldString: old, newString: new))
                }
            default:
                continue
            }
            if var existing = map[path] {
                existing.added += added
                existing.removed += removed
                existing.hunks.append(contentsOf: hunks)
                // A file created then edited in the same turn is still "added".
                if existing.status != .added { existing.status = status }
                map[path] = existing
            } else {
                map[path] = FileEdit(path: path, added: added, removed: removed, hunks: hunks, status: status)
                order.append(path)
            }
        }
        return order.compactMap { map[$0] }
    }

}

// MARK: - Changed Files Card (+ per-file hover diff preview)

/// A file touched by a turn's Edit/Write/MultiEdit tool calls, with rough
/// added/removed line counts and the hunks needed to render/open its diff.
struct FileEdit: Identifiable {
    let path: String
    var added: Int
    var removed: Int
    var hunks: [PreviewFile.EditHunk]
    var status: Status = .modified
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }

    /// Adopted from the AI Commit component's file-status indicators.
    enum Status {
        case added, modified

        var label: String { self == .added ? "A" : "M" }

        @MainActor var color: Color {
            self == .added ? ClaudeTheme.statusSuccess : ClaudeTheme.statusWarning
        }
    }
}

/// Collapsible card listing the files a turn changed — adapted from the AI
/// Commit component. Header is a summary ("N files changed" + total +/-) that
/// toggles a file list; each row shows status (A/M) · icon · path · +adds/-dels.
private struct ChangedFilesCard: View {
    let edits: [FileEdit]
    let onOpen: (FileEdit) -> Void
    @State private var isExpanded = false

    private var totalAdded: Int { edits.reduce(0) { $0 + $1.added } }
    private var totalRemoved: Int { edits.reduce(0) { $0 + $1.removed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to expand/collapse the file list
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: ClaudeTheme.messageSize(9), weight: .semibold))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Text("\(edits.count) file\(edits.count == 1 ? "" : "s") changed")
                        .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                    Spacer(minLength: 8)
                    if totalAdded > 0 {
                        Text(verbatim: "+\(totalAdded)")
                            .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))
                            .foregroundStyle(ClaudeTheme.statusSuccess)
                    }
                    if totalRemoved > 0 {
                        Text(verbatim: "-\(totalRemoved)")
                            .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))
                            .foregroundStyle(ClaudeTheme.statusError)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle()
                    .fill(ClaudeTheme.border)
                    .frame(height: 0.5)
                VStack(spacing: 0) {
                    ForEach(edits) { edit in
                        ChangedFileRow(edit: edit) { onOpen(edit) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(ClaudeTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ClaudeTheme.border, lineWidth: 0.5))
    }
}

/// One row in the changed-files list. Hover shows a diff preview popover;
/// click opens the full diff.
private struct ChangedFileRow: View {
    let edit: FileEdit
    let onOpen: () -> Void
    @State private var hovering = false

    private var icon: String {
        switch (edit.name as NSString).pathExtension.lowercased() {
        case "swift":                                return "swift"
        case "md", "markdown", "txt", "rtf":         return "doc.text"
        case "json", "yml", "yaml", "toml", "plist": return "curlybraces"
        case "sh", "bash", "zsh", "fish":            return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg", "pdf": return "photo"
        default:                                     return "doc"
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Text(edit.status.label)
                    .font(.system(size: ClaudeTheme.messageSize(11), weight: .semibold, design: .monospaced))
                    .foregroundStyle(edit.status.color)
                    .frame(width: 12)
                Image(systemName: icon)
                    .font(.system(size: ClaudeTheme.messageSize(10)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                Text(edit.name)
                    .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if edit.added > 0 {
                    Text(verbatim: "+\(edit.added)")
                        .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))
                        .foregroundStyle(ClaudeTheme.statusSuccess)
                }
                if edit.removed > 0 {
                    Text(verbatim: "-\(edit.removed)")
                        .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))
                        .foregroundStyle(ClaudeTheme.statusError)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(hovering ? ClaudeTheme.surfaceSecondary.opacity(0.6) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursorOnHover()
        .onHover { hovering = $0 }
        .popover(isPresented: $hovering, arrowEdge: .trailing) {
            EditDiffPreview(edit: edit)
        }
    }
}

/// Hover popover: the file path + a colored diff of the edit hunks.
private struct EditDiffPreview: View {
    let edit: FileEdit

    private var lines: [DiffLine] {
        FileDiffView.buildEditDiffLines(from: edit.hunks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(edit.path)
                    .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium, design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 12)
                if edit.added > 0 {
                    Text(verbatim: "+\(edit.added)")
                        .foregroundStyle(ClaudeTheme.statusSuccess)
                }
                if edit.removed > 0 {
                    Text(verbatim: "-\(edit.removed)")
                        .foregroundStyle(ClaudeTheme.statusError)
                }
            }
            .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))

            ClaudeThemeDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: ClaudeTheme.messageSize(11), design: .monospaced))
                            .foregroundStyle(line.kind.foregroundColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 0.5)
                            .background(diffRowBackground(line.kind))
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(12)
        .frame(width: 460)
        .background(ClaudeTheme.codeBackground)
    }

    private func diffRowBackground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added:   return ClaudeTheme.statusSuccess.opacity(0.08)
        case .removed: return ClaudeTheme.statusError.opacity(0.08)
        default:       return .clear
        }
    }
}

// MARK: - Flow Layout

private struct EmergeModifier: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .offset(y: (1.0 - progress) * 12)
            .blur(radius: (1.0 - progress) * 3)
            .scaleEffect(0.97 + 0.03 * progress, anchor: .top)
            .opacity(0.2 + 0.8 * progress)
    }
}

