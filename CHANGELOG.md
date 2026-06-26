# Changelog

All notable changes to **Grove** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Inspector tab bar** no longer wraps or overlaps at narrow widths — labels are single-line and the
  bar scrolls horizontally when cramped. The "Files" tab is now labelled **"All files"**, "Changes"
  shows a live changed-file count badge, and the inspector's minimum width is raised to 280pt.
- **Terminal moved to a docked lower section** of the inspector with **Setup · Run · Terminal**
  sub-tabs, a collapse chevron, a resize handle, and `+` / reset controls — removing the Terminal tab
  from the top bar. The terminal session now survives sub-tab switches and collapse.

## [0.5.0] - 2026-06-25

> Cockpit refinement release — per-session worktree isolation, a unified
> `~/Grove` home, image attachments that actually reach the model, a calmer
> Conductor-style transcript, and a rebuilt right inspector. Still a **preview**
> (not yet a stable `1.0`; see "Known limitations").

### Added

- **Per-session worktrees.** Every new chat now spins up its own isolated git
  worktree (not just one per workspace), so parallel sessions never collide on
  the working tree. Worktree branches are named after places (e.g. `missoula`)
  instead of being derived from the prompt.
- **Unified `~/Grove` home.** A single managed storage root with
  `repos/`, `workspaces/`, and `archived-contexts/`, plus full create / rename /
  delete (CRUD) for projects, workspaces, and sessions — with confirm dialogs
  for destructive actions in the sidebar.
- **Grove's own GitHub OAuth app.** Login uses Grove's first-party OAuth client
  ID instead of a borrowed one.
- **Unified "+" / Project menu** — Open project · Open GitHub project · Quick
  start (create a fresh local git repo ready for an agent).
- **Resizable right inspector** — drag handle with a persisted width
  (`@AppStorage`), moved out of the `HSplitView` so it no longer fights the
  chat pane for layout.
- **Image paste & attachment delivery** — pasted/dropped images are always
  attached, advertised on the pasteboard so paste reliably fires, and delivered
  to the model via file paths in the prompt (Clarc-style) rather than base64
  stdin blocks.

### Changed

- **Calmer, Conductor-style transcript.** Tool calls render as compact one-line
  activity rows (icon · action · target · status) instead of heavy cards; Bash
  shows as a terminal block and edits as file-edit pills with a hover diff
  preview. Tool output expands inline with **Show more / Show less** and no
  inner scroll box (so hovering never traps page scroll).
- **Plain, card-free activity rows** unify tool calls and thinking blocks; the
  mid-stream streaming-indicator box and tool-grouping were removed, and
  thinking-only turns fold into a single turn summary. Assistant text gains a
  subtle emerge animation when streaming completes.
- **Sidebar simplified** to one row per session (worktree folded in, no
  duplicate workspace row); the branch icon is colored by GitHub PR state
  (green = open, purple = merged).
- **Cleaner chat header** — removed the project-folder tab strip and the
  per-session tab bar above the chat; navigation now lives entirely in the
  sidebar. The title bar shows just `Grove(<version>)` (no CLI version).
- **Flatter message bubbles** — uniform 4 pt corners for a squarer, more
  segmented look.
- **Typography** — response text matches the activity-row size (12 pt) and
  markdown inherits font via `.font()` rather than hard-coded sizes.
- Session files are now resolved by id across working directories and the app
  watches the whole `~/.claude/projects/` tree instead of per-project roots.

### Fixed

- **Repeated keychain password prompts on launch.** The GitHub token is now
  stored with `delete-then-add` + `SecAccessCreate` (empty trusted list) instead
  of `SecItemUpdate`, so it is never ACL-locked to a specific binary under
  ad-hoc signing; a one-time migration re-saves the token on first read.
- **Lost chat session on reopen / switch.** Session lookup scans each
  workspace's worktree path (where the CLI actually writes session JSONL), and
  the workspace binding + cwd are restored when switching sessions.
- **Auto permission mode** no longer prompts — it auto-approves tool requests as
  intended.
- **Right-panel tabs** follow the selected project instead of a stale workspace.
- **`ANTHROPIC_API_KEY` is stripped** from the CLI subprocess environment.

### Security

- Removed `ANTHROPIC_API_KEY` from the spawned `claude` CLI environment so a
  user's ambient key is never forwarded to the subprocess.

## [0.2.0] - 2026-06-24

> Feature-complete **preview** (not yet a stable `1.0`; see "Known limitations").

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

- **Image attachments now reach the model.** Attached/pasted/dropped images were
  only referenced as a `[Attached image: <path>]` text line, so the CLI never
  received the actual image (the path was often a temp file deleted after the
  turn). Images are now sent as base64 image blocks in the stream-json user
  message — with magic-byte media-type detection and PNG transcoding for
  clipboard TIFF / unsupported containers.
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

[0.5.0]: https://github.com/i-anubhav-anand/grove/compare/v0.2.0...v0.5.0
[0.2.0]: https://github.com/i-anubhav-anand/grove/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/i-anubhav-anand/grove/releases/tag/v0.1.0
