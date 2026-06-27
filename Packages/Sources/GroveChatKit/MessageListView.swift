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

    private let foldThreshold = 30

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Show all messages with a scroll icon divider at the threshold
                if settledItems.count > foldThreshold {
                    let hiddenCount = settledItems.count - foldThreshold
                    messageRows(settledItems.prefix(hiddenCount))
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                        .foregroundStyle(ClaudeTheme.textTertiary.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
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
        let activeMessages = activeResponseMessages(from: messages)
        Group {
            if !activeMessages.isEmpty {
                // Render the in-flight turn incrementally — each step (thinking,
                // tool, text) appears as it streams in — and keep a running timer
                // pinned at the bottom so progress is always visible.
                ForEach(activeMessages, id: \.id) { message in
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
    let item: ActivityItem
    var isMessageStreaming: Bool = false
    @State private var isExpanded = false
    @State private var isContentExpanded = false

    /// The subagent run behind an Agent/Task tool call, if its steps were recorded.
    private var subagentRun: SubagentRun? {
        guard case .toolCall(let tc) = item,
              ["agent", "task"].contains(tc.name.lowercased()) else { return nil }
        return chatBridge.subagentRuns[tc.id]
    }

    /// A one-line greyish preview of a thinking block, shown next to "Thinking".
    private var thinkingPreview: String? {
        guard case .thinking(_, let text, _) = item else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let firstLine = t.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? t
        return firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Marker header — tap to expand when there's detail to show
            ChatMarker(
                icon: markerIcon,
                isRunning: isRunning,
                label: markerLabel,
                // Hide the preview once expanded — the full text shows below, so
                // keeping the pill would just repeat the opening line.
                preview: isExpanded ? nil : thinkingPreview,
                expandable: hasExpandableContent,
                isExpanded: isExpanded
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasExpandableContent else { return }
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }

            if isExpanded {
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

    private func runningLabel(for tc: ToolCall) -> String {
        let lower = tc.name.lowercased()
        switch lower {
        case "read":    return "Reading..."
        case "bash":    return "Running..."
        case "edit", "multiedit", "multi_edit": return "Editing..."
        case "write":   return "Writing..."
        case "grep":    return "Searching..."
        case "glob":    return "Finding files..."
        case "agent":   return "Spawning agent..."
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

