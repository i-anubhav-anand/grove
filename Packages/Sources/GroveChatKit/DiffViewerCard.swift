import SwiftUI
import GroveCore

/// Styled diff card matching the assistant-ui DiffViewer design:
/// header with filename + extension badge + +/- stats, then
/// line-numbered rows with colored backgrounds for additions/deletions.
struct DiffViewerCard: View {
    let filePath: String?
    let lines: [DiffLine]

    private static let collapseThreshold = 25
    @State private var isExpanded = false

    // MARK: Convenience inits

    init(filePath: String?, old: String, new: String) {
        self.filePath = filePath
        let hunk = PreviewFile.EditHunk(oldString: old, newString: new)
        self.lines = FileDiffView.buildEditDiffLines(from: [hunk])
    }

    init(filePath: String?, lines: [DiffLine]) {
        self.filePath = filePath
        self.lines = lines
    }

    // MARK: Computed

    private var addedCount: Int   { lines.filter { $0.kind == .added }.count }
    private var removedCount: Int { lines.filter { $0.kind == .removed }.count }

    private var fileName: String? {
        guard let p = filePath, !p.isEmpty else { return nil }
        let name = URL(fileURLWithPath: p).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private var fileExt: String? {
        guard let p = filePath, !p.isEmpty else { return nil }
        let ext = URL(fileURLWithPath: p).pathExtension.uppercased()
        return ext.isEmpty ? nil : ext
    }

    private var needsCollapse: Bool { lines.count > Self.collapseThreshold }

    private var visibleLines: [DiffLine] {
        guard needsCollapse && !isExpanded else { return lines }
        return Array(lines.prefix(Self.collapseThreshold))
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(ClaudeTheme.border)
                .frame(height: 0.5)

            if needsCollapse && isExpanded {
                ScrollView {
                    lineList
                }
                .frame(maxHeight: 380)
            } else {
                lineList
            }

            if needsCollapse {
                Rectangle()
                    .fill(ClaudeTheme.border)
                    .frame(height: 0.5)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded
                             ? String(localized: "Show less", bundle: .module)
                             : String(format: String(localized: "Show %lld more lines", bundle: .module),
                                      lines.count - Self.collapseThreshold))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: ClaudeTheme.messageSize(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .background(ClaudeTheme.codeBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ClaudeTheme.border, lineWidth: 0.5))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            // Extension badge
            if let ext = fileExt {
                Text(ext)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(ClaudeTheme.border.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
            }

            // File name
            Text(fileName ?? "Changes")
                .font(.system(size: ClaudeTheme.messageSize(12), design: .monospaced))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Spacer(minLength: 8)

            // Stats
            if addedCount > 0 {
                Text("+\(addedCount)")
                    .font(.system(size: ClaudeTheme.messageSize(11), weight: .semibold, design: .monospaced))
                    .foregroundStyle(ClaudeTheme.statusSuccess)
            }
            if removedCount > 0 {
                Text("-\(removedCount)")
                    .font(.system(size: ClaudeTheme.messageSize(11), weight: .semibold, design: .monospaced))
                    .foregroundStyle(ClaudeTheme.statusError)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ClaudeTheme.codeBackground)
    }

    // MARK: Lines

    private var lineList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                DiffLineRow(line: line)
            }
        }
        .background(ClaudeTheme.background)
    }
}
