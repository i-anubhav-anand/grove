import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GroveCore
import GroveChatKit

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @State private var showGitHubSheet = false
    @State private var showFilePicker = false
    @Environment(\.openSettings) private var openSettings
    @State private var sidebarTab: SidebarTab = .history
    @State private var fileSearchTrigger = false
    @State private var inspectorStarted = true
    @AppStorage("inspectorPanelWidth") private var inspectorWidth: Double = 400
    @State private var resizeBaseWidth: Double? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showCommandPalette = false

    enum SidebarTab: String, CaseIterable {
        case history = "History"
        case files = "Files"

        var icon: String {
            switch self {
            case .files: "folder"
            case .history: "clock"
            }
        }
    }

    var body: some View {
        if !appState.onboardingCompleted {
            OnboardingView()
        } else {
            GeometryReader { geo in
            // Inspector floor = the default width (never shrink below it); ceiling = 25% of the
            // window so the chat keeps ≥75%. On narrow windows where 25% < default, the default wins.
            let maxInspector = max(400, geo.size.width * 0.25)
            HStack(spacing: 0) {
            HSplitView {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebarContent
                } detail: {
                    detailContent
                }
                .background {
                    Button("") {
                        columnVisibility = (columnVisibility == .all) ? .detailOnly : .all
                    }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                }
                .overlay {
                    if windowState.showMarketplace {
                        ZStack {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        windowState.showMarketplace = false
                                    }
                                }
                            SkillMarketView()
                                .focusable(false)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .id(appState.themeRevision)
                .onChange(of: windowState.showInspector) { _, isShowing in
                    if isShowing, !inspectorStarted { inspectorStarted = true }
                }
                .onChange(of: appState.focusMode) { _, newValue in
                    windowState.focusMode = newValue
                }
                .onAppear {
                    windowState.focusMode = appState.focusMode
                }
                .navigationTitle({
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    return "Grove(\(appVersion))"
                }())
                .toolbar {
                    if columnVisibility != .detailOnly {
                        ToolbarItemGroup(placement: .confirmationAction) {
                            Menu {
                                Button {
                                    showFilePicker = true
                                } label: {
                                    Label("Open project", systemImage: "folder")
                                }
                                Button {
                                    showGitHubSheet = true
                                } label: {
                                    Label("Open GitHub project", systemImage: "globe")
                                }
                                Divider()
                                Button {
                                    quickStart()
                                } label: {
                                    Label("Quick start", systemImage: "plus.square.on.square")
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: ClaudeTheme.size(16)))
                                    .foregroundStyle(ClaudeTheme.textSecondary)
                            }
                            .menuIndicator(.hidden)
                            .help("New project")
                            .fileImporter(
                                isPresented: $showFilePicker,
                                allowedContentTypes: [.folder],
                                allowsMultipleSelection: false
                            ) { result in
                                handleFolderSelection(result)
                            }
                        }
                    }
                }
                .layoutPriority(1)
            }
            .overlay {
                CommandPaletteView(isPresented: $showCommandPalette)
                    .background {
                        Button("") { showCommandPalette.toggle() }
                            .keyboardShortcut("k", modifiers: .command)
                            .hidden()
                    }
            }

            if inspectorStarted && windowState.showInspector {
                Rectangle()
                    .fill(ClaudeTheme.border)
                    .frame(width: 1)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                // Anchor to the width at drag start so movement tracks the cursor 1:1.
                                // (Reading + writing inspectorWidth with absolute translation made it accelerate.)
                                let base = resizeBaseWidth ?? inspectorWidth
                                if resizeBaseWidth == nil { resizeBaseWidth = base }
                                inspectorWidth = min(max(base - value.translation.width, 400), maxInspector)
                            }
                            .onEnded { _ in resizeBaseWidth = nil }
                    )
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }

                InspectorPanel()
                    .frame(width: min(max(CGFloat(inspectorWidth), 400), maxInspector))
                    .id(appState.themeRevision)
            }
            } // HStack
            } // GeometryReader
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Left pane is the workspace/session list. The file tree now lives in
            // the right panel's "Files" tab.
            WorkspaceListView()

            ClaudeThemeDivider()

            if let project = windowState.selectedProject {
                GitStatusView(projectPath: project.path)
            }
        }
        .background(ClaudeTheme.sidebarBackground)
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        .sheet(isPresented: $showGitHubSheet) {
            GitHubSheet()
        }
    }

    @Environment(\.openWindow) private var openWindow

    // MARK: - Detail

    private var detailContent: some View {
        Group {
            if windowState.selectedProject != nil {
                VStack(spacing: 0) {
                    ChatView {
                        ChatToolbarControls(placement: .composer)
                    }
                }
                .modifier(ChatDetailModifiers())
            } else if !windowState.isInitialized {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ClaudeTheme.background)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sparkle")
                        .font(.system(size: ClaudeTheme.size(48)))
                        .foregroundStyle(ClaudeTheme.accent)

                    Text("Select a Project")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ClaudeTheme.textPrimary)

                    Text("Select a project from the sidebar or add a new one.")
                        .font(.subheadline)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ClaudeTheme.background)
            }
        }
        .sheet(item: Bindable(windowState).inspectorFile) { file in
            FileInspectorView(filePath: file.path, fileName: file.name)
                .frame(minWidth: 1000, idealWidth: 1400, maxWidth: 1920,
                       minHeight: 600, idealHeight: 1000, maxHeight: 1200)
        }
        .sheet(item: Bindable(windowState).diffFile) { file in
            FileDiffView(filePath: file.path, fileName: file.name, editHunks: file.editHunks)
                .frame(minWidth: 1000, idealWidth: 1400, maxWidth: 1920,
                       minHeight: 600, idealHeight: 1000, maxHeight: 1200)
        }
        .alert("Error", isPresented: Bindable(windowState).showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(windowState.errorMessage ?? ""))
        }
        .focusedValue(\.startNewChat) {
            appState.startNewChat(in: windowState)
        }
        // Toolbar is in an isolated struct so NSToolbar does not re-layout on project switches.
        .background {
            DetailToolbar()
        }
    }

    // MARK: - Folder Selection

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        Task { await appState.addProjectFromFolder(url, in: windowState) }
    }

    /// Quick start: pick a location + name, create the folder, `git init` it, and
    /// add it as a project — a fresh local repo ready for an agent.
    private func quickStart() {
        let panel = NSSavePanel()
        panel.title = "Quick start — new project"
        panel.prompt = "Create"
        panel.nameFieldLabel = "Project name:"
        panel.nameFieldStringValue = "new-project"
        panel.canCreateDirectories = true
        try? FileManager.default.createDirectory(at: GroveHome.repos, withIntermediateDirectories: true)
        panel.directoryURL = GroveHome.repos
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                await Self.gitInit(at: url)
                await appState.addProjectFromFolder(url, in: windowState)
            } catch {
                windowState.errorMessage = "Couldn't create project: \(error.localizedDescription)"
                windowState.showError = true
            }
        }
    }

    private static func gitInit(at url: URL) async {
        await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["init"]
            proc.currentDirectoryURL = url
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
        }.value
    }
}

// MARK: - Detail Toolbar (isolated struct — no selectedProject dependency, prevents NSToolbar re-layout on project switch)

struct DetailToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .toolbar {
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        appState.startNewChat(in: windowState)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .help("New Chat")

                    Button {
                        windowState.showInspector.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help("Toggle Inspector")
                    .keyboardShortcut("4", modifiers: .command)

                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
    }
}

// MARK: - Inspector Tab Control

struct InspectorTabControl: View {
    @Binding var selection: InspectorTab
    /// Optional per-tab counts. A tab with an entry shows a `CountBadge`; absent tabs show no badge.
    var counts: [InspectorTab: Int] = [:]
    var onTabClick: (InspectorTab) -> Void = { _ in }

    var body: some View {
        // Horizontal scroll is the narrow-width fallback: labels never wrap (lineLimit + fixedSize),
        // the bar scrolls instead of compressing. The track background hugs the content so the pill
        // stays tight even when the ScrollView is given extra width.
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    let isSelected = selection == tab
                    Button {
                        selection = tab
                        onTabClick(tab)
                    } label: {
                        HStack(spacing: 5) {
                            Text(LocalizedStringKey(tab.rawValue))
                                .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            if let count = counts[tab] {
                                CountBadge(count: count, isSelected: isSelected)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .foregroundStyle(isSelected ? ClaudeTheme.textOnAccent : ClaudeTheme.textSecondary)
                        .background(
                            isSelected ? ClaudeTheme.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
        }
        .scrollIndicators(.hidden)
    }
}

/// Small count pill shown inline after a tab label (e.g. "Changes 3"). Adapts to the selected pill.
struct CountBadge: View {
    let count: Int
    var isSelected: Bool = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: ClaudeTheme.size(10), weight: .medium))
            .foregroundStyle(isSelected ? ClaudeTheme.textOnAccent : ClaudeTheme.textTertiary)
            .padding(.horizontal, 5)
            .frame(minWidth: 16)
            .background(
                isSelected ? ClaudeTheme.textOnAccent.opacity(0.2) : ClaudeTheme.surfaceTertiary,
                in: Capsule()
            )
    }
}

// MARK: - Inspector Panel

struct InspectorPanel: View {
    @Environment(WindowState.self) private var windowState
    @Environment(AppState.self) private var appState
    @State private var memoClearID: UUID? = nil
    @State private var memoFocusID: UUID? = nil
    @State private var fileSearchTrigger = false
    @State private var changedFileCount = 0
    @State private var prModel = PRReviewModel()
    @AppStorage("inspectorTerminalDockHeight") private var terminalDockHeight: Double = 260

    private func bumpFocus(for tab: InspectorTab) {
        switch tab {
        case .memo: memoFocusID = UUID()
        case .files, .changes, .checks: break
        }
    }

    private var repoFullName: String? { windowState.selectedProject?.gitHubRepo }
    private var prBranch: String? { windowState.selectedWorkspace?.branch }

    /// Working directory for the right-panel tabs: the selected workspace's
    /// worktree, falling back to the project root. The workspace is only honored
    /// when it belongs to the selected project — otherwise a stale workspace from
    /// a previously-selected project would point the panel at the wrong repo.
    private var workspaceCwd: String? {
        if let ws = windowState.selectedWorkspace,
           ws.projectId == windowState.selectedProject?.id {
            return ws.worktreePath
        }
        return windowState.selectedProject?.path
    }

    var body: some View {
        VStack(spacing: 0) {
            if let pr = prModel.pullRequest {
                PRMergeHeader(pr: pr, model: prModel)
                ClaudeThemeDivider()
            }

            HStack(spacing: 8) {
                InspectorTabControl(
                    selection: Bindable(windowState).inspectorTab,
                    counts: [.changes: changedFileCount],
                    onTabClick: { tab in bumpFocus(for: tab) }
                )

                Spacer()

                if windowState.inspectorTab == .memo {
                    InspectorIconButton(systemName: "arrow.counterclockwise", help: "Clear Memo") {
                        memoClearID = UUID()
                    }
                }

                Button {
                    windowState.showInspector = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("w", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ClaudeThemeDivider()

            Group {
                if let cwd = workspaceCwd {
                    FileTreeView(projectPath: cwd, searchTrigger: $fileSearchTrigger)
                } else {
                    Color.clear
                }
            }
            .frame(maxHeight: windowState.inspectorTab == .files ? .infinity : 0)
            .clipped()

            ChangesPaneView(worktreePath: workspaceCwd, prModel: prModel)
                .frame(maxHeight: windowState.inspectorTab == .changes ? .infinity : 0)
                .clipped()

            ChecksPaneView(
                worktreePath: windowState.selectedWorkspace?.worktreePath,
                branch: windowState.selectedWorkspace?.branch
            )
            .frame(maxHeight: windowState.inspectorTab == .checks ? .infinity : 0)
            .clipped()

            InspectorMemoPanel(projectId: windowState.selectedProject?.id,
                               clearTrigger: memoClearID,
                               focusTrigger: memoFocusID)
                .frame(maxHeight: windowState.inspectorTab == .memo ? .infinity : 0)
                .clipped()

            InspectorTerminalDock(
                cwd: workspaceCwd,
                isOpen: Bindable(windowState).terminalDockOpen,
                tab: Bindable(windowState).terminalDockTab,
                bodyHeight: $terminalDockHeight
            )
        }
        .background(ClaudeTheme.surfaceElevated)
        .clipped()
        .onChange(of: windowState.inspectorTab) { _, newTab in
            bumpFocus(for: newTab)
        }
        .onChange(of: windowState.showInspector) { _, isShowing in
            if isShowing { bumpFocus(for: windowState.inspectorTab) }
        }
        .task(id: workspaceCwd) {
            // Drives the "Changes" tab badge. Reuses ChangesPaneView's git-status helper rather than
            // duplicating the plumbing; counts porcelain lines the same way the pane does.
            guard let cwd = workspaceCwd else { changedFileCount = 0; return }
            let output = await ChangesPaneView.runGitStatus(cwd: cwd)
            changedFileCount = output.split(separator: "\n").filter { $0.count > 3 }.count
        }
        .task(id: "\(repoFullName ?? "")|\(prBranch ?? "")") {
            await prModel.reload(github: appState.github, repo: repoFullName, branch: prBranch, loggedIn: appState.isLoggedIn)
        }
    }
}

// MARK: - PR Merge Header

/// Slim "Ready to merge" strip shown above the inspector tabs when the branch has an open PR.
/// The Merge button opens the PR in the browser for now — there is no merge API yet (TODO).
struct PRMergeHeader: View {
    @Environment(\.openURL) private var openURL
    let pr: PullRequest
    let model: PRReviewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if let url = URL(string: pr.htmlUrl) { openURL(url) }
            } label: {
                HStack(spacing: 3) {
                    Text("#\(pr.number)")
                        .font(.system(size: ClaudeTheme.size(12), weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: ClaudeTheme.size(9), weight: .semibold))
                }
                .foregroundStyle(ClaudeTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(pr.title)

            Text(model.stateLabel)
                .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                .foregroundStyle(model.isReadyToMerge ? ClaudeTheme.statusSuccess : ClaudeTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                // TODO: real merge via the GitHub API; opens the PR in the browser for now.
                if let url = URL(string: pr.htmlUrl) { openURL(url) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.merge")
                    Text("Merge")
                }
                .font(.system(size: ClaudeTheme.size(12), weight: .semibold))
                .foregroundStyle(model.isReadyToMerge ? ClaudeTheme.statusSuccess : ClaudeTheme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(model.isReadyToMerge ? ClaudeTheme.statusSuccess : ClaudeTheme.borderSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Open the pull request to merge")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Inspector Terminal Dock

/// Docked lower section of the inspector hosting Setup / Run / Terminal. Collapsible (chevron / ×) and
/// resizable (top drag handle). All three sub-panes stay mounted and are height-gated, so the terminal
/// session survives sub-tab switches and collapse.
struct InspectorTerminalDock: View {
    let cwd: String?
    @Binding var isOpen: Bool
    @Binding var tab: TerminalDockTab
    @Binding var bodyHeight: Double

    @State private var process = TerminalProcess()
    @State private var resetID = UUID()
    @State private var focusID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            if isOpen { resizeHandle } else { ClaudeThemeDivider() }
            header
            if isOpen { ClaudeThemeDivider() }
            content
                .frame(height: isOpen ? CGFloat(bodyHeight) : 0)
                .clipped()
        }
        .background(ClaudeTheme.surfaceElevated)
        .onChange(of: tab) { _, newTab in
            if newTab == .terminal { focusID = UUID() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isOpen.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isOpen ? 0 : -90))
                    .font(.system(size: ClaudeTheme.size(11), weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Collapse" : "Expand")

            ForEach(TerminalDockTab.allCases, id: \.self) { t in
                Button {
                    tab = t
                    if !isOpen { withAnimation(.easeInOut(duration: 0.15)) { isOpen = true } }
                    if t == .terminal { focusID = UUID() }
                } label: {
                    Text(LocalizedStringKey(t.rawValue))
                        .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(tab == t ? ClaudeTheme.textPrimary : ClaudeTheme.textSecondary)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(tab == t ? ClaudeTheme.accent : Color.clear)
                                .frame(height: 1.5)
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            if tab == .terminal {
                InspectorIconButton(systemName: "arrow.counterclockwise", help: "Reset Terminal") { resetTerminal() }
            }

            InspectorIconButton(systemName: "plus", help: "New Terminal") {
                tab = .terminal
                if !isOpen { isOpen = true }
                resetTerminal()
            }

            InspectorIconButton(systemName: "xmark", help: "Close") {
                withAnimation(.easeInOut(duration: 0.15)) { isOpen = false }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: Content (all sub-panes mounted; height-gated to preserve the terminal session)

    private var content: some View {
        VStack(spacing: 0) {
            setupPane
                .frame(maxHeight: tab == .setup ? .infinity : 0)
                .clipped()

            RunPaneView(embedded: true)
                .frame(maxHeight: tab == .run ? .infinity : 0)
                .clipped()

            EmbeddedTerminalView(
                executable: "/bin/zsh",
                arguments: ["-il"],
                currentDirectory: cwd,
                process: process,
                focusTrigger: focusID
            )
            .id(resetID)
            .padding(8)
            .background(ClaudeTheme.codeBackground)
            .frame(maxHeight: tab == .terminal ? .infinity : 0)
            .clipped()
        }
    }

    private var setupPane: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: ClaudeTheme.size(22)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            // TODO: wire a per-project setup script once that concept exists (mirror RunPaneView).
            Text("No setup script configured")
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClaudeTheme.codeBackground)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(ClaudeTheme.border)
            .frame(height: 1)
            .overlay(Color.clear.frame(height: 6).contentShape(Rectangle()))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        bodyHeight = max(120, min(600, bodyHeight - Double(value.translation.height)))
                    }
            )
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
    }

    private func resetTerminal() {
        process.terminate()
        process = TerminalProcess()
        resetID = UUID()
        focusID = UUID()
    }
}

// MARK: - Claude Segmented Control

struct ClaudeSegmentedControl: View {
    @Binding var selection: MainView.SidebarTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainView.SidebarTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: ClaudeTheme.size(10), weight: .medium))
                        Text(LocalizedStringKey(tab.rawValue))
                            .font(.system(size: ClaudeTheme.size(12), weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .foregroundStyle(selection == tab ? ClaudeTheme.textOnAccent : ClaudeTheme.textSecondary)
                    .background(
                        selection == tab ? ClaudeTheme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(ClaudeTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
    }
}

// MARK: - Sidebar Tab Shortcuts

struct SidebarTabShortcuts: View {
    @Binding var sidebarTab: MainView.SidebarTab
    @Binding var fileSearchTrigger: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .background {
                Button("") {
                    withAnimation(.easeInOut(duration: 0.15)) { sidebarTab = .files }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fileSearchTrigger.toggle() }
                }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()

                Button("") {
                    columnVisibility = .all
                    withAnimation(.easeInOut(duration: 0.15)) { sidebarTab = .history }
                }
                .keyboardShortcut("1", modifiers: .command)
                .hidden()

                Button("") {
                    columnVisibility = .all
                    withAnimation(.easeInOut(duration: 0.15)) { sidebarTab = .files }
                }
                .keyboardShortcut("2", modifiers: .command)
                .hidden()
            }
    }
}

// MARK: - Shared Chat UI Components

private func effortDisplayName(_ effort: String) -> String {
    switch effort {
    case "low": return "Low"
    case "medium": return "Medium"
    case "high": return "High"
    case "xhigh": return "XHigh"
    case "max": return "Max"
    default: return effort.capitalized
    }
}

enum ChatToolbarControlsPlacement {
    case toolbar
    case composer
}

struct ChatToolbarControls: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let placement: ChatToolbarControlsPlacement

    init(placement: ChatToolbarControlsPlacement = .toolbar) {
        self.placement = placement
    }

    private var effectiveMode: PermissionMode { windowState.sessionPermissionMode ?? appState.permissionMode }
    private var effectiveModel: String { windowState.sessionModel ?? appState.selectedModel }

    var body: some View {
        HStack(spacing: placement == .composer ? 8 : 4) {
            if placement == .composer {
                Spacer(minLength: 12)
            }

            Menu {
                Section("Permission Mode") {
                    ForEach(PermissionMode.allCases, id: \.self) { mode in
                        Button {
                            appState.setSessionPermissionMode(mode, in: windowState)
                        } label: {
                            Text(LocalizedStringKey(mode.displayName))
                            if effectiveMode == mode { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                controlLabel(
                    title: effectiveMode.displayName,
                    isAccent: placement == .composer
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Permission mode: \(effectiveMode.displayName)")

            Menu {
                Section("Model Picker") {
                    ForEach(AppState.availableModels, id: \.self) { model in
                        Button {
                            appState.setSessionModel(model, in: windowState)
                        } label: {
                            Text(AppState.modelDisplayName(model))
                            if effectiveModel == model { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                controlLabel(
                    title: AppState.modelDisplayName(effectiveModel),
                    isAccent: false
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Model: \(AppState.modelDisplayName(effectiveModel))")

            Menu {
                Section("Effort Picker") {
                    Button {
                        appState.setSessionEffort(nil, in: windowState)
                    } label: {
                        Text("Auto Effort")
                        if windowState.sessionEffort == nil { Image(systemName: "checkmark") }
                    }
                    Divider()
                    ForEach(AppState.availableEfforts, id: \.self) { effort in
                        Button {
                            appState.setSessionEffort(effort, in: windowState)
                        } label: {
                            Text(LocalizedStringKey(effortDisplayName(effort)))
                            if windowState.sessionEffort == effort { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                controlLabel(
                    title: windowState.sessionEffort.map { effortDisplayName($0) } ?? "Auto Effort",
                    isAccent: false
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Effort level: \(windowState.sessionEffort.map { effortDisplayName($0) } ?? "Auto Effort")")
        }
        .frame(maxWidth: placement == .composer ? .infinity : nil, alignment: .leading)
    }

    @ViewBuilder
    private func controlLabel(title: String, isAccent: Bool) -> some View {
        switch placement {
        case .toolbar:
            ToolbarChipLabel(title: title)
        case .composer:
            ComposerControlLabel(title: title, isAccent: isAccent)
        }
    }
}

struct ToolbarChipLabel: View {
    let title: String

    @State private var isHovered = false

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.system(size: ClaudeTheme.size(12), weight: .medium))
        .foregroundStyle(ClaudeTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isHovered ? ClaudeTheme.surfaceTertiary : ClaudeTheme.surfaceSecondary,
            in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                .strokeBorder(ClaudeTheme.borderSubtle, lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
        .pointerCursorOnHover()
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

struct ComposerControlLabel: View {
    let title: String
    let isAccent: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isAccent ? ClaudeTheme.accent : ClaudeTheme.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            isHovered ? ClaudeTheme.surfaceSecondary.opacity(0.85) : Color.clear,
            in: RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
        )
        .contentShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
        .onHover { isHovered = $0 }
        .pointerCursorOnHover()
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

struct ChatDetailModifiers: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    func body(content: Content) -> some View {
        content
            .overlay {
                if let request = windowState.pendingPermissions.first {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        PermissionModal(request: request)
                            .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusLarge))
                            .shadow(color: ClaudeTheme.shadowColor, radius: 20)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: windowState.pendingPermissions.count)
                }
            }
            .sheet(isPresented: Bindable(windowState).showModelPicker) {
                ModelPickerSheet()
                    .environment(appState)
                    .environment(windowState)
            }
            .sheet(isPresented: Bindable(windowState).showEffortPicker) {
                EffortPickerSheet()
                    .environment(appState)
                    .environment(windowState)
            }
            .sheet(item: Bindable(windowState).interactiveTerminal) { terminal in
                InteractiveTerminalPopup(state: terminal)
            }
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    private var effectiveModel: String { windowState.sessionModel ?? appState.selectedModel }

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Model")
                .font(.headline)
                .foregroundStyle(ClaudeTheme.textPrimary)

            VStack(spacing: 8) {
                ForEach(AppState.availableModels.indices, id: \.self) { index in
                    let model = AppState.availableModels[index]
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppState.modelDisplayName(model))
                                .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                                .foregroundStyle(ClaudeTheme.textPrimary)
                            Text(AppState.modelDescription(model))
                                .font(.system(size: ClaudeTheme.size(11)))
                                .foregroundStyle(ClaudeTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if effectiveModel == model {
                            Image(systemName: "checkmark")
                                .foregroundStyle(ClaudeTheme.accent)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(index == selectedIndex ? ClaudeTheme.accentSubtle : ClaudeTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
                    .onTapGesture {
                        appState.setSessionModel(model, in: windowState)
                        dismiss()
                    }
                }
            }

            Text("↑↓ Select  ↵ Confirm  esc Cancel")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .padding(20)
        .frame(width: 380)
        .background(ClaudeTheme.background)
        .focusable()
        .focused($isFocused)
        .onKeyPress(.upArrow) {
            selectedIndex = (selectedIndex - 1 + AppState.availableModels.count) % AppState.availableModels.count
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = (selectedIndex + 1) % AppState.availableModels.count
            return .handled
        }
        .onKeyPress(.return) {
            appState.setSessionModel(AppState.availableModels[selectedIndex], in: windowState)
            dismiss()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            selectedIndex = AppState.availableModels.firstIndex(of: effectiveModel) ?? 0
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

// MARK: - Effort Picker Sheet

struct EffortPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool

    // 0 = Auto (nil), 1...n = availableEfforts
    private let items: [String?] = [nil] + AppState.availableEfforts.map { Optional($0) }

    private var effectiveEffort: String? { windowState.sessionEffort }

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Effort Level")
                .font(.headline)
                .foregroundStyle(ClaudeTheme.textPrimary)

            VStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { index in
                    let effort = items[index]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(effort.map { effortDisplayName($0) } ?? "Auto")
                                .foregroundStyle(ClaudeTheme.textPrimary)
                            if effort == "max" {
                                Text("Opus 4.6 only")
                                    .font(.caption2)
                                    .foregroundStyle(ClaudeTheme.textTertiary)
                            }
                        }
                        Spacer()
                        if effectiveEffort == effort {
                            Image(systemName: "checkmark")
                                .foregroundStyle(ClaudeTheme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(index == selectedIndex ? ClaudeTheme.accentSubtle : ClaudeTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
                    .onTapGesture {
                        appState.setSessionEffort(effort, in: windowState)
                        dismiss()
                    }
                }
            }

            Text("↑↓ Select  ↵ Confirm  esc Cancel")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textTertiary)
        }
        .padding(20)
        .frame(width: 300)
        .background(ClaudeTheme.background)
        .focusable()
        .focused($isFocused)
        .onKeyPress(.upArrow) {
            selectedIndex = (selectedIndex - 1 + items.count) % items.count
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = (selectedIndex + 1) % items.count
            return .handled
        }
        .onKeyPress(.return) {
            appState.setSessionEffort(items[selectedIndex], in: windowState)
            dismiss()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            selectedIndex = items.firstIndex(where: { $0 == effectiveEffort }) ?? 0
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

#Preview {
    MainView()
        .environment(AppState())
        .environment(WindowState())
}
