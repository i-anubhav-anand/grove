import SwiftUI
import GroveCore

/// Shared pull-request state for the inspector. One fetch feeds both the "Ready to merge" header
/// (above the tabs) and the Changes pane's review-comments toggle — so we never fetch twice.
@MainActor
@Observable
final class PRReviewModel {
    var pullRequest: PullRequest?
    var comments: [PRReviewComment] = []
    /// `mergeable_state`: "clean" means ready to merge.
    var mergeableState: String?
    var loading = false
    var errorText: String?

    var isReadyToMerge: Bool { mergeableState == "clean" }

    /// Short human label for the PR's current mergeability.
    var stateLabel: String {
        switch mergeableState {
        case "clean": return "Ready to merge"
        case "blocked": return "Blocked"
        case "dirty": return "Conflicts"
        case "behind": return "Behind base"
        case "unstable": return "Checks pending"
        case "draft": return "Draft"
        default: return "Open"
        }
    }

    func reload(github: GitHubService, repo: String?, branch: String?, loggedIn: Bool) async {
        guard loggedIn, let repo, let branch else {
            reset(); return
        }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            guard let pr = try await github.fetchPullRequest(repoFullName: repo, branch: branch) else {
                reset(); return
            }
            pullRequest = pr
            comments = try await github.fetchReviewComments(repoFullName: repo, pullNumber: pr.number)
            mergeableState = try? await github.fetchMergeableState(repoFullName: repo, number: pr.number)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            pullRequest = nil
            comments = []
            mergeableState = nil
        }
    }

    private func reset() {
        pullRequest = nil
        comments = []
        mergeableState = nil
        errorText = nil
    }
}

// MARK: - PR Review Comments (relocated from the former ReviewPaneView tab)

/// Inline list of a PR's review comments. Each can be **incorporated** (seeds the chat composer)
/// or **dismissed** (hidden locally). Surfaced via the eye toggle in the Changes pane header.
struct PRCommentsView: View {
    @Environment(WindowState.self) private var windowState
    let comments: [PRReviewComment]

    @State private var dismissed: Set<Int> = []

    private var visible: [PRReviewComment] {
        comments.filter { !dismissed.contains($0.id) }
    }

    var body: some View {
        if visible.isEmpty {
            VStack {
                Spacer()
                Text("No review comments")
                    .font(.system(size: ClaudeTheme.size(12)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(visible) { comment in
                row(comment)
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }
            .listStyle(.plain)
        }
    }

    private func row(_ comment: PRReviewComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(comment.author)
                    .font(.system(size: ClaudeTheme.size(11), weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textPrimary)
                Spacer()
                Text(locationLabel(comment))
                    .font(.system(size: ClaudeTheme.size(10), design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Text(comment.body)
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(ClaudeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button { incorporate(comment) } label: {
                    Label("Incorporate", systemImage: "arrow.down.doc")
                        .font(.system(size: ClaudeTheme.size(10), weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(ClaudeTheme.accent)

                Button { dismissed.insert(comment.id) } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.system(size: ClaudeTheme.size(10)))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(ClaudeTheme.textTertiary)
            }
        }
        .padding(8)
        .background(ClaudeTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func locationLabel(_ comment: PRReviewComment) -> String {
        let name = URL(fileURLWithPath: comment.path).lastPathComponent
        if let line = comment.displayLine { return "\(name):\(line)" }
        return name
    }

    private func incorporate(_ comment: PRReviewComment) {
        let location = comment.displayLine.map { "\(comment.path):\($0)" } ?? comment.path
        let body = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = "Address this: \(location) — \(body)"
        if windowState.inputText.isEmpty {
            windowState.inputText = prompt
        } else {
            windowState.inputText += "\n" + prompt
        }
        windowState.requestInputFocus = true
        dismissed.insert(comment.id)
    }
}
