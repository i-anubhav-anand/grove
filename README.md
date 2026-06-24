# 🌳 Grove

A native macOS app for Claude Code: streaming chat, tool rendering, permission approval, git/diff review, an embedded terminal, and per-workspace git worktree isolation for running agents in parallel.

## Build & run

```bash
# Logic + UI packages
cd Packages && swift build && swift test

# The app
open Grove.xcodeproj   # pick the "Grove" scheme, ⌘R
# or:
xcodebuild -project Grove.xcodeproj -scheme Grove -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" CODE_SIGNING_REQUIRED=NO build
```

## Layout

```
Grove/             App target (SwiftUI views, services)
Grove.xcodeproj    Xcode project
Packages/          GroveCore (logic) + GroveChatKit (UI)
GroveTests/        App tests
poc/WorktreeKit/   Worktree-isolation primitive
```

## Tech stack

Swift 6.2 · SwiftUI · macOS 15+ · Swift Package Manager · spawns the `claude` CLI.
