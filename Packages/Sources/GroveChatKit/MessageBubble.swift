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
    @State private var processExpanded = false

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
                    // Assistant message: render blocks in order
                    let hidden = message.isStreaming ? [] : message.blocks.compactMap(\.toolCall).filter { isTransientTool($0) && $0.hasNonEmptyResult }
                    // Filter to only renderable blocks — exclude hidden transient tool blocks from ForEach
                    // to prevent zero-height TupleViews from introducing VStack spacing.
                    // Adjacent text blocks made contiguous by hidden tools are merged into a single bubble
                    // (so continuous text Claude sent across turns due to tool_use appears as one bubble)
                    let visibleBlocks = Self.mergeAdjacentTextBlocks(
                        in: message.blocks.filter { block in
                            if let text = block.text { return !text.isEmpty }
                            if let toolCall = block.toolCall {
                                if message.isStreaming { return true }
                                if isTransientTool(toolCall) { return false }
                                // Agent/Edit/Write tools are always shown even without a result
                                // Agent/Edit/Write/AskUserQuestion are always shown even without a result
                                if toolCall.isKeepAlways { return true }
                                // Other non-transient tools: only show when there is a result or error (prevents empty tool bubbles)
                                return toolCall.result != nil || toolCall.isError
                            }
                            if block.isThinking { return true }
                            return false
                        }
                    )

                    // Hidden tool summary — shown before text (reflects tool execution → text response order)
                    if !hidden.isEmpty {
                        transientToolSummary(hidden: hidden)
                    }

                    // Fold the "process" (leading thinking + tool calls) into a
                    // collapsible summary; the final answer text renders directly.
                    let split = Self.splitProcessAndAnswer(visibleBlocks)
                    let toolCount = split.process.filter { $0.toolCall != nil }.count
                    let shouldFold = !message.isStreaming && (toolCount >= 1 || split.process.count >= 2)

                    if shouldFold {
                        processFold(processBlocks: split.process, toolCount: toolCount, hasHiddenTools: !hidden.isEmpty)
                        ForEach(split.answer) { block in
                            blockView(block, hasHiddenTools: !hidden.isEmpty)
                        }
                    } else {
                        ForEach(visibleBlocks) { block in
                            blockView(block, hasHiddenTools: !hidden.isEmpty)
                        }
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
                        FlowLayout(spacing: 6) {
                            ForEach(edits) { edit in
                                FileEditPill(edit: edit) {
                                    windowState.diffFile = PreviewFile(
                                        path: edit.path, name: edit.name, editHunks: edit.hunks
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Process Fold (thinking + tool calls collapsed)

    /// Split an assistant message's blocks into the leading "process" (thinking +
    /// tool calls + intermediate text) and the trailing answer text.
    static func splitProcessAndAnswer(_ blocks: [MessageBlock]) -> (process: [MessageBlock], answer: [MessageBlock]) {
        var i = blocks.count
        while i > 0, let t = blocks[i - 1].text, !t.isEmpty { i -= 1 }
        return (Array(blocks[0..<i]), Array(blocks[i...]))
    }

    private func foldLabel(toolCount: Int, total: Int) -> String {
        if toolCount > 0 {
            let t = "\(toolCount) tool call\(toolCount == 1 ? "" : "s")"
            let m = "\(total) message\(total == 1 ? "" : "s")"
            return "\(t), \(m)"
        }
        return "\(total) step\(total == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func processFold(processBlocks: [MessageBlock], toolCount: Int, hasHiddenTools: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { processExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: processExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: ClaudeTheme.messageSize(9), weight: .semibold))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Text(foldLabel(toolCount: toolCount, total: processBlocks.count))
                        .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                    Image(systemName: "terminal")
                        .font(.system(size: ClaudeTheme.messageSize(10)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if processExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(processBlocks) { block in
                        blockView(block, hasHiddenTools: hasHiddenTools)
                    }
                }
                .padding(.leading, 10)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MessageBlock, hasHiddenTools: Bool) -> some View {
        if let text = block.text, !text.isEmpty {
            assistantTextBubble(text: text, blockId: block.id, hasHiddenTools: hasHiddenTools)
        }
        if let toolCall = block.toolCall {
            if toolCall.name == "AskUserQuestion" {
                AskUserQuestionView(toolCall: toolCall)
            } else {
                PlainActivityRow(item: .toolCall(toolCall))
            }
        }
        if block.isThinking {
            ThinkingBlockView(block: block, isMessageStreaming: message.isStreaming)
        }
    }

    // MARK: - Compact Boundary Bubble

    private var compactBoundaryBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
            Text(message.content)
                .font(.system(size: ClaudeTheme.messageSize(13), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                .fill(ClaudeTheme.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                .strokeBorder(ClaudeTheme.border, lineWidth: BubbleStyle.borderWidth)
        )
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

    private func assistantTextBubble(text: String, blockId: String, hasHiddenTools: Bool = false) -> some View {
        // "Last block" for cursor purposes means the last TEXT block — a trailing
        // thinking block (rare but possible) must not strip the streaming cursor.
        let lastText = message.blocks.last(where: \.isText)
        let isLastBlock = lastText?.id == blockId && lastText?.text == text

        return HStack(alignment: .bottom, spacing: 0) {
            if message.isStreaming && isLastBlock {
                Text(text)
                    .font(.system(size: ClaudeTheme.messageSize(15)))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownContentView(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if message.isStreaming && isLastBlock {
                Text("|")
                    .font(.system(size: ClaudeTheme.messageSize(15), weight: .light))
                    .foregroundStyle(ClaudeTheme.accent)
                    .opacity(cursorVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorVisible)
                    .onAppear { cursorVisible = false }
            }
        }
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
        .onTapGesture {
            if hasHiddenTools {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTransientTools.toggle()
                }
            }
        }
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

    // MARK: - Transient Tool Helpers

    /// Read, Grep, Glob, Bash etc. are collapsed into a summary after streaming completes
    private func isTransientTool(_ toolCall: ToolCall) -> Bool {
        let cat = ToolCategory(toolName: toolCall.name)
        return cat == .readOnly || cat == .execution
    }

    /// Merges adjacent text blocks made contiguous by hidden transient tools.
    /// Displays continuous text Claude split across turns due to tool_use as a single bubble.
    ///
    /// Join rule: respects original trailing/leading whitespace; adds a single space only when
    /// neither side has whitespace. Forced paragraph breaks would split bullets mid-list,
    /// so they are avoided — even text following a complete sentence joins naturally with a single space.
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

    @State private var showTransientTools = false

    private func transientToolSummary(hidden: [ToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTransientTools.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: ClaudeTheme.messageSize(11)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Text(String(format: String(localized: "%lld tools executed", bundle: .module), hidden.count))
                        .font(.system(size: ClaudeTheme.messageSize(12)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Image(systemName: showTransientTools ? "chevron.up" : "chevron.down")
                        .font(.system(size: ClaudeTheme.messageSize(9)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showTransientTools {
                ForEach(hidden, id: \.id) { toolCall in
                    PlainActivityRow(item: .toolCall(toolCall))
                }
            }
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if message.role == .user {
            return UnevenRoundedRectangle(
                topLeadingRadius: ClaudeTheme.cornerRadiusLarge,
                bottomLeadingRadius: ClaudeTheme.cornerRadiusLarge,
                bottomTrailingRadius: 4,
                topTrailingRadius: ClaudeTheme.cornerRadiusLarge
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: ClaudeTheme.cornerRadiusLarge,
                bottomLeadingRadius: 4,
                bottomTrailingRadius: ClaudeTheme.cornerRadiusLarge,
                topTrailingRadius: ClaudeTheme.cornerRadiusLarge
            )
        }
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
            switch tc.name.lowercased() {
            case "write":
                let content = tc.input["content"]?.stringValue ?? ""
                added = lineCount(content)
                hunks = [PreviewFile.EditHunk(oldString: "", newString: content)]
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
                map[path] = existing
            } else {
                map[path] = FileEdit(path: path, added: added, removed: removed, hunks: hunks)
                order.append(path)
            }
        }
        return order.compactMap { map[$0] }
    }

}

// MARK: - File Edit Pill (+ hover diff preview)

/// A file touched by a turn's Edit/Write/MultiEdit tool calls, with rough
/// added/removed line counts and the hunks needed to render/open its diff.
struct FileEdit: Identifiable {
    let path: String
    var added: Int
    var removed: Int
    var hunks: [PreviewFile.EditHunk]
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// Compact pill: file icon + name + `+adds`/`-removed`. Hover shows a diff
/// preview popover; click opens the full diff.
private struct FileEditPill: View {
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
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: ClaudeTheme.messageSize(10)))
                    .foregroundStyle(ClaudeTheme.statusWarning)
                Text(edit.name)
                    .font(.system(size: ClaudeTheme.messageSize(11), weight: .medium))
                    .foregroundStyle(ClaudeTheme.textSecondary)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ClaudeTheme.surfacePrimary, in: Capsule())
            .overlay(Capsule().strokeBorder(ClaudeTheme.border, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerCursorOnHover()
        .onHover { hovering = $0 }
        .popover(isPresented: $hovering, arrowEdge: .bottom) {
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

/// A simple wrapping layout: lays subviews left-to-right, wrapping to the next
/// row when the proposed width is exceeded. Used for the file-edit pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

