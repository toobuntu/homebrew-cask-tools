<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# Shared Guidelines

This document contains guidelines shared between `AGENTS.md` and `CLAUDE.md`
to avoid content drift. Both files reference this document rather than
duplicating these sections.

## Reasoning style

Always operate with maximum reasoning effort and deep multi-step analysis.
Use extended thinking when available. Prefer thoroughness over speed.

- Decompose problems step by step; list assumptions before proceeding.
- Explore multiple approaches and evaluate tradeoffs before selecting a solution.
- Consider edge cases, failure modes, and macOS compatibility implications.
- Validate conclusions before producing final output — avoid first-pass or heuristic answers.
- Be exhaustive over concise.

## macOS compatibility

The Copilot Coding Agent runs on Ubuntu, but this tap targets macOS end-users.
**All implementations must be compatible with macOS.** Specifically:

- Use POSIX/BSD-compatible CLI syntax. macOS ships BSD variants of core utilities
  (`sed`, `awk`, `find`, `xargs`, `date`, `grep`, …); GNU extensions (e.g. `sed -E`
  with multi-line ranges, `date -d`, `find -printf`) are **not** available by default.
- Prefer Homebrew-installed tools (e.g. `ggrep`, `gsed`) or POSIX flags that work on both.
- Shell scripts must be POSIX `sh`-compatible or explicitly target `bash`/`zsh` with the
  appropriate shebang. Avoid bash-only syntax (e.g. `mapfile`, process substitution) in
  files with a `#!/bin/sh` shebang.
- Do not depend on Linux-specific paths (`/proc`, `/sys`) or packages (`apt`, `dpkg`).
- Ruby code that shells out must use commands available on macOS (e.g. `xattr`, `pkgutil`).
- When testing locally on the Ubuntu sandbox, be aware that macOS-only paths (Caskroom,
  `/Applications`, etc.) will not exist; mock or skip those paths in specs.
- `brew style --fix` is canonical for all files (Ruby and shell). It runs RuboCop for Ruby
  and shfmt + shellcheck for shell scripts. CI enforces this; the pre-commit hook does too.

## REUSE / licensing

Files must carry SPDX headers. Run `scripts/annotate.sh` to annotate non-compliant files.
The `reuse` tool is pre-installed in the Copilot sandbox; do **not** hand-write SPDX headers —
run `scripts/annotate.sh` so that formatting and copyright info are standardized throughout.

`scripts/annotate.sh` special-cases all generated files under `completions/` and man page
files (`.1`, `.1.md`): because the generator overwrites their content, they use `.license`
sidecars created with `--force-dot-license` rather than inline `#` comment headers.

License texts are committed in `LICENSES/` (populated via `reuse download --all`).
