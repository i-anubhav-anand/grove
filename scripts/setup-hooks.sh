#!/bin/sh
# Point git at the repo's committed hooks so every clone/worktree gets the
# pre-commit test gate. Run once after cloning:  ./scripts/setup-hooks.sh
set -e
ROOT="$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
chmod +x "$ROOT/.githooks/"* 2>/dev/null || true
echo "Hooks installed: core.hooksPath -> .githooks (pre-commit runs swift test)."
