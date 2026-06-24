import SwiftUI
import GroveCore

/// Create a workspace: choose a project, name a new branch, and fork from a base
/// ref. Creates a real git worktree via `AppState.createWorkspace` and selects it.
struct NewWorkspaceSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss

    let preselectedProject: Project?

    @State private var projectId: UUID?
    @State private var branch = ""
    @State private var baseRef = "HEAD"
    @State private var creating = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New workspace")
                .font(.headline)
            Text("Creates an isolated git worktree on a new branch, so an agent can work this repo in parallel without colliding with others.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Picker("Project", selection: $projectId) {
                    Text("Select…").tag(UUID?.none)
                    ForEach(appState.projects) { project in
                        Text(project.name).tag(UUID?.some(project.id))
                    }
                }
                TextField("New branch", text: $branch, prompt: Text("feature/login"))
                TextField("Fork from", text: $baseRef, prompt: Text("HEAD"))
            }
            .formStyle(.grouped)
            .frame(height: 130)

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
                Button(creating ? "Creating…" : "Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { projectId = preselectedProject?.id ?? appState.projects.first?.id }
    }

    private var canCreate: Bool {
        projectId != nil
            && !branch.trimmingCharacters(in: .whitespaces).isEmpty
            && !creating
    }

    private func create() {
        guard let pid = projectId else { return }
        let branchName = branch.trimmingCharacters(in: .whitespaces)
        let base = baseRef.trimmingCharacters(in: .whitespaces).isEmpty
            ? "HEAD" : baseRef.trimmingCharacters(in: .whitespaces)
        creating = true
        errorText = nil
        Task {
            do {
                let ws = try await appState.createWorkspace(projectId: pid, branch: branchName, baseRef: base)
                appState.selectWorkspace(ws, in: windowState)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            creating = false
        }
    }
}
