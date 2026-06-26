import SwiftUI
import GroveCore

// MARK: - RunPaneView

/// Runs a project's configured run script (⌘R) in the selected worktree via an
/// embedded terminal. Presented as a sheet/standalone pane. Re-running terminates
/// the previous process and starts a fresh one; a stop button kills the current run.
struct RunPaneView: View {
    /// When embedded in the inspector terminal dock: drop the sheet sizing + the standalone
    /// close button, and don't auto-run on appear (the pane stays mounted behind sub-tabs).
    var embedded: Bool = false

    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.dismiss) private var dismiss

    @State private var process = TerminalProcess()
    /// Changing this rebuilds the terminal NSView, which (re)starts the process.
    @State private var runToken: UUID?
    @State private var isRunning = false
    @State private var exitCode: Int32?

    @State private var isEditing = false
    @State private var scriptDraft = ""

    private var cwd: String? {
        appState.runWorkingDirectory(in: windowState)
    }

    private var script: String? {
        appState.runScript(in: windowState)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeThemeDivider()

            if isEditing || script == nil {
                editor
            }

            if let token = runToken, let script, let cwd {
                EmbeddedTerminalView(
                    executable: "/bin/zsh",
                    arguments: ["-ilc", script],
                    currentDirectory: cwd,
                    onProcessTerminated: { code in
                        Task { @MainActor in
                            exitCode = code
                            isRunning = false
                        }
                    },
                    process: process
                )
                .id(token)
                .padding(8)
                .background(ClaudeTheme.codeBackground)
                .frame(maxHeight: .infinity)
            } else {
                idlePlaceholder
            }
        }
        .runPaneFrame(embedded: embedded)
        .background(ClaudeTheme.surfaceElevated)
        .onAppear {
            scriptDraft = script ?? ""
            // Auto-run once when opened with a script already configured (sheet mode only).
            if script != nil, !embedded { run() }
        }
        .onDisappear { process.terminate() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.circle")
                .foregroundStyle(ClaudeTheme.accent)
            Text("Run")
                .font(.system(size: ClaudeTheme.size(13), weight: .medium, design: .monospaced))
                .foregroundStyle(ClaudeTheme.textPrimary)

            if let script, !isEditing {
                Text(script)
                    .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            statusBadge

            // Edit the run script
            Button {
                scriptDraft = script ?? ""
                isEditing.toggle()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Edit Run Script")

            // Stop
            Button {
                stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(!isRunning)
            .help("Stop")

            // Run / Re-run (⌘R)
            Button {
                run()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(script == nil || cwd == nil)
            .help("Run (⌘R)")

            if !embedded {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: ClaudeTheme.size(11), weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("w", modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isRunning {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Running")
                    .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
        } else if let exitCode {
            HStack(spacing: 4) {
                Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: ClaudeTheme.size(11)))
                    .foregroundStyle(exitCode == 0 ? ClaudeTheme.statusSuccess : ClaudeTheme.statusError)
                Text(exitCode == 0 ? "exit 0" : "exit \(exitCode)")
                    .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
                    .foregroundStyle(ClaudeTheme.textTertiary)
            }
        }
    }

    // MARK: - Script Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run Script")
                .font(.system(size: ClaudeTheme.size(11), weight: .semibold))
                .foregroundStyle(ClaudeTheme.textTertiary)

            TextField("e.g. npm run dev", text: $scriptDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: ClaudeTheme.size(12), design: .monospaced))
                .lineLimit(1...4)
                .padding(8)
                .background(ClaudeTheme.codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel") { isEditing = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(ClaudeTheme.textTertiary)
                Button("Save & Run") {
                    appState.setRunScript(scriptDraft, in: windowState)
                    isEditing = false
                    if script != nil { run() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(scriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "play.circle")
                .font(.system(size: ClaudeTheme.size(22)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            Text(cwd == nil ? "Select a project to run a script" : "Press ⌘R to run")
                .font(.system(size: ClaudeTheme.size(12)))
                .foregroundStyle(ClaudeTheme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClaudeTheme.codeBackground)
    }

    // MARK: - Actions

    private func run() {
        guard script != nil, cwd != nil else { return }
        process.terminate()
        process = TerminalProcess()
        exitCode = nil
        isRunning = true
        runToken = UUID()
    }

    private func stop() {
        process.terminate()
        isRunning = false
    }
}

private extension View {
    /// Sheet sizing for standalone presentation; flexible fill when embedded in the dock.
    @ViewBuilder
    func runPaneFrame(embedded: Bool) -> some View {
        if embedded {
            self.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            self.frame(minWidth: 700, idealWidth: 820, minHeight: 480, idealHeight: 620)
        }
    }
}
