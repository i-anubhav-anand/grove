import Foundation
import GroveCore

/// W6 Dispatcher — turn a GitHub issue into a ready-to-work workspace: create a
/// worktree on a branch named for the issue, open a fresh chat in it, and seed
/// the first prompt with the issue so an agent can start immediately.
@MainActor
extension AppState {

    /// A GitHub issue, decoded from `GET /repos/{owner}/{repo}/issues`. The same
    /// endpoint returns pull requests; `pullRequest` is non-nil for those so they
    /// can be filtered out.
    struct DispatchIssue: Identifiable, Decodable, Sendable {
        let number: Int
        let title: String
        let body: String?
        let htmlUrl: String
        let pullRequest: PullRequestRef?

        var id: Int { number }
        var isPullRequest: Bool { pullRequest != nil }

        struct PullRequestRef: Decodable, Sendable {
            let url: String
        }

        enum CodingKeys: String, CodingKey {
            case number, title, body
            case htmlUrl = "html_url"
            case pullRequest = "pull_request"
        }
    }

    enum DispatchError: LocalizedError {
        case noRepo
        case notAuthenticated
        case apiError(Int, String)

        var errorDescription: String? {
            switch self {
            case .noRepo:
                return "This project isn't linked to a GitHub repo, so there are no issues to dispatch from."
            case .notAuthenticated:
                return "Sign in with GitHub to load issues."
            case .apiError(let code, let message):
                return "GitHub API error (\(code)): \(message)"
            }
        }
    }

    /// Read-only fetch of open issues for a project's linked GitHub repo. Pull
    /// requests are filtered out. Reuses `GitHubService`'s stored token without
    /// mutating it.
    func fetchOpenIssues(for project: Project) async throws -> [DispatchIssue] {
        guard let fullName = project.gitHubRepo, !fullName.isEmpty else {
            throw DispatchError.noRepo
        }
        guard let token = await github.accessToken else {
            throw DispatchError.notAuthenticated
        }
        guard let url = URL(string: "https://api.github.com/repos/\(fullName)/issues?state=open&per_page=100&sort=updated") else {
            throw DispatchError.noRepo
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw DispatchError.apiError(code, body)
        }

        let issues = try JSONDecoder().decode([DispatchIssue].self, from: data)
        return issues.filter { !$0.isPullRequest }
    }

    /// Git branch name derived from an issue, e.g. `issue-12-w6-dispatcher`.
    func branchName(for issue: DispatchIssue) -> String {
        var slug = ""
        var lastDash = false
        for ch in issue.title.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                slug.append(ch)
                lastDash = false
            } else if !lastDash {
                slug.append("-")
                lastDash = true
            }
        }
        let dashes = CharacterSet(charactersIn: "-")
        slug = slug.trimmingCharacters(in: dashes)
        if slug.count > 40 {
            slug = String(slug.prefix(40)).trimmingCharacters(in: dashes)
        }
        return slug.isEmpty ? "issue-\(issue.number)" : "issue-\(issue.number)-\(slug)"
    }

    /// The first prompt seeded into the new chat — the issue title and body.
    func seedPrompt(for issue: DispatchIssue) -> String {
        var text = "Work on GitHub issue #\(issue.number): \(issue.title)"
        if let body = issue.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            text += "\n\n\(body)"
        }
        return text
    }

    /// Create a workspace for the issue, open a fresh chat in it, and seed the
    /// first prompt. When `autoSend` is true the prompt is sent right away.
    @discardableResult
    func dispatch(
        issue: DispatchIssue,
        projectId: UUID,
        autoSend: Bool,
        in window: WindowState
    ) async throws -> Workspace {
        let workspace = try await createWorkspace(projectId: projectId, branch: branchName(for: issue))
        selectWorkspace(workspace, in: window)
        startNewChat(in: window)
        window.inputText = seedPrompt(for: issue)
        if autoSend {
            await send(in: window)
        } else {
            window.requestInputFocus = true
        }
        return workspace
    }

    // MARK: - Dispatch from a prompt

    /// Git branch name derived from a free-form prompt, e.g. "Add dark mode toggle"
    /// → `add-dark-mode-toggle`. Empty/punctuation-only prompts fall back to
    /// `workspace`.
    func branchName(forPrompt prompt: String) -> String {
        var slug = ""
        var lastDash = false
        for ch in prompt.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                slug.append(ch)
                lastDash = false
            } else if !lastDash {
                slug.append("-")
                lastDash = true
            }
        }
        let dashes = CharacterSet(charactersIn: "-")
        slug = slug.trimmingCharacters(in: dashes)
        if slug.count > 40 {
            slug = String(slug.prefix(40)).trimmingCharacters(in: dashes)
        }
        return slug.isEmpty ? "workspace" : slug
    }

    /// Disambiguate a branch name against the project's existing workspaces by
    /// appending `-2`, `-3`, … so two similar prompts don't collide.
    private func uniqueBranch(_ base: String, projectId: UUID) -> String {
        let existing = Set(workspaces.filter { $0.projectId == projectId }.map(\.branch))
        guard existing.contains(base) else { return base }
        var i = 2
        while existing.contains("\(base)-\(i)") { i += 1 }
        return "\(base)-\(i)"
    }

    /// Create a workspace from a free-form prompt: branch off the repo's remote
    /// default, open a fresh chat, and seed it with the prompt so an agent can
    /// start right away. When `autoSend` is true the prompt is sent immediately.
    @discardableResult
    func dispatch(
        prompt: String,
        projectId: UUID,
        autoSend: Bool,
        in window: WindowState
    ) async throws -> Workspace {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = uniqueBranch(branchName(forPrompt: trimmed), projectId: projectId)
        let workspace = try await createWorkspace(projectId: projectId, branch: branch)
        selectWorkspace(workspace, in: window)
        startNewChat(in: window)
        window.inputText = trimmed
        if autoSend {
            await send(in: window)
        } else {
            window.requestInputFocus = true
        }
        return workspace
    }
}
