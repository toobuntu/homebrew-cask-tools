<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# Agent Instructions for toobuntu/homebrew-cask-tools

This repository provides Homebrew external tap commands: `brew purge-quarantine`,
`brew cask-extract`, `brew man`, and `brew generate-tap-man-completions` (developer-only).
Code quality and style should be at a level suitable for potential inclusion in Homebrew.

Run `brew style --fix --changed && brew typecheck` to verify any file edits before committing.

## Reasoning style

Always operate with maximum reasoning effort and deep multi-step analysis.
Use extended thinking when available. Prefer thoroughness over speed.

- Decompose problems step by step; list assumptions before proceeding.
- Explore multiple approaches and evaluate tradeoffs before selecting a solution.
- Consider edge cases, failure modes, and macOS compatibility implications.
- Validate conclusions before producing final output — avoid first-pass or heuristic answers.
- Be exhaustive over concise.

## Homebrew in the Copilot Coding Agent Sandbox

`brew` is installed at `/home/linuxbrew/.linuxbrew/bin/brew` (via `.github/workflows/copilot-setup-steps.yml`)
but is **not on `PATH`** by default. Either:

- run `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` once per shell session, or
- use the full path `/home/linuxbrew/.linuxbrew/bin/brew` directly.

The cellar is empty (`core: false, cask: false`), but `brew style`, `brew typecheck`,
`brew tests`, and `brew mcp-server` all work because they only need the Homebrew runtime
and bundler gems (cached by `.github/workflows/copilot-setup-steps.yml`).
The following formulae are also pre-installed and available on `PATH`:
`actionlint`, `reuse`, `pinact`, `zizmor`, `shellcheck`, `shfmt`, `gh`, `gnu-tar`, `subversion`, `curl`.

## macOS Compatibility

The Copilot Coding Agent runs on Ubuntu, but this tap targets macOS end-users. **All
implementations must be compatible with macOS.** Specifically:

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

## Code Standards

### Required Before Each Commit

**Always prefer the Homebrew MCP Server tools** — use `Homebrew/style`, `Homebrew/typecheck`,
and `Homebrew/tests` from the MCP server rather than running `brew` via the bash tool.
The bash tool may have restricted network access in the Copilot sandbox; the MCP server
tools do not require outbound network access for style, typecheck, or test operations because
the bundler gems are pre-cached. Only fall back to bash if the MCP server is unavailable.

- `Homebrew/style` (MCP) — equivalent to `brew style --fix --changed`
- `Homebrew/typecheck` (MCP) — equivalent to `brew typecheck`
- `Homebrew/tests` (MCP) with `--only=cmd/purge-quarantine`, `--only=cmd/cask-extract`, `--only=cmd/man`, or `--only=cmd/generate-tap-man-completions` — equivalent to `brew tests --only=cmd/<file>`
  (requires the cmd/dev-cmd and spec to be hardlinked first — use `scripts/run-tests.sh`)

### Development Flow

- Write new code (using Sorbet `sig` type signatures and `typed: strict` for new files, but never for RSpec/test/`*_spec.rb` files)
- Write new tests (avoid more than one `:integration_test` per file for speed).
  Write fast tests by preferring a single `expect` per unit test and combine expectations in a single test when it is an integration test or has non-trivial `before` for test setup.
- When adding or tightening tests, verify them with a red/green cycle using the exact `--only=file:line` target for the example you changed.
- Formula classes created in specs may be frozen; avoid stubbing class methods on them with RSpec mocks and prefer instance-level stubs or test setup that does not require class-method stubbing.
- Keep comments minimal; prefer self-documenting code through strings, variable names, etc. over more comments.

## Repository Structure

- `cmd/purge-quarantine.rb`: External tap command implementing `brew purge-quarantine`.
  File name has no `brew-` prefix — Homebrew tap commands use this convention.
- `cmd/cask-extract.rb`: External tap command implementing `brew cask-extract`.
  Extracts a cask from Homebrew's git history into a personal tap, optionally adding
  a `postflight` block to remove macOS's quarantine extended attribute.
- `cmd/man.rb`: External tap command implementing `brew man`.
  Displays man pages bundled with installed formulae, with `--list` and `--interactive`
  modes for resolving ambiguity when multiple formulae ship the same page name.
- `dev-cmd/generate-tap-man-completions.rb`: Developer-only command implementing `brew generate-tap-man-completions`.
  Generates Bash, ZSH, and Fish completion files for all commands in `cmd/` and `dev-cmd/`, Ronn man
  page sources (`.1.md`), and compiled roff (`.1`) into `manpages/`. Cleans up stale files for
  removed commands. Accepts `--tap=<user>/<repo>` to override the auto-detected tap.
  Lives in `dev-cmd/` to avoid confusing casual users; requires `HOMEBREW_DEVELOPER=1`.
  Homebrew does not support external `dev-cmd/` in taps, so a `cmd/` hardlink is needed
  locally (see `.gitignore`). Symlinks do not work; Homebrew's command loading resolves
  symlinks to their realpath before registering commands. CI hardlinks the file directly.
  The `.githooks/post-merge` and `.githooks/post-rewrite` hooks re-create the hardlink
  automatically after `git pull` (set `core.hooksPath = .githooks` once to enable).
- `test/cmd/purge-quarantine_spec.rb`: RSpec spec for the `purge-quarantine` command.
- `test/cmd/cask-extract_spec.rb`: RSpec spec for the `cask-extract` command.
- `test/cmd/man_spec.rb`: RSpec spec for the `man` command.
- `test/cmd/generate-tap-man-completions_spec.rb`: RSpec spec for the `generate-tap-man-completions` command.
- `completions/`: Pre-generated shell completion files. Regenerate with `brew generate-tap-man-completions`
  after any `cmd_args` change. CI verifies these are not out of date.
- `manpages/`: Pre-generated man page sources (`.1.md`, Ronn format) and compiled roff (`.1`).
  Regenerate with `brew generate-tap-man-completions` after any `cmd_args` change.
  CI verifies sources are not out of date.
- `docs/`: Project documentation, including architecture notes (see `docs/architecture.md`).
- `.gitignore`: Ignores the `cmd/generate-tap-man-completions.rb` hardlink (see dev-cmd above).
- `scripts/run-generate-tap-man-completions.sh`: Helper script to hardlink `dev-cmd/generate-tap-man-completions.rb`
  into the installed tap's `cmd/` and run the command with `--tap=` pointed at the installed tap.
  Syncs generated files back to the development clone for committing, then restores the tap repo
  to a clean state (via `git restore` + `git clean -fd`). Detects when the dev clone and tap repo
  are the same directory (e.g. Copilot sandbox) and skips the sync/restore steps.
  Designed to be run from the development clone. Forwards all arguments to the command.
  Pass `--open-pr` to create a branch, commit, push, and open a PR from the dev clone via `gh`.
  The `--open-pr`, `--no-pull-requests`, and `--no-fork` flags are declared in `cmd_args`
  (visible in `--help`, completions, and man pages) and forwarded to the brew command.
  Cleans up hardlinks on exit. See `docs/architecture.md` § Developer workflow for details.
- `scripts/run-tests.sh`: Helper script to hardlink tap files into `$(brew --repo)` and run `brew tests`.
  Accepts an optional `--only=cmd/<file>[:<line>]` argument to run a specific test.
- `scripts/annotate.sh`: Annotates non-REUSE-compliant files with SPDX headers. Run this
  instead of hand-writing SPDX headers.
- `.githooks/pre-commit`: Pre-commit hook — runs `brew style --fix` (Ruby + shell), actionlint, and REUSE compliance.
- `.githooks/post-merge`: Post-merge hook — re-creates the `cmd/` hardlink for `dev-cmd/` after `git pull` (merge).
- `.githooks/post-rewrite`: Post-rewrite hook — re-creates the hardlink after `git pull --rebase` or `git rebase`.
- `.github/workflows/ci.yml`: CI — runs `brew style --changed` (Ruby + shell) and `brew tests`.
- `.github/workflows/autogenerated-files.yml`: CI — checks that completions and man page sources
  are up to date (triggers on PRs/pushes touching `cmd/`, `dev-cmd/`, `completions/`, or `manpages/`).
- `.github/workflows/actionlint.yml`: CI — runs `actionlint` and `zizmor` code scanning.
- `.github/workflows/sync-shared-config.yml`: Syncs shared configuration files from upstream
  Homebrew repositories. Uses `yq` for YAML mutations with post-mutation assertions.
  Requires a GitHub App token to push workflow files — see `docs/architecture.md` § CI setup.
- `.mcp.json`: Claude Code project-level MCP server config (used when running `claude` locally).
- `.vscode/mcp.json`: VS Code MCP server config (used in VS Code with Copilot locally).
- `.github/workflows/copilot-setup-steps.yml`: Setup steps for GitHub Copilot coding agent — installs Homebrew and caches bundler gems.

## MCP Server Configuration

The Homebrew MCP Server (`brew mcp-server`) provides Homebrew tools to AI coding agents.
It is configured differently per client:

| Client | Config location |
|--------|-----------------|
| Claude Code | `.mcp.json` (in this repo) |
| VS Code | `.vscode/mcp.json` (in this repo) |
| GitHub Copilot coding agent | Repository Settings → Copilot → Coding agent → MCP configuration |

For GitHub Copilot coding agent, add the following JSON in the repository's Copilot settings.
`brew` is available (but not on `PATH`) because `.github/workflows/copilot-setup-steps.yml` runs `Homebrew/actions/setup-homebrew`.

```json
{
  "mcpServers": {
    "Homebrew": {
      "type": "local",
      "command": "/home/linuxbrew/.linuxbrew/bin/brew",
      "args": ["mcp-server"],
      "tools": ["*"]
    }
  }
}
```

## Key Guidelines

1. Follow Ruby and Bash best practices and idiomatic patterns.
2. Maintain existing code structure and organisation.
3. Write unit tests for new functionality.
4. Document public APIs and complex logic.
5. Suggest changes to the `docs/` folder when appropriate (create it if needed).
6. Follow software principles such as DRY and YAGNI.
7. Keep diffs as minimal as possible.
8. Prefer shelling out via `HOMEBREW_BREW_FILE` instead of requiring `cmd/` or `dev-cmd` when composing brew commands.
9. Inline new or existing methods as methods or local variables unless they are reused 2+ times or needed for unit tests.
10. Use Sorbet `sig` type signatures and `# typed: strict` for all non-spec Ruby files.
11. Never use `# typed: strict` in RSpec `*_spec.rb` files.
12. Named arguments in `AbstractCommand` subclasses: use `named_args :installed_cask, min: 1` for cask commands that operate on installed casks — this provides tab completion via Homebrew's `__brew_complete_installed_casks` (which lists Caskroom directories, without loading cask definitions) and works for casks that have been removed from all taps. The `:installed_cask` type only affects completion hints and usage banners; it does not validate cask names against tapped sources at parse time.
13. `include SystemCommand::Mixin` (top-level constant, not `Homebrew::SystemCommand::Mixin`).
14. All implementations must be compatible with macOS (see macOS Compatibility section above). The agent runs on Ubuntu, but users run this tap on macOS. Avoid GNU-only CLI extensions; use POSIX/BSD-compatible syntax.
15. Do **not** hand-write SPDX/REUSE headers. Instead run `scripts/annotate.sh` so that formatting and copyright info are standardised throughout the repo. `annotate.sh` special-cases all generated files under `completions/` and man page (`.1`, `.1.md`) files to use `.license` sidecars (`--force-dot-license`) so their generated content is never altered.
16. **Output ordering**: `ohai`/`oh1` write to `$stdout`; `opoo`/`ofail` write to `$stderr`. These streams may interleave when both are used in the same code path (e.g., `ohai` inside a loop followed by an `opoo`). When multiple related warning lines must stay together, emit them as a single `opoo <<~EOS … EOS` call rather than separate `opoo` calls, so both lines go to stderr atomically.
17. **Man pages**: `brew generate-tap-man-completions` generates Ronn man page sources (`manpages/brew-<command>.1.md`) and compiled roff (`manpages/brew-<command>.1`) from each command's `cmd_args`. Regenerate after any `cmd_args` change; CI verifies sources are current.
