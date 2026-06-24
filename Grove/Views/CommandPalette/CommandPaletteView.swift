import SwiftUI
import GroveCore

/// ⌘K command palette: a centered overlay with a search field that fuzzy-filters
/// across workspaces, chats, projects, and a few actions (New workspace, Settings).
/// Arrow keys move the selection, Enter runs it, Esc dismisses. Mounted via a single
/// `.overlay` in `MainView`.
struct CommandPaletteView: View {
    @Binding var isPresented: Bool

    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var showNewWorkspace = false
    @FocusState private var fieldFocused: Bool

    private let maxResults = 8

    var body: some View {
        ZStack {
            if isPresented {
                backdrop
                panel
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isPresented)
        .onChange(of: isPresented) { _, presenting in
            if presenting {
                query = ""
                selectedIndex = 0
                DispatchQueue.main.async { fieldFocused = true }
            }
        }
        .sheet(isPresented: $showNewWorkspace) {
            NewWorkspaceSheet(preselectedProject: windowState.selectedProject)
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        Color.black.opacity(0.25)
            .ignoresSafeArea()
            .onTapGesture { dismiss() }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(ClaudeTheme.borderSubtle)
            results
        }
        .frame(width: 560)
        .background(ClaudeTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusMedium)
                .stroke(ClaudeTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 24, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 120)
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { runSelected(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: ClaudeTheme.size(15)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            TextField("Search workspaces, chats, projects…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: ClaudeTheme.size(16)))
                .foregroundStyle(ClaudeTheme.textPrimary)
                .focused($fieldFocused)
                .onChange(of: query) { _, _ in selectedIndex = 0 }
                .onSubmit { runSelected() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var results: some View {
        let items = filteredItems
        return Group {
            if items.isEmpty {
                Text("No matches")
                    .font(.system(size: ClaudeTheme.size(13)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == selectedIndex)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedIndex = index
                                        runSelected()
                                    }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selectedIndex) { _, idx in
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(idx, anchor: .center) }
                    }
                }
            }
        }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: ClaudeTheme.size(14)))
                .foregroundStyle(selected ? ClaudeTheme.accent : ClaudeTheme.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: ClaudeTheme.size(14)))
                    .foregroundStyle(ClaudeTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(item.kind.label)
                .font(.system(size: ClaudeTheme.size(10), weight: .medium))
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? ClaudeTheme.accentSubtle : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
        .padding(.horizontal, 8)
    }

    // MARK: - Navigation

    private func move(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func runSelected() {
        let items = filteredItems
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        dismiss()
        item.run()
    }

    private func dismiss() {
        fieldFocused = false
        isPresented = false
    }

    // MARK: - Items

    private var filteredItems: [PaletteItem] {
        let all = buildItems()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return Array(all.prefix(maxResults))
        }
        let scored = all.compactMap { item -> (PaletteItem, Int)? in
            guard let score = FuzzyMatch.score(query: trimmed, in: item.haystack) else { return nil }
            return (item, score)
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(maxResults)
            .map(\.0)
    }

    private func buildItems() -> [PaletteItem] {
        var items: [PaletteItem] = []

        // Actions
        items.append(PaletteItem(
            id: "action.new-workspace",
            kind: .action,
            title: "New workspace",
            subtitle: "Create an isolated git worktree",
            icon: "plus.rectangle.on.folder",
            run: { showNewWorkspace = true }
        ))
        items.append(PaletteItem(
            id: "action.settings",
            kind: .action,
            title: "Settings",
            subtitle: nil,
            icon: "gearshape",
            run: { openSettings() }
        ))

        // Workspaces
        for ws in appState.workspaces {
            let projectName = appState.projects.first { $0.id == ws.projectId }?.name
            items.append(PaletteItem(
                id: "workspace.\(ws.id.uuidString)",
                kind: .workspace,
                title: ws.displayName,
                subtitle: projectName,
                icon: "rectangle.split.2x1",
                run: { appState.selectWorkspace(ws, in: windowState) }
            ))
        }

        // Chats
        for summary in appState.allSessionSummaries {
            let projectName = appState.projects.first { $0.id == summary.projectId }?.name
            items.append(PaletteItem(
                id: "chat.\(summary.id)",
                kind: .chat,
                title: summary.title,
                subtitle: projectName,
                icon: "bubble.left.and.bubble.right",
                run: { appState.selectSession(id: summary.id, in: windowState) }
            ))
        }

        // Projects
        for project in appState.projects {
            items.append(PaletteItem(
                id: "project.\(project.id.uuidString)",
                kind: .project,
                title: project.name,
                subtitle: project.path,
                icon: "folder",
                run: { appState.selectProject(project, in: windowState) }
            ))
        }

        return items
    }
}

// MARK: - PaletteItem

private struct PaletteItem: Identifiable {
    enum Kind {
        case workspace, chat, project, action

        var label: String {
            switch self {
            case .workspace: "Workspace"
            case .chat: "Chat"
            case .project: "Project"
            case .action: "Action"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let icon: String
    let run: () -> Void

    /// Combined text the fuzzy matcher searches over.
    var haystack: String {
        if let subtitle { return "\(title) \(subtitle)" }
        return title
    }
}

// MARK: - FuzzyMatch

/// Subsequence fuzzy matcher: every character of `query` must appear in order in
/// the candidate. Rewards consecutive runs and matches at word boundaries so the
/// most relevant results sort to the top.
enum FuzzyMatch {
    static func score(query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return 0 }
        guard q.count <= c.count else { return nil }

        var score = 0
        var qi = 0
        var prevMatch = -2
        for (ci, ch) in c.enumerated() {
            guard qi < q.count, ch == q[qi] else { continue }
            score += 1
            if ci == prevMatch + 1 { score += 5 }          // consecutive run
            if ci == 0 || c[ci - 1] == " " || c[ci - 1] == "/" { score += 3 } // word start
            prevMatch = ci
            qi += 1
            if qi == q.count { break }
        }
        return qi == q.count ? score : nil
    }
}
