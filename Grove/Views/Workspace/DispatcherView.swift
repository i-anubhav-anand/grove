import SwiftUI
import GroveCore

/// Dispatch from a GitHub issue: pick an open issue, create a worktree on a
/// branch named for it, and open a chat seeded with the issue so an agent can
/// start immediately. Reuses `AppState.createWorkspace` and read-only GitHub
/// calls. See `AppState+Dispatch`.
struct DispatcherView: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss

    let preselectedProject: Project?
    /// Called after a successful dispatch so a presenting sheet can close too.
    var onDispatched: (() -> Void)?

    @State private var projectId: UUID?
    @State private var issues: [AppState.DispatchIssue] = []
    @State private var searchText = ""
    @State private var loading = false
    @State private var dispatching: Int?
    @State private var autoSend = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dispatch from issue")
                .font(.headline)
            Text("Pick an open GitHub issue. Grove creates a workspace on a branch named for the issue and seeds a new chat with it, so an agent can start working right away.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Project", selection: $projectId) {
                Text("Select…").tag(UUID?.none)
                ForEach(appState.projects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search issues…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            issueList

            Toggle("Send the prompt immediately", isOn: $autoSend)
                .font(.caption)
                .toggleStyle(.checkbox)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 540)
        .onAppear { projectId = preselectedProject?.id ?? appState.projects.first?.id }
        .task(id: projectId) { await loadIssues() }
    }

    // MARK: - Issue list

    @ViewBuilder
    private var issueList: some View {
        if loading {
            centered { ProgressView().controlSize(.small) }
        } else if errorText != nil && issues.isEmpty {
            centered {
                Text("Couldn't load issues.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if filteredIssues.isEmpty {
            centered {
                Text(issues.isEmpty ? "No open issues." : "No issues match your search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            List(filteredIssues) { issue in
                issueRow(issue)
            }
            .listStyle(.plain)
            .frame(maxHeight: .infinity)
        }
    }

    private func issueRow(_ issue: AppState.DispatchIssue) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "smallcircle.filled.circle")
                .font(.caption)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.body)
                    .lineLimit(1)
                Text("#\(issue.number)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if dispatching == issue.number {
                ProgressView().controlSize(.small)
            } else {
                Button("Dispatch") { dispatch(issue) }
                    .disabled(dispatching != nil)
            }
        }
        .padding(.vertical, 2)
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private var filteredIssues: [AppState.DispatchIssue] {
        guard !searchText.isEmpty else { return issues }
        return issues.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || "\($0.number)".contains(searchText)
        }
    }

    private func loadIssues() async {
        guard let pid = projectId,
              let project = appState.projects.first(where: { $0.id == pid }) else {
            issues = []
            return
        }
        loading = true
        errorText = nil
        issues = []
        do {
            issues = try await appState.fetchOpenIssues(for: project)
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }

    private func dispatch(_ issue: AppState.DispatchIssue) {
        guard let pid = projectId else { return }
        dispatching = issue.number
        errorText = nil
        Task {
            do {
                _ = try await appState.dispatch(issue: issue, projectId: pid, autoSend: autoSend, in: windowState)
                dismiss()
                onDispatched?()
            } catch {
                errorText = error.localizedDescription
                dispatching = nil
            }
        }
    }
}
