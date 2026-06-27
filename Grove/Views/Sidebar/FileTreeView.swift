import SwiftUI
import AppKit
import GroveCore

/// View that displays the project folder structure as a tree.
struct FileTreeView: View {
    let projectPath: String
    @Binding var searchTrigger: Bool
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @State private var rootNode: FileNode?
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var showHiddenFiles = false
    @State private var refreshTick = 0
    @FocusState private var isSearchFieldFocused: Bool

    /// Returns only files matching the search query as a flat list
    private var filteredFiles: [FileNode] {
        guard let root = rootNode, !searchText.isEmpty else { return [] }
        var results: [FileNode] = []
        FileNode.collectFiles(from: root, matching: searchText.lowercased(), into: &results)
        return results
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Files")
                    .font(.system(size: ClaudeTheme.size(12), weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isSearching.toggle()
                        if isSearching {
                            isSearchFieldFocused = true
                        } else {
                            searchText = ""
                        }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(isSearching ? ClaudeTheme.accent : ClaudeTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .help("Search Files (⌘F)")

                Button {
                    showHiddenFiles.toggle()
                } label: {
                    Image(systemName: showHiddenFiles ? "eye" : "eye.slash")
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(showHiddenFiles ? ClaudeTheme.accent : ClaudeTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .help(showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files")

                Button {
                    refreshTick &+= 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(ClaudeTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search Bar
            if isSearching {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: ClaudeTheme.size(11)))
                        .foregroundStyle(ClaudeTheme.textTertiary)

                    TextField("Search filename...", text: $searchText)
                        .font(.system(size: ClaudeTheme.size(12)))
                        .textFieldStyle(.plain)
                        .focused($isSearchFieldFocused)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: ClaudeTheme.size(11)))
                                .foregroundStyle(ClaudeTheme.textTertiary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ClaudeTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .onExitCommand {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isSearching = false
                        searchText = ""
                    }
                }
            }

            ClaudeThemeDivider()

            if let root = rootNode {
                if isSearching && !searchText.isEmpty {
                    // Search results: flat list
                    let results = filteredFiles
                    if results.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "doc.questionmark")
                                .font(.system(size: ClaudeTheme.size(24)))
                                .foregroundStyle(ClaudeTheme.textTertiary)
                            Text("No results for '\(searchText)'")
                                .font(.system(size: ClaudeTheme.size(12)))
                                .foregroundStyle(ClaudeTheme.textTertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        treeScrollView {
                            Text("\(results.count) files")
                                .font(.system(size: ClaudeTheme.size(10)))
                                .foregroundStyle(ClaudeTheme.textTertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)

                            ForEach(results) { file in
                                SearchResultRow(node: file, searchText: searchText, selectedPath: windowState.inspectorFile?.path, onFileSelect: { node in
                                    windowState.inspectorFile = PreviewFile(path: node.id, name: node.name)
                                }, onAddPath: { node in
                                    addPathToInput(node)
                                })
                            }
                        }
                    }
                } else {
                    treeScrollView {
                        ForEach(root.children) { child in
                            FileNodeRow(node: child, depth: 0, selectedPath: windowState.inspectorFile?.path, onFileSelect: { node in
                                windowState.inspectorFile = PreviewFile(path: node.id, name: node.name)
                            }, onAddPath: { node in
                                addPathToInput(node)
                            })
                        }
                    }
                }
            } else {
                // First load only — subsequent project switches keep the previous tree visible
                // until the new scan completes (no flash).
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        // Single .task replaces onAppear + multiple onChange reload calls.
        // SwiftUI auto-cancels the previous scan when the key changes.
        .task(id: TreeScanKey(path: projectPath, hidden: showHiddenFiles, tick: refreshTick)) {
            let path = projectPath
            let hidden = showHiddenFiles
            let node = await Task.detached(priority: .userInitiated) {
                FileNode.scan(path: path, maxDepth: 4, showHiddenFiles: hidden)
            }.value
            guard !Task.isCancelled else { return }
            rootNode = node
        }
        .onChange(of: appState.isStreaming(in: windowState)) { old, new in
            if old && !new { refreshTick &+= 1 }
        }
        .onChange(of: searchTrigger) {
            withAnimation(.easeInOut(duration: 0.15)) {
                isSearching = true
                isSearchFieldFocused = true
            }
        }
    }

    private func addPathToInput(_ node: FileNode) {
        let path = "@" + node.id
        if windowState.inputText.isEmpty {
            windowState.inputText = path + " "
        } else {
            windowState.inputText += " " + path + " "
        }
        windowState.requestInputFocus = true
    }

    @ViewBuilder
    private func treeScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1, content: content)
                .padding(.vertical, 4)
        }
    }

}

// MARK: - Tree Scan Key

private struct TreeScanKey: Equatable {
    let path: String
    let hidden: Bool
    let tick: Int
}

// MARK: - File Node Row

private struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    let selectedPath: String?
    let onFileSelect: (FileNode) -> Void
    let onAddPath: (FileNode) -> Void
    @State private var isExpanded = false
    @State private var isHovered = false

    /// Per-level indent (the tree's `--tree-indent: 20px`).
    private static let indent: CGFloat = 20
    /// Chevron column width (`size-4` = 16px) + `gap-1` (4px).
    private static let chevronSlot: CGFloat = 16

    private var isSelected: Bool { !node.isDirectory && selectedPath == node.id }

    var body: some View {
        // not-last:pb-0.5 → 2px gap between sibling rows
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if node.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } else {
                    onFileSelect(node)
                }
            } label: {
                // Indent is inside the label so the background spans full width.
                HStack(spacing: 0) {
                    Color.clear.frame(width: CGFloat(depth) * Self.indent)

                    HStack(spacing: 4) {
                        if node.isDirectory {
                            Image(systemName: "chevron.down")
                                .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                                .foregroundStyle(ClaudeTheme.textTertiary)
                                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                                .frame(width: Self.chevronSlot, height: Self.chevronSlot)
                        } else {
                            Color.clear.frame(width: Self.chevronSlot, height: Self.chevronSlot)
                        }

                        Image(systemName: node.icon)
                            .font(.system(size: ClaudeTheme.size(12)))
                            .foregroundStyle(node.isDirectory ? ClaudeTheme.accent : node.iconColor)
                            .frame(width: 16)

                        Text(node.name)
                            .font(.system(size: ClaudeTheme.size(13), design: node.isDirectory ? .default : .monospaced))
                            .foregroundStyle(labelColor)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if node.isDirectory && !node.children.isEmpty {
                            Text("\(node.children.count)")
                                .font(.system(size: ClaudeTheme.size(10)))
                                .foregroundStyle(ClaudeTheme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? ClaudeTheme.accent.opacity(0.4) : .clear, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
            .contextMenu {
                if !node.isDirectory {
                    Button {
                        onAddPath(node)
                    } label: {
                        Label("Add path to message", systemImage: "text.append")
                    }
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.id)])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }

            if isExpanded {
                ForEach(node.children) { child in
                    FileNodeRow(node: child, depth: depth + 1, selectedPath: selectedPath, onFileSelect: onFileSelect, onAddPath: onAddPath)
                }
            }
        }
    }

    /// `hover:bg-accent` / `data-[selected=true]:bg-accent` — accent-tinted fill.
    private var rowBackground: Color {
        if isSelected { return ClaudeTheme.accent.opacity(0.22) }
        if isHovered { return ClaudeTheme.accent.opacity(0.10) }
        return .clear
    }

    private var labelColor: Color {
        if isSelected { return ClaudeTheme.textPrimary }
        return node.isDirectory ? ClaudeTheme.textPrimary : ClaudeTheme.textSecondary
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let node: FileNode
    let searchText: String
    let selectedPath: String?
    let onFileSelect: (FileNode) -> Void
    let onAddPath: (FileNode) -> Void
    @State private var isHovered = false

    private var isSelected: Bool { selectedPath == node.id }

    /// Extracts the parent folder name from the file path
    private var parentFolder: String {
        let url = URL(fileURLWithPath: node.id)
        return url.deletingLastPathComponent().lastPathComponent
    }

    var body: some View {
        Button {
            onFileSelect(node)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: node.icon)
                    .font(.system(size: ClaudeTheme.size(12)))
                    .foregroundStyle(node.iconColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name)
                        .font(.system(size: ClaudeTheme.size(13), design: .monospaced))
                        .foregroundStyle(ClaudeTheme.textPrimary)
                        .lineLimit(1)

                    Text(parentFolder)
                        .font(.system(size: ClaudeTheme.size(12)))
                        .foregroundStyle(ClaudeTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(searchRowBackground, in: RoundedRectangle(cornerRadius: 5))
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button {
                onAddPath(node)
            } label: {
                Label("Add path to message", systemImage: "text.append")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.id)])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }

    private var searchRowBackground: Color {
        if isSelected { return ClaudeTheme.accent.opacity(0.18) }
        if isHovered { return ClaudeTheme.sidebarItemHover }
        return .clear
    }
}

// MARK: - File Node Model

struct FileNode: Identifiable, Sendable {
    let id: String
    let name: String
    let isDirectory: Bool
    let children: [FileNode]

    var icon: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        case "md", "txt": return "doc.text"
        case "png", "jpg", "jpeg", "svg", "pdf": return "photo"
        case "css", "scss": return "paintbrush"
        case "html": return "globe"
        case "yaml", "yml", "toml": return "gearshape"
        case "gitignore": return "eye.slash"
        case "xcodeproj", "xcworkspace": return "hammer"
        default: return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return ClaudeTheme.accent }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "json": return ClaudeTheme.statusSuccess
        case "css", "scss": return .pink
        case "html": return ClaudeTheme.statusError
        case "png", "jpg", "jpeg", "svg", "pdf": return .purple
        default: return ClaudeTheme.textTertiary
        }
    }

    /// Recursively traverses the tree and collects file nodes whose names contain the search query
    static func collectFiles(from node: FileNode, matching query: String, into results: inout [FileNode]) {
        if !node.isDirectory && node.name.lowercased().contains(query) {
            results.append(node)
        }
        for child in node.children {
            collectFiles(from: child, matching: query, into: &results)
        }
    }

    nonisolated static func scan(path: String, maxDepth: Int, showHiddenFiles: Bool = false) -> FileNode? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        return buildNode(url: url, fm: fm, currentDepth: 0, maxDepth: maxDepth, showHiddenFiles: showHiddenFiles)
    }

    private nonisolated static let ignoredNames: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData",
        "node_modules", ".DS_Store", "Pods",
        "xcuserdata", ".xcodeproj", ".xcworkspace",
    ]

    private nonisolated static func buildNode(
        url: URL,
        fm: FileManager,
        currentDepth: Int,
        maxDepth: Int,
        showHiddenFiles: Bool
    ) -> FileNode {
        let name = url.lastPathComponent

        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        guard isDir.boolValue else {
            return FileNode(id: url.path, name: name, isDirectory: false, children: [])
        }

        var children: [FileNode] = []

        if currentDepth < maxDepth {
            var options: FileManager.DirectoryEnumerationOptions = []
            if !showHiddenFiles { options.insert(.skipsHiddenFiles) }

            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: options
            )) ?? []

            children = contents
                .filter { !ignoredNames.contains($0.lastPathComponent) }
                .map { buildNode(url: $0, fm: fm, currentDepth: currentDepth + 1, maxDepth: maxDepth, showHiddenFiles: showHiddenFiles) }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        }

        return FileNode(id: url.path, name: name, isDirectory: true, children: children)
    }
}

#Preview {
    FileTreeView(projectPath: "/Users/jmlee/workspace/Grove", searchTrigger: .constant(false))
        .frame(width: 280, height: 400)
}
