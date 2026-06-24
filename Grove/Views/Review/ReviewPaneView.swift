import SwiftUI
import GroveCore

/// Right-panel "Review" tab: fetches the open PR for the selected workspace's
/// branch and lists its inline review comments. Each comment can be
/// **incorporated** (seeds the chat composer with an "Address this:" prompt) or
/// **dismissed** (hidden locally).
struct ReviewPaneView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    @State private var comments: [PRReviewComment] = []
    @State private var dismissed: Set<Int> = []
    @State private var pullRequest: PullRequest?
    @State private var loading = false
    @State private var errorText: String?

    private var repoFullName: String? { windowState.selectedProject?.gitHubRepo }
    private var branch: String? { windowState.selectedWorkspace?.branch }

    private var visibleComments: [PRReviewComment] {
        comments.filter { !dismissed.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeThemeDivider()
            content
        }
        .background(ClaudeTheme.surfaceElevated)
        .task(id: "\(repoFullName ?? "")|\(branch ?? "")") { await reload() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let pr = pullRequest {
                Text("PR #\(pr.number)")
                    .font(.system(size: ClaudeTheme.size(11), weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                Text(pr.title)
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .lineLimit(1)
            } else {
                Text("Review")
                    .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
            Spacer()
            Button { Task { await reload() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: ClaudeTheme.size(11)))
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if !appState.isLoggedIn {
            placeholder("Sign in to GitHub to sync PR comments")
        } else if repoFullName == nil {
            placeholder("No GitHub repo linked to this project")
        } else if branch == nil {
            placeholder("Select a workspace to review its PR")
        } else if loading {
            placeholder("Loading…")
        } else if let errorText {
            placeholder(errorText)
        } else if pullRequest == nil {
            placeholder("No open pull request for this branch")
        } else if visibleComments.isEmpty {
            placeholder("No review comments")
        } else {
            List(visibleComments) { comment in
                commentRow(comment)
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }
            .listStyle(.plain)
        }
    }

    private func commentRow(_ comment: PRReviewComment) -> some View {
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

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func locationLabel(_ comment: PRReviewComment) -> String {
        let name = URL(fileURLWithPath: comment.path).lastPathComponent
        if let line = comment.displayLine { return "\(name):\(line)" }
        return name
    }

    private func incorporate(_ comment: PRReviewComment) {
        let location: String
        if let line = comment.displayLine {
            location = "\(comment.path):\(line)"
        } else {
            location = comment.path
        }
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

    private func reload() async {
        guard appState.isLoggedIn, let repo = repoFullName, let branch else {
            comments = []
            pullRequest = nil
            return
        }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            guard let pr = try await appState.github.fetchPullRequest(repoFullName: repo, branch: branch) else {
                pullRequest = nil
                comments = []
                return
            }
            pullRequest = pr
            comments = try await appState.github.fetchReviewComments(repoFullName: repo, pullNumber: pr.number)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            comments = []
        }
    }
}
