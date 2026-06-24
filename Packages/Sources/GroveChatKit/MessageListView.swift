import SwiftUI
import Combine
import GroveCore

/// Message scroll area — extracted from ChatView to isolate @Observable dependencies on `messages`.
struct MessageListView: View {
    @Environment(ChatBridge.self) private var chatBridge
    @Environment(WindowState.self) private var windowState
    @State private var scrollPosition = ScrollPosition()
    @State private var settledItems: [ChatMessage] = []
    @State private var scrollTask: Task<Void, Never>?
    @State private var isNearBottom = true
    @State private var isOlderCollapsed = true
    @State private var isSessionReady = false

    private let foldThreshold = 30

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Fold older messages when count exceeds threshold
                if settledItems.count > foldThreshold {
                    let hiddenCount = settledItems.count - foldThreshold

                    // Expanded state: show older messages
                    if !isOlderCollapsed {
                        messageRows(settledItems.prefix(hiddenCount))
                    }

                    // Fold toggle button
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isOlderCollapsed.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Group {
                                if isOlderCollapsed {
                                    Text(String(format: String(localized: "Show %lld earlier messages", bundle: .module), hiddenCount))
                                } else {
                                    Text("Collapse earlier messages", bundle: .module)
                                }
                            }
                            .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                            Image(systemName: isOlderCollapsed ? "chevron.down" : "chevron.up")
                                .font(.system(size: ClaudeTheme.size(10), weight: .medium))
                        }
                        .foregroundStyle(ClaudeTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                                .fill(ClaudeTheme.surfacePrimary.opacity(0.6))
                        )
                    }
                    .buttonStyle(.plain)

                    messageRows(settledItems.suffix(foldThreshold))
                } else {
                    messageRows(settledItems[...])
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Streaming view is outside VStack — text deltas don't affect settled layout
            VStack(spacing: 16) {
                if !windowState.focusMode {
                    StreamingMessageView {
                        rebuildSettledItems()
                        if isNearBottom { scrollToBottomDebounced() }
                    }
                }

                if chatBridge.isStreaming {
                    HStack(alignment: .top, spacing: 0) {
                        StreamingIndicatorView(
                            isThinking: chatBridge.isThinking,
                            startDate: chatBridge.streamingStartDate
                        )
                        Spacer(minLength: 40)
                    }
                }

                if !chatBridge.isStreaming && !settledItems.isEmpty {
                    WebPreviewButton(messages: settledItems)
                        .id("web-preview")
                }
            }
            .padding(.horizontal, 20)
            // Suppress layout animations when switching sessions so the pulse indicator
            // doesn't visually jump as StreamingMessageView changes height.
            .animation(.none, value: windowState.currentSessionId)

            Color.clear.frame(height: 1)
                .padding(.bottom, 16)
        }
        .opacity(isSessionReady ? 1 : 0)
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geo in
            let distanceFromBottom = geo.contentSize.height - geo.visibleRect.maxY
            return distanceFromBottom < 120
        } action: { _, nearBottom in
            isNearBottom = nearBottom
        }
        .task(id: windowState.currentSessionId) {
            isSessionReady = false
            scrollTask?.cancel()
            isOlderCollapsed = true
            scrollPosition = ScrollPosition()
            rebuildSettledItems()
            // Skip scroll/fade delay for empty sessions — appear instantly
            guard !settledItems.isEmpty else {
                isSessionReady = true
                return
            }
            try? await Task.sleep(for: .milliseconds(16))  // 1 frame: scroll after VStack layout is committed
            scrollPosition.scrollTo(edge: .bottom)
            // Pre-set isNearBottom so streaming messages that arrive before onScrollGeometryChange
            // fires still trigger scrollToBottomDebounced(), keeping the pulse pinned to the bottom.
            isNearBottom = true
            try? await Task.sleep(for: .milliseconds(32))  // 2 frames: fade-in after scroll settles
            withAnimation(.easeIn(duration: 0.15)) { isSessionReady = true }
        }
        .onChange(of: chatBridge.isStreaming) { old, new in
            // Only update when streaming ends — settled list doesn't change at start, so skip
            if old && !new {
                rebuildSettledItems()
                scrollToBottomDebounced()
            }
        }
        .overlay {
            if settledItems.isEmpty && !chatBridge.isStreaming && windowState.currentSessionId == nil {
                EmptySessionView()
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func messageRows(_ messages: some RandomAccessCollection<ChatMessage>) -> some View {
        // Settled list: collapse each completed turn's intermediate activity
        // (tool calls + narration) into a single summary, leaving the final
        // answer visible. The live-streaming path uses its own grouping.
        let groups = groupSettledTurns(Array(messages))
        ForEach(groups) { group in
            if group.isTransientGroup {
                TurnActivitySummaryView(messages: group.messages)
                    .id(group.id)
            } else if let message = group.messages.first {
                MessageBubble(message: message)
                    .id(message.id)
            }
        }
    }

    // MARK: - Message Grouping

    // MARK: - Settled Items

    private func rebuildSettledItems() {
        let messages = settledOnlyMessages(from: chatBridge.messages)
        var t = Transaction()
        t.animation = nil
        withTransaction(t) { settledItems = messages }
    }

    /// If streaming, returns only completed messages excluding the last consecutive (non-error) assistant sequence.
    /// If not streaming, returns all messages without the streaming flag.
    /// In focus mode, further filters to only user messages and completed assistant responses.
    private func settledOnlyMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        var settled: [ChatMessage]
        if messages.last?.isStreaming == true {
            let boundary = streamingBoundaryIndex(in: messages)
            settled = Array(messages[..<boundary]).filter { !$0.isStreaming }
        } else {
            settled = messages.filter { !$0.isStreaming }
        }
        if windowState.focusMode {
            settled = settled.filter { $0.role == .user || $0.isResponseComplete || $0.isCompactBoundary }
        }
        return settled
    }

    private func scrollToBottomDebounced() {
        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            scrollPosition.scrollTo(edge: .bottom)
        }
    }
}

// MARK: - Message Grouping Helpers

/// Single-pass partition of messages into (settled, streaming) without scanning the array twice.
fileprivate func partitionByStreaming(_ messages: [ChatMessage]) -> (settled: [ChatMessage], streaming: [ChatMessage]) {
    var settled: [ChatMessage] = []
    var streaming: [ChatMessage] = []
    for m in messages { if m.isStreaming { streaming.append(m) } else { settled.append(m) } }
    return (settled, streaming)
}


fileprivate struct MessageGroup: Identifiable {
    let id: UUID
    let messages: [ChatMessage]
    let isTransientGroup: Bool
}

/// Returns true if the message would render only a transient tool summary (no visible text or non-transient tools).
fileprivate func isPureTransientMessage(_ message: ChatMessage) -> Bool {
    guard message.role == .assistant, !message.isError, !message.isCompactBoundary else { return false }
    // Whitespace-only text is treated as invisible so it doesn't break transient grouping.
    let hasVisibleText = message.blocks.contains {
        guard let text = $0.text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    if hasVisibleText { return false }
    let toolCalls = message.blocks.compactMap(\.toolCall)
    guard !toolCalls.isEmpty else { return false }
    let hasNonTransient = toolCalls.contains { !ToolCategory(toolName: $0.name).isTransient }
    if hasNonTransient { return false }
    return true
}

/// Returns true if the message has no renderable content — all tool calls were removed
/// (e.g. empty bash output stripped by setToolResult) and there is no text.
/// These messages are invisible in the UI and should not break transient-tool grouping.
fileprivate func isInvisibleMessage(_ message: ChatMessage) -> Bool {
    guard message.role == .assistant, !message.isError, !message.isCompactBoundary, !message.isStreaming else { return false }
    return message.blocks.isEmpty
}

/// Groups consecutive pure-transient assistant messages into combined groups.
/// - Parameter minGroupSize: Minimum number of transient messages required to collapse into a group.
///   Pass 1 (streaming context) to hide even a single completed tool call the moment the next message starts.
///   Pass 2 (settled list) to keep lone tool calls visible after streaming ends.
fileprivate func groupMessages(_ messages: [ChatMessage], minGroupSize: Int = 2) -> [MessageGroup] {
    var result: [MessageGroup] = []
    var accumulator: [ChatMessage] = []

    func flushAccumulator() {
        guard !accumulator.isEmpty else { return }
        if accumulator.count >= minGroupSize {
            result.append(MessageGroup(id: accumulator[0].id, messages: accumulator, isTransientGroup: true))
        } else {
            for m in accumulator {
                result.append(MessageGroup(id: m.id, messages: [m], isTransientGroup: false))
            }
        }
        accumulator = []
    }

    for message in messages {
        if isPureTransientMessage(message) {
            accumulator.append(message)
        } else if isInvisibleMessage(message) {
            // Skip invisible messages (e.g. all tool calls removed due to empty results).
            // They render nothing in the UI and must not break consecutive transient grouping.
            continue
        } else {
            flushAccumulator()
            result.append(MessageGroup(id: message.id, messages: [message], isTransientGroup: false))
        }
    }
    flushAccumulator()

    return result
}

// MARK: - Turn-Aware Settled Grouping

fileprivate func messageHasVisibleText(_ message: ChatMessage) -> Bool {
    message.blocks.contains {
        guard let text = $0.text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// IDs of the trailing text-only assistant messages that make up each turn's
/// final answer. Everything else in a completed turn is intermediate activity
/// (tool calls + narration) that collapses into a single summary.
fileprivate func finalAnswerMessageIDs(in messages: [ChatMessage]) -> Set<UUID> {
    func isTurnMember(_ m: ChatMessage) -> Bool {
        m.role == .assistant && !m.isError && !m.isCompactBoundary && !m.isStreaming
    }
    var ids: Set<UUID> = []
    var i = 0
    while i < messages.count {
        guard isTurnMember(messages[i]) else { i += 1; continue }
        var j = i
        while j < messages.count && isTurnMember(messages[j]) { j += 1 }
        // Walk back from the turn's end over messages that are text with no
        // tool calls — those form the final answer.
        var k = j - 1
        while k >= i, messageHasVisibleText(messages[k]), messages[k].blocks.compactMap(\.toolCall).isEmpty {
            ids.insert(messages[k].id)
            k -= 1
        }
        i = j
    }
    return ids
}

/// Settled-list grouping: every intermediate (non-final-answer) assistant
/// message of a completed turn folds into one collapsible summary. Final
/// answers, user messages, errors, and compact boundaries render as-is.
fileprivate func groupSettledTurns(_ messages: [ChatMessage]) -> [MessageGroup] {
    let finalAnswers = finalAnswerMessageIDs(in: messages)
    var result: [MessageGroup] = []
    var accumulator: [ChatMessage] = []

    func isCollapsibleIntermediate(_ m: ChatMessage) -> Bool {
        guard m.role == .assistant, !m.isError, !m.isCompactBoundary, !m.isStreaming else { return false }
        guard !finalAnswers.contains(m.id) else { return false }
        return messageHasVisibleText(m) || !m.blocks.compactMap(\.toolCall).isEmpty
    }

    func flush() {
        guard !accumulator.isEmpty else { return }
        result.append(MessageGroup(id: accumulator[0].id, messages: accumulator, isTransientGroup: true))
        accumulator = []
    }

    for message in messages {
        if isCollapsibleIntermediate(message) {
            accumulator.append(message)
        } else if isInvisibleMessage(message) {
            continue
        } else {
            flush()
            result.append(MessageGroup(id: message.id, messages: [message], isTransientGroup: false))
        }
    }
    flush()
    return result
}

// MARK: - Shared Helper

/// Returns the start index of the last consecutive non-error assistant sequence.
/// Used to distinguish the settled (previous) / active (streaming) boundary.
private func streamingBoundaryIndex(in messages: [ChatMessage]) -> Int {
    var idx = messages.count - 1
    while idx >= 0 && messages[idx].role == .assistant && !messages[idx].isError {
        idx -= 1
    }
    return idx + 1
}

// MARK: - Streaming Message (isolated view — chatBridge.messages dependency confined to this view)

struct StreamingMessageView: View {
    @Environment(ChatBridge.self) private var chatBridge
    @Environment(WindowState.self) private var windowState
    var onStructureChanged: () -> Void

    var body: some View {
        let messages = chatBridge.messages
        let activeMessages = activeResponseMessages(from: messages)
        let (settledActive, streamingActive) = partitionByStreaming(activeMessages)
        Group {
            if !activeMessages.isEmpty {

                if !streamingActive.isEmpty {
                    // Collapse completed transient tool calls (even a single one) the moment
                    // the next streaming message begins, so only the current message stays visible.
                    let groups = groupMessages(settledActive, minGroupSize: 1)
                    ForEach(groups) { group in
                        if group.isTransientGroup {
                            TransientGroupSummaryView(messages: group.messages)
                                .id(group.id)
                        } else if let message = group.messages.first {
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                } else {
                    // Nothing streaming yet — show each settled message individually.
                    ForEach(settledActive, id: \.id) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }

                ForEach(streamingActive, id: \.id) { message in
                    MessageBubble(message: message)
                        .id(message.id)
                }
            }
        }
        .onChange(of: messages.count) { _, _ in
            onStructureChanged()
        }
    }

    /// Returns the last consecutive assistant sequence (including streaming turn) while streaming.
    /// Returns an empty array when not streaming so StreamingMessageView renders nothing.
    private func activeResponseMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        guard messages.last?.isStreaming == true else { return [] }
        return Array(messages[streamingBoundaryIndex(in: messages)...])
    }
}

// MARK: - Activity Item

/// A single item in the activity summary list — either a tool call or a thinking block.
enum ActivityItem: Identifiable {
    case toolCall(ToolCall)
    case thinking(id: String, text: String, duration: TimeInterval?)

    var id: String {
        switch self {
        case .toolCall(let tc): return tc.id
        case .thinking(let blockId, _, _): return blockId
        }
    }
}

func activityItems(from messages: [ChatMessage]) -> [ActivityItem] {
    messages.flatMap { msg in
        msg.blocks.compactMap { block -> ActivityItem? in
            if let tc = block.toolCall { return .toolCall(tc) }
            if let t = block.thinking, !t.isEmpty {
                return .thinking(id: block.id, text: t, duration: block.thinkingDuration)
            }
            return nil
        }
    }
}

// MARK: - Plain Activity Row

/// Card-free row for the activity summary list. The row is plain text with a
/// hover highlight; clicking expands an inline scrollable content card.
struct PlainActivityRow: View {
    let item: ActivityItem
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var isContentExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            rowHeader
            if isExpanded {
                rowContent.padding(.leading, 20)
            }
        }
    }

    // MARK: Header

    private var rowHeader: some View {
        HStack(spacing: 6) {
            rowIcon
                .font(.system(size: ClaudeTheme.messageSize(11)))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .frame(width: 14, alignment: .leading)
            rowLabel
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            isHovered ? ClaudeTheme.surfacePrimary.opacity(0.5) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }
    }

    @ViewBuilder
    private var rowIcon: some View {
        if isHovered {
            Image(systemName: isExpanded ? "minus" : "plus")
        } else if case .thinking = item {
            Image(systemName: "brain")
        } else if case .toolCall(let tc) = item {
            Image(systemName: symbol(for: tc.name.lowercased()))
        }
    }

    @ViewBuilder
    private var rowLabel: some View {
        if case .thinking(_, let text, _) = item {
            Text("Thinking")
                .font(.system(size: ClaudeTheme.messageSize(12), weight: .medium))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .layoutPriority(1)
            Text(text.prefix(100).replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: ClaudeTheme.messageSize(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if case .toolCall(let tc) = item {
            Text(label(for: tc))
                .font(.system(size: ClaudeTheme.messageSize(12)))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: Expanded content

    @ViewBuilder
    private var rowContent: some View {
        if case .thinking(_, let text, _) = item {
            Text(text)
                .font(.system(size: ClaudeTheme.messageSize(12)))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if case .toolCall(let tc) = item {
            toolContent(tc)
        }
    }

    @ViewBuilder
    private func toolContent(_ tc: ToolCall) -> some View {
        let lower = tc.name.lowercased()
        if lower == "bash", let cmd = tc.input["command"]?.stringValue {
            bashCard(cmd: cmd, result: tc.result, isError: tc.isError)
        } else if (lower == "edit" || lower == "multiedit" || lower == "multi_edit"),
                  let old = tc.input["old_string"]?.stringValue,
                  let new = tc.input["new_string"]?.stringValue {
            diffCard(old: old, new: new)
        } else if let result = tc.result, !result.isEmpty {
            resultCard(result)
        }
    }

    // MARK: Cards

    private func bashCard(cmd: String, result: String?, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text("$")
                    .font(.system(size: ClaudeTheme.messageSize(12), weight: .bold, design: .monospaced))
                    .foregroundStyle(ClaudeTheme.accent)
                Text(cmd)
                    .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let r = result, !r.isEmpty {
                ScrollView {
                    Text(r)
                        .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
                        .foregroundStyle(isError ? ClaudeTheme.statusError : ClaudeTheme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudeTheme.codeBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private func resultCard(_ result: String) -> some View {
        // The Read tool's result already arrives in `cat -n` format (line numbers
        // baked in), so we render the raw text in a scrollable monospace card
        // rather than adding a second column of numbers.
        ScrollView {
            Text(result)
                .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding(10)
        .background(ClaudeTheme.codeBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private func diffCard(old: String, new: String) -> some View {
        let removedLines = old.components(separatedBy: .newlines).map { ("-", $0, false) }
        let addedLines = new.components(separatedBy: .newlines).map { ("+", $0, true) }
        let allLines = removedLines + addedLines
        let threshold = 14
        let visible = isContentExpanded ? allLines : Array(allLines.prefix(threshold))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, triple in
                let (pfx, txt, isAdded) = triple
                Text(pfx + " " + txt)
                    .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
                    .foregroundStyle(isAdded ? ClaudeTheme.statusSuccess : ClaudeTheme.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background((isAdded ? ClaudeTheme.statusSuccess : ClaudeTheme.statusError).opacity(0.06))
            }
            if allLines.count > threshold {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isContentExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(isContentExpanded ? "Show less" : "Show more", bundle: .module)
                        Image(systemName: isContentExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: ClaudeTheme.messageSize(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .background(ClaudeTheme.codeBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Label / symbol helpers

    private func label(for tc: ToolCall) -> String {
        let lower = tc.name.lowercased()
        switch lower {
        case "read":
            let name = tc.input["file_path"]?.stringValue.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            if let result = tc.result {
                let lineCount = result.components(separatedBy: .newlines).count
                return name.isEmpty ? "Read \(lineCount) lines" : "Read \(lineCount) lines — \(name)"
            }
            return name.isEmpty ? "Read" : "Read — \(name)"
        case "bash":
            if let cmd = tc.input["command"]?.stringValue {
                let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                return String(trimmed.prefix(70))
            }
            return "Run command"
        case "edit", "multiedit", "multi_edit":
            if let path = tc.input["file_path"]?.stringValue {
                return "Edit — \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "Edit"
        case "write":
            if let path = tc.input["file_path"]?.stringValue {
                return "Write — \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "Write"
        case "grep":
            if let pat = tc.input["pattern"]?.stringValue { return "grep — \(pat.prefix(50))" }
            return "Search"
        case "glob":
            if let pat = tc.input["pattern"]?.stringValue ?? tc.input["path"]?.stringValue {
                return "Find — \(pat.prefix(50))"
            }
            return "Find files"
        case "agent":
            return tc.input["description"]?.stringValue ?? "Agent"
        default:
            return tc.name
        }
    }

    private func symbol(for lower: String) -> String {
        switch lower {
        case "read":                             return "doc.text"
        case "bash":                             return "terminal"
        case "edit", "multiedit", "multi_edit":  return "pencil"
        case "write":                            return "square.and.pencil"
        case "grep", "glob":                     return "magnifyingglass"
        case "agent":                            return "cpu"
        default:                                 return "wrench"
        }
    }
}

// MARK: - Transient Group Summary

struct TransientGroupSummaryView: View {
    let messages: [ChatMessage]
    @State private var isExpanded = false

    private var toolCallCount: Int {
        messages.reduce(0) { $0 + $1.blocks.compactMap(\.toolCall).count }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: ClaudeTheme.size(11)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                        Text(String(format: String(localized: "%lld tools executed", bundle: .module), toolCallCount))
                            .font(.system(size: ClaudeTheme.size(12)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: ClaudeTheme.size(9)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    let items = activityItems(from: messages)
                    ForEach(items) { item in
                        PlainActivityRow(item: item)
                    }
                }
            }
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Turn Activity Summary (settled turns — collapsed by default)

/// Collapses a completed turn's intermediate activity into a single header
/// ("N tool calls · M messages"). Collapsed by default so the final answer is
/// what you read; expand to see each tool call and thinking block.
struct TurnActivitySummaryView: View {
    let messages: [ChatMessage]
    @State private var isExpanded = false

    private var toolCallCount: Int {
        messages.reduce(0) { $0 + $1.blocks.compactMap(\.toolCall).count }
    }

    private var summaryLabel: String {
        let tools = String(format: String(localized: "%lld tool calls", bundle: .module), toolCallCount)
        let msgs = String(format: String(localized: "%lld messages", bundle: .module), messages.count)
        return "\(tools) · \(msgs)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: ClaudeTheme.size(9), weight: .semibold))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                        Text(summaryLabel)
                            .font(.system(size: ClaudeTheme.size(12)))
                            .foregroundStyle(ClaudeTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    let items = activityItems(from: messages)
                    ForEach(items) { item in
                        PlainActivityRow(item: item)
                    }
                }
            }
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Empty Session

struct EmptySessionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: ClaudeTheme.size(36)))
                .foregroundStyle(ClaudeTheme.textTertiary)

            Text("How can I help you?", bundle: .module)
                .font(.system(size: ClaudeTheme.size(18), weight: .medium))
                .foregroundStyle(ClaudeTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicatorView: View {
    let isThinking: Bool
    var startDate: Date?

    var body: some View {
        HStack(spacing: 8) {
            PulseRingView()
                .id("pulse")

            Group {
                if isThinking {
                    Text("Thinking...", bundle: .module)
                } else {
                    Text("Generating response...", bundle: .module)
                }
            }
            .font(.system(size: ClaudeTheme.size(13)))
            .foregroundStyle(ClaudeTheme.textSecondary)

            Spacer()

            if let startDate {
                ElapsedTimeView(startDate: startDate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ClaudeTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium))
    }
}

// MARK: - Elapsed Time

struct ElapsedTimeView: View {
    let startDate: Date
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(elapsed.formattedDuration)
            .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
            .foregroundStyle(ClaudeTheme.textTertiary)
            .onAppear {
                elapsed = Date().timeIntervalSince(startDate)
            }
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(startDate)
            }
    }
}
