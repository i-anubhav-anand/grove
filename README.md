# 🌳 Grove

**Run a fleet of Claude Code agents in parallel — each in its own isolated git worktree — from one native macOS app.**

Grove is a native macOS client for [Claude Code](https://www.anthropic.com/claude-code). Instead of juggling terminal tabs, you drive many coding agents at once: every session runs in its own git worktree, so agents work side-by-side on the same repo without ever stepping on each other's files. You get streaming chat, rich tool rendering, one-click permission approval, built-in diff/PR review, and an embedded terminal — all in a focused, keyboard-friendly UI.

> **Status:** preview. Ships frequently (30+ releases); not yet a stable `1.0`. See [Known limitations](#known-limitations).

---

## Why Grove

Running agents in a raw terminal gets messy fast — parallel sessions clobber the working tree, tool output is hard to read, and reviewing what the agent changed means context-switching to another tool. Grove puts the whole loop in one place:

- **True parallelism, zero collisions.** Each chat session spins up its own git worktree under a managed `~/Grove` home, so many agents can work on many branches of the same repo simultaneously.
- **Readable agent runs.** Streaming responses, collapsible tool calls, and clear thinking/output separation — not a wall of terminal text.
- **Review without leaving the app.** See changed files, per-file diffs, a live changed-file count, checks status, and — when a branch has an open PR — a "Ready to merge" header with mergeable state and a Merge button.

## Features

- **Per-session git worktree isolation** — every new chat is its own branch + worktree; parallel sessions never collide.
- **Streaming chat** with rich **tool-call rendering** and thinking/output separation.
- **Permission approval** — approve or deny tool calls inline (with an auto-approve mode).
- **Diff & PR review** — changed-files view, per-file diffs, flat ⇄ folder grouping, checks tab, inline PR review comments, and one-click merge for branches with an open PR.
- **Embedded terminal** — docked Setup · Run · Terminal sub-tabs that survive tab switches.
- **Image attachments** — paste or drop images straight into a message; they're delivered to the model.
- **Unified `~/Grove` home** — managed `repos/`, `workspaces/`, and `archived-contexts/`, with full create / rename / delete for projects, workspaces, and sessions.
- **First-party GitHub OAuth** — sign in with Grove's own OAuth app.
- **MCP-aware** — renders MCP tools and their output.

## Build & run

Requires macOS 15+ and Xcode with a Swift 6.2 toolchain.

```bash
# Logic + UI packages (GroveCore, GroveChatKit)
cd Packages && swift build && swift test

# The app
open Grove.xcodeproj   # pick the "Grove" scheme, then ⌘R

# …or build from the command line without signing:
xcodebuild -project Grove.xcodeproj -scheme Grove -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" CODE_SIGNING_REQUIRED=NO build
```

Grove spawns the `claude` CLI under the hood, so make sure [Claude Code](https://www.anthropic.com/claude-code) is installed and authenticated.

## Project layout

```
App/               Thin app entry point
Grove/             App target — SwiftUI views, services, utilities
Grove.xcodeproj    Xcode project
Packages/          GroveCore (logic) + GroveChatKit (UI), with tests
GroveTests/        App-level tests
poc/WorktreeKit/   Worktree-isolation primitive
scripts/           Dev + release scripts
.githooks/         Pre-commit test gate
```

## Tech stack

Swift 6.2 · SwiftUI · macOS 15+ · Swift Package Manager · spawns the `claude` CLI. A pre-commit hook runs `swift test` before every commit.

## Known limitations

This is a preview build, not a stable `1.0`:

- APIs, storage layout, and UI are still moving release-to-release.
- Worktree management assumes a clean-ish repo; very large repos or unusual git setups may need manual cleanup.
- Not yet notarized for distribution — build from source (see above).

See [`CHANGELOG.md`](CHANGELOG.md) for the full release history.

## License

See repository for license details.
