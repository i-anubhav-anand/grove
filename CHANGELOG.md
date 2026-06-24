# Changelog

All notable changes to **Grove** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> Target: `0.2.0` — feature-complete **preview** (not yet a stable `1.0`; see
> "Known limitations").

### Added

- **Workspace cockpit (worktree per workspace).** Each workspace is an isolated
  git worktree on its own branch, created/managed from the sidebar.
  - `Workspace` model + `GitWorktreeService` wired into the app; create, list,
    archive (with a dirty-tree force-confirm), and launch-time reconcile.
  - Workspaces sidebar grouped **Project → Workspaces → Sessions**.
  - Per-workspace **status board** (Backlog / In Progress / In Review / Done).
  - Per-workspace **git diff stats** (`+adds −dels`) and a running indicator.
- **Three-pane cockpit shell** — left: session list; center: chat; right:
  always-on panel with **Files · Changes · Checks · Terminal · Review** tabs,
  bound to the selected worktree.
- **Multiple chats per workspace** as tabs (`⌘T` new, `⌘⇧W` close).
- **Run Script** pane (`⌘R`) to run a project's test/dev command in the worktree.
- **Command palette** (`⌘K`) to jump to workspaces, chats, projects, and actions.
- **Checks tab** — PR / CI status with a "fix failing checks" action that seeds
  the chat.
- **Dispatcher** — create a workspace from a GitHub issue with a seeded prompt.
- **Code review** — comment on a diff line (sends to chat) and sync PR review
  comments (incorporate / dismiss).
- **Workspace↔session binding** — new chats are bound to the selected workspace,
  **spawn in that workspace's worktree** (not the project root), and the binding
  is persisted across relaunch.
- **All-black theme**, set as the new default.
- **Pre-commit test gate** (`.githooks/pre-commit`) that blocks any commit unless
  `swift test` passes; install via `scripts/setup-hooks.sh`.

### Changed

- Sidebar flattened to a **Project → workspaces** list (with diff stats) and the
  composer placeholder is now **"Add a follow up"**.
- The file tree moved out of the left sidebar into the right panel's **Files** tab;
  the right panel is now persistent.

### Fixed

- Pre-commit hook: corrected a `tail`-pipe that masked `swift test`'s exit code,
  and cleared `GIT_*` hook env that was corrupting `core.bare` when worktree
  tests ran.

### Known limitations

- The full **create-workspace → chat → edit → commit → PR** loop is not yet
  dogfooded end-to-end (tracked: #22).
- A few features are pragmatic/partial: live diff-stat refresh is event-driven
  (not file-watched), and W8 click-through is unverified (tracked: #23).
- UI / integration test coverage is thin — only `GroveCore` unit tests today
  (tracked: #24).
- The app is **ad-hoc signed, not notarized** — distribution shows a Gatekeeper
  warning.

## [0.1.0] - 2026-06-24

### Added

- Initial release of **Grove**, a native macOS app for Claude Code.
  - **Engine** (`GroveCore`): spawn the `claude` CLI and stream its NDJSON output
    as typed `StreamEvent`s; `ShellPathResolver`; `ClaudeService` actor.
  - **Chat** (`GroveChatKit`): streaming transcript, markdown + code blocks,
    thinking blocks, tool rendering, permission approval, slash commands,
    attachments.
  - Embedded terminal, git status + diff review, GitHub login / repos / PR
    creation, skills marketplace, sessions/history, settings, onboarding.
  - `WorktreeKit` — verified per-workspace git worktree isolation primitive.

[Unreleased]: https://github.com/i-anubhav-anand/grove/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/i-anubhav-anand/grove/releases/tag/v0.1.0
