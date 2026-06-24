import SwiftUI
import GroveCore

/// Prompt-first workspace creation: describe the task, pick the project, and Grove
/// spins up an isolated git worktree — branched from the repo's remote default
/// branch — on a branch named for your prompt, opens a fresh chat, and seeds it so
/// an agent can start right away. No branch or base-ref fiddling required.
/// See `AppState.dispatch(prompt:projectId:autoSend:in:)`.
struct NewWorkspaceSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss

    let preselectedProject: Project?

    @State private var projectId: UUID?
    @State private var prompt = ""
    @State private var createMore = false
    @State private var creating = false
    @State private var errorText: String?
    @State private var showDispatcher = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New workspace")
                .font(.headline)

            promptField

            HStack(spacing: 10) {
                Picker("Create from", selection: $projectId) {
                    Text("Select project…").tag(UUID?.none)
                    ForEach(appState.projects) { project in
                        Text(project.name).tag(UUID?.some(project.id))
                    }
                }
                .labelsHidden()
                .fixedSize()

                Spacer()

                Toggle("Create more", isOn: $createMore)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                    .help("Keep this sheet open to create another workspace after this one")
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button {
                    showDispatcher = true
                } label: {
                    Label("Create from a GitHub issue", systemImage: "smallcircle.filled.circle")
                }
                .buttonStyle(.link)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(creating ? "Creating…" : "Create") { create() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            projectId = preselectedProject?.id ?? appState.projects.first?.id
            promptFocused = true
        }
        .sheet(isPresented: $showDispatcher) {
            DispatcherView(
                preselectedProject: projectId.flatMap { id in appState.projects.first { $0.id == id } } ?? preselectedProject,
                onDispatched: { dismiss() }
            )
        }
    }

    private var promptField: some View {
        ZStack(alignment: .topLeading) {
            if prompt.isEmpty {
                Text("What do you want to work on?")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $prompt)
                .focused($promptFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
        }
        .padding(8)
        .background(ClaudeTheme.inputBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(ClaudeTheme.border, lineWidth: 1)
        )
    }

    private var canCreate: Bool {
        projectId != nil
            && !prompt.trimmingCharacters(in: .whitespaces).isEmpty
            && !creating
    }

    private func create() {
        guard canCreate, let pid = projectId else { return }
        creating = true
        errorText = nil
        Task {
            do {
                try await appState.dispatch(prompt: prompt, projectId: pid, autoSend: false, in: windowState)
                if createMore {
                    prompt = ""
                    creating = false
                    promptFocused = true
                } else {
                    dismiss()
                }
            } catch {
                errorText = error.localizedDescription
                creating = false
            }
        }
    }
}
