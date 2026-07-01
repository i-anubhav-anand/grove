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
    @State private var isSessionReady = false
    /// The chat column width, injected by the host layout (MainView). It's derived
    /// purely from window geometry (window − inspector − sidebar), so it never depends
    /// on message content — the single, feedback-free source of truth for every width
    /// cap in the chat. `.infinity` only until the host provides a value.
    @Environment(\.chatColumnMaxWidth) private var chatColumnMaxWidth

    /// Cap each message bubble (query + response) at 75% of the chat column.
    private var bubbleMaxWidth: CGFloat {
        chatColumnMaxWidth < .infinity ? max(0, chatColumnMaxWidth - 40) * 0.75 : .infinity
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                messageRows(settledItems[...])
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Streaming view is outside VStack — text deltas don't affect settled layout
            VStack(spacing: 16) {
                if !windowState.focusMode {
                    StreamingMessageView(onContentGrew: {
                        // Follow the answer as it streams, but only while pinned.
                        if isNearBottom { scrollToBottomDebounced() }
                    }) {
                        rebuildSettledItems()
                        if isNearBottom { scrollToBottomDebounced() }
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
        .overlay(alignment: .bottomTrailing) {
            if !isNearBottom && isSessionReady {
                scrollToBottomButton
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isNearBottom)
        .environment(\.bubbleMaxWidth, bubbleMaxWidth)
    }

    // MARK: - Scroll To Bottom

    private var scrollToBottomButton: some View {
        Button {
            isNearBottom = true
            scrollPosition.scrollTo(edge: .bottom)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: ClaudeTheme.size(13), weight: .semibold))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(ClaudeTheme.border, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help("Scroll to bottom")
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

fileprivate struct MessageGroup: Identifiable {
    let id: UUID
    let messages: [ChatMessage]
    let isTransientGroup: Bool
}

/// Returns true if the message has no renderable content — all tool calls were removed
/// (e.g. empty bash output stripped by setToolResult) and there is no text.
fileprivate func isInvisibleMessage(_ message: ChatMessage) -> Bool {
    guard message.role == .assistant, !message.isError, !message.isCompactBoundary, !message.isStreaming else { return false }
    return message.blocks.isEmpty
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
        let hasThinking = m.blocks.contains { $0.isThinking }
        return messageHasVisibleText(m) || !m.blocks.compactMap(\.toolCall).isEmpty || hasThinking
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
    var onContentGrew: () -> Void = {}
    var onStructureChanged: () -> Void

    /// Cheap proxy for "the streaming answer grew" — its text length plus block
    /// count. Drives scroll-follow without rebuilding the settled list per token.
    private var streamingContentLength: Int {
        guard let last = chatBridge.messages.last, last.isStreaming else { return 0 }
        return last.content.count + last.blocks.count
    }

    var body: some View {
        let messages = chatBridge.messages
        let display = completedTurnMessages(from: messages)
        Group {
            if chatBridge.isStreaming {
                // Don't render the in-progress step in real time. Show each step
                // only once it's complete (it "pops up" done), and keep a running
                // timer pinned below so progress is always visible.
                ForEach(display, id: \.id) { message in
                    MessageBubble(message: message)
                        .id(message.id)
                }
                RunningIndicator()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .onChange(of: messages.count) { _, _ in
            onStructureChanged()
        }
        .onChange(of: streamingContentLength) { _, _ in
            onContentGrew()
        }
    }

    /// Returns the last consecutive assistant sequence (including streaming turn) while streaming.
    /// Returns an empty array when not streaming so StreamingMessageView renders nothing.
    private func activeResponseMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        guard messages.last?.isStreaming == true else { return [] }
        return Array(messages[streamingBoundaryIndex(in: messages)...])
    }

    /// The in-flight turn with only *completed* steps. The trailing block of the
    /// streaming message (the one being generated right now) is dropped so nothing
    /// renders token-by-token — each step appears only once it's done.
    private func completedTurnMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        var active = activeResponseMessages(from: messages)
        guard let lastIdx = active.indices.last else { return [] }

        var last = active[lastIdx]
        if last.isStreaming, let tail = last.blocks.last {
            let tailInProgress: Bool
            if let tc = tail.toolCall {
                tailInProgress = tc.result == nil && !tc.isError   // tool still running
            } else {
                tailInProgress = true                              // text/thinking being written
            }
            if tailInProgress { last.blocks.removeLast() }
        }
        last.isStreaming = false   // render the kept blocks as finished (no cursor)
        active[lastIdx] = last
        return active.filter { !$0.blocks.isEmpty }
    }
}

// MARK: - Running Indicator

/// Compact "session is running" indicator shown at the bottom while a turn is in
/// flight. Reuses ChatMarker's shimmer (the same shading used for thinking) and
/// shows live elapsed time.
struct RunningIndicator: View {
    @Environment(ChatBridge.self) private var chatBridge
    @State private var now = Date()
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ChatMarker(isRunning: true, label: elapsedLabel)
            .onReceive(ticker) { now = $0 }
    }

    private var elapsedLabel: String {
        guard let start = chatBridge.streamingStartDate else { return "Running" }
        let t = max(0, now.timeIntervalSince(start))
        let minutes = Int(t) / 60
        let seconds = t - Double(minutes * 60)
        return minutes > 0
            ? String(format: "%dm, %.1fs", minutes, seconds)
            : String(format: "%.1fs", seconds)
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
    @Environment(ChatBridge.self) private var chatBridge
    @Environment(WindowState.self) private var windowState
    let item: ActivityItem
    var isMessageStreaming: Bool = false
    /// External accordion binding. When set, this row's expand/collapse is controlled
    /// by the parent so only one item can be open at a time.
    var expandedOverride: Binding<Bool>? = nil
    @State private var isExpanded = false

    private var effectiveExpanded: Bool { expandedOverride?.wrappedValue ?? isExpanded }
    private func setExpanded(_ value: Bool) {
        if let b = expandedOverride { b.wrappedValue = value } else { isExpanded = value }
    }

    /// An edit/write tool call rendered as a rich file row (chip + diff + hover).
    private var fileEdit: FileEdit? {
        guard case .toolCall(let tc) = item else { return nil }
        return FileEdit(toolCall: tc)
    }

    /// The subagent run behind an Agent/Task tool call, if its steps were recorded.
    private var subagentRun: SubagentRun? {
        guard case .toolCall(let tc) = item,
              ["agent", "task"].contains(tc.name.lowercased()) else { return nil }
        return chatBridge.subagentRuns[tc.id]
    }

    /// One-line greyish preview shown next to the marker label.
    /// For thinking blocks: first line of the thought.
    /// For agent/task tool calls: the description field.
    private var markerPreview: String? {
        switch item {
        case .thinking(_, let text, _):
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            let firstLine = t.split(separator: "\n").first.map(String.init) ?? t
            let limit = 72
            return firstLine.count > limit ? String(firstLine.prefix(limit)) + "…" : firstLine
        case .toolCall(let tc) where ["agent", "task"].contains(tc.name.lowercased()):
            // Tools use varying field names; fall back through common options
            // and finally the subagent run's meta description.
            let raw = tc.input["description"]?.stringValue
                ?? tc.input["prompt"]?.stringValue
                ?? tc.input["task"]?.stringValue
                ?? subagentRun?.description
            guard let raw else { return nil }
            // Strip leading "ActionWord: " prefix (e.g. "Hunt: ", "Explore: ")
            let stripped = raw.replacing(#/^\w+:\s*/#, with: "")
            return stripped.isEmpty ? raw : stripped
        default:
            return nil
        }
    }

    var body: some View {
        if let edit = fileEdit {
            // Edits render as rich file rows (chip + diff stats + hover preview)
            // everywhere — including the settled-turn dropdown, not just live.
            ChangedFileRow(edit: edit) {
                windowState.diffFile = PreviewFile(path: edit.path, name: edit.name, editHunks: edit.hunks)
            }
        } else {
            markerBody
        }
    }

    private var markerBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Marker header — tap to expand when there's detail to show
            ChatMarker(
                icon: markerIcon,
                isRunning: isRunning,
                label: markerLabel,
                // Hide the preview once expanded — the full content shows below.
                preview: effectiveExpanded ? nil : markerPreview,
                expandable: hasExpandableContent,
                isExpanded: effectiveExpanded
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasExpandableContent else { return }
                withAnimation(.easeInOut(duration: 0.15)) { setExpanded(!effectiveExpanded) }
            }

            if effectiveExpanded {
                rowContent
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: Marker props

    private var isRunning: Bool {
        switch item {
        case .thinking: return isMessageStreaming
        case .toolCall(let tc): return tc.result == nil && isMessageStreaming
        }
    }

    private var markerIcon: String? {
        guard !isRunning else { return nil }
        switch item {
        case .thinking: return "brain"
        case .toolCall(let tc): return symbol(for: tc.name.lowercased())
        }
    }

    private var markerLabel: String {
        switch item {
        case .thinking: return isRunning ? "Thinking..." : "Thinking"
        case .toolCall(let tc):
            let base = isRunning ? runningLabel(for: tc) : label(for: tc)
            if let run = subagentRun, !run.steps.isEmpty {
                return "\(base) · \(run.steps.count) steps"
            }
            return base
        }
    }

    private var hasExpandableContent: Bool {
        if subagentRun != nil { return true }
        switch item {
        case .thinking(_, let text, _): return !text.isEmpty
        case .toolCall(let tc): return tc.result != nil || tc.input["command"] != nil
        }
    }

    // MARK: Expanded content

    @ViewBuilder
    private var rowContent: some View {
        if let run = subagentRun {
            AgentStepsView(run: run)
        } else if case .thinking(_, let text, _) = item {
            ScrollView {
                MarkdownContentView(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
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
            DiffViewerCard(filePath: tc.input["file_path"]?.stringValue, old: old, new: new)
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

    // MARK: Label / symbol helpers

    private func runningLabel(for tc: ToolCall) -> String {
        let lower = tc.name.lowercased()
        switch lower {
        case "read":    return "Reading..."
        case "bash":    return "Running..."
        case "edit", "multiedit", "multi_edit": return "Editing..."
        case "write":   return "Writing..."
        case "grep":    return "Searching..."
        case "glob":    return "Finding files..."
        case "agent", "task": return "Spawning agent..."
        default:        return "\(tc.name)..."
        }
    }

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
        case "agent", "task":
            return "Agent"
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
        case "agent", "task":                    return "cpu"
        default:                                 return "wrench"
        }
    }
}

// MARK: - Turn Activity Summary (settled turns — collapsed by default)

/// Collapses a completed turn's intermediate activity into a single header
/// ("N tool calls · M messages"). Collapsed by default so the final answer is
/// what you read; expand to see each tool call and thinking block in a
/// chain-of-thought timeline.
struct TurnActivitySummaryView: View {
    let messages: [ChatMessage]
    @State private var isExpanded = false
    @State private var expandedIds: Set<String> = []

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
            VStack(alignment: .leading, spacing: 0) {
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
                .padding(.bottom, isExpanded ? 10 : 0)

                if isExpanded {
                    let items = activityItems(from: messages)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            ChainStepRow(item: item, isLast: idx == items.count - 1, expandedIds: $expandedIds)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .containerRelativeFrame(.horizontal) { w, _ in w * 0.75 }
    }
}

// MARK: - Chain Step Row

/// One step in the settled-turn chain-of-thought timeline. Wraps PlainActivityRow
/// with a left rail (dot + connecting line) so expanded steps read like a timeline.
private struct ChainStepRow: View {
    let item: ActivityItem
    let isLast: Bool
    @Binding var expandedIds: Set<String>

    private var itemExpandedBinding: Binding<Bool> {
        Binding(
            get: { expandedIds.contains(item.id) },
            set: { newVal in
                if newVal { expandedIds.insert(item.id) } else { expandedIds.remove(item.id) }
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
                .frame(width: 14, alignment: .center)

            PlainActivityRow(item: item, expandedOverride: itemExpandedBinding)
                .padding(.bottom, isLast ? 0 : 4)
        }
        // fixedSize prevents the parent (containerRelativeFrame / ScrollView)
        // from proposing infinite height to this row and inflating it.
        .fixedSize(horizontal: false, vertical: true)
        // Connector in overlay so it doesn't contribute to layout height.
        .overlay(alignment: .topLeading) {
            if !isLast {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 16) // 6pt top pad + 6pt dot + 4pt gap
                    Rectangle()
                        .fill(ClaudeTheme.border)
                        .frame(width: 1)
                }
                .frame(width: 14)
            }
        }
    }

    private var dotColor: Color {
        switch item {
        case .thinking:
            return ClaudeTheme.accent.opacity(0.75)
        case .toolCall(let tc):
            switch tc.name.lowercased() {
            case "bash":
                return ClaudeTheme.statusSuccess
            case "edit", "write", "multiedit", "multi_edit":
                return ClaudeTheme.statusWarning
            case "read", "grep", "glob":
                return ClaudeTheme.textSecondary
            default:
                return ClaudeTheme.textTertiary
            }
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

