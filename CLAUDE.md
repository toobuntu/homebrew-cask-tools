<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# CLAUDE.md

This file provides technical notes for AI agents and contributors working in this repository.

## Reasoning style

See [`docs/shared-guidelines.md`](docs/shared-guidelines.md#reasoning-style) for the
canonical reasoning style guidelines shared across all agent instruction files.

## Repository overview

This is a Homebrew external tap hosting `brew purge-quarantine`, `brew cask-extract`,
`brew man`, and `brew generate-tap-man-completions`.
`brew purge-quarantine` removes macOS quarantine (`com.apple.quarantine`) and provenance
(`com.apple.provenance`) extended attributes from installed cask bundles to satisfy Gatekeeper.
`brew cask-extract` extracts a cask from Homebrew's git history into a personal tap,
optionally adding a `postflight` block to remove macOS's quarantine extended attribute.
`brew man` displays man pages bundled with installed formulae, resolving pages that are
not on the default `MANPATH` (e.g. keg-only formulae).
`brew generate-tap-man-completions` is a developer-only command (requires `HOMEBREW_DEVELOPER=1`)
that generates shell completions and Ronn man page sources for commands in `cmd/` and `dev-cmd/`.

Commands are implemented as Ruby files in `cmd/` (user-facing) and `dev-cmd/` (developer-only)
using Homebrew's `AbstractCommand` infrastructure. Since Homebrew does not support external
`dev-cmd/` in third-party taps, a local hardlink from `cmd/` to `dev-cmd/` is needed for
development use (the hardlink is gitignored). Symlinks do not work — use a hardlink:

```sh
ln -f dev-cmd/generate-tap-man-completions.rb cmd/generate-tap-man-completions.rb
```

Re-run after any `git pull` that updates `dev-cmd/generate-tap-man-completions.rb`, as git
may recreate the file as a new inode leaving the hardlink stale. CI hardlinks the file directly.

The `.githooks/post-merge` and `.githooks/post-rewrite` hooks automate this re-link after
`git pull` for developers who have `git config core.hooksPath .githooks` set.

## Commands

```sh
# Prefer the Homebrew MCP Server tools for all brew operations in the agent sandbox.
# Use Homebrew/style, Homebrew/typecheck, Homebrew/tests instead of running brew via bash.

# Lint (must pass before committing) — prefer Homebrew/style via MCP
brew style --fix --changed

# Type-check — prefer Homebrew/typecheck via MCP
brew typecheck

# Run all tests (requires hardlinks — use the script instead of running directly)
scripts/run-tests.sh

# Run a specific test file or line
scripts/run-tests.sh --only=cmd/purge-quarantine:LINE
scripts/run-tests.sh --only=cmd/cask-extract
scripts/run-tests.sh --only=cmd/man
scripts/run-tests.sh --only=cmd/generate-tap-man-completions

# Regenerate shell completions, man page sources, and compiled roff after any cmd_args change.
# Run from the development clone; generates into the installed tap repo, then syncs back.
scripts/run-generate-tap-man-completions.sh

# Same, but also commit, push, and open a PR from the dev clone:
scripts/run-generate-tap-man-completions.sh --open-pr
```

### Regenerating completions in the Copilot sandbox

In the Copilot coding agent sandbox, the dev repo and the installed tap are the
**same directory** (symlinked by `setup-homebrew`).
`scripts/run-generate-tap-man-completions.sh` detects this layout and automatically
skips the sync and restore steps that would otherwise fail. You can use it normally:

```sh
scripts/run-generate-tap-man-completions.sh
```

Generated files land directly in the working tree — no sync step is needed.
See `docs/architecture.md` § "Copilot sandbox" for details.

## Architecture: tiered bundle discovery

See [`docs/architecture.md`](docs/architecture.md) for the full architecture
documentation, including the seven-tier bundle discovery strategy and shell
completion details.

## Testing

`brew tests` requires spec and cmd files to be **hardlinked** (not symlinked) into
`$(brew --repo)/Library/Homebrew/`. The script `scripts/run-tests.sh` does this, warns
about concurrent brew commands, and removes the hardlinks in an `EXIT` trap.

In CI (`brew_tests` job in `.github/workflows/ci.yml`) the same hardlink approach is used.

### RSpec design notes

- Avoid `it_behaves_like "parseable arguments"` — the shared example is not registered
  when the spec is loaded in isolation via `--only`.
- Use `let(:tmpdir) { Pathname(Dir.mktmpdir) }` + `after { FileUtils.rm_rf(tmpdir) }`,
  not `around`/`@tmpdir` (scoping issue with RSpec).
- Stub `lsregister_dump` directly (not `system_command` with `LSREGISTER_PATH`) to avoid
  interference from a cached dump at `HOMEBREW_CACHE/purge-quarantine/lsregister.dump`.
- Formula classes created in specs may be frozen; prefer instance-level stubs.
- `# typed: true` (not `strict`) in `*_spec.rb` files.

## Homebrew-specific conventions

- `args.verbose?` not `verbose?` (not an instance method on `AbstractCommand` subclasses).
- `Cask::Artifact::Moved` (not `::App`) covers all installable artifact types with a target.
- `named_args :installed_cask, min: 1` — used for `purge-quarantine` to provide tab completion for installed cask names (via Homebrew's `__brew_complete_installed_casks`, which lists Caskroom directories without loading cask definitions). Works correctly for deprecated/removed casks.
- `rescue => e` (idiomatic Ruby; equivalent to `rescue StandardError => e`). Never use bare `rescue Exception` — that catches `SystemExit` and `Interrupt`.
- `T.unsafe()` for Sorbet strict typing with dynamic Cask artifact APIs.
- `include SystemCommand::Mixin` (top-level, not `Homebrew::SystemCommand::Mixin`).
- **Output ordering**: `ohai`/`oh1` write to `$stdout`; `opoo`/`ofail` write to `$stderr`. When mixed in the same code path the two streams can interleave (system commands run in-order, but Ruby buffers stdout and stderr independently). Emit multiple related warning lines as one `opoo <<~EOS … EOS` block so they reach stderr atomically and cannot be split by stdout output.
- **RuboCop disables**: Homebrew's custom `Cop/DisableComment` cop requires a comment on the line immediately above a `# rubocop:disable` line. The inline `--` RuboCop syntax is not accepted.

## macOS compatibility

See [`docs/shared-guidelines.md`](docs/shared-guidelines.md#macos-compatibility) for the
full macOS compatibility guidelines shared across all agent instruction files.

## REUSE / licensing

See [`docs/shared-guidelines.md`](docs/shared-guidelines.md#reuse--licensing) for the
full REUSE/licensing guidelines shared across all agent instruction files.

## Man pages

Man page sources (`manpages/brew-<command>.1.md`, Ronn format) and compiled roff (`manpages/brew-<command>.1`)
are both generated by `brew generate-tap-man-completions`.
The generator uses `CLI::Parser.from_cmd_path` to extract `usage_banner_text` and `processed_options`
from each command's `cmd_args` block — the same approach as Homebrew's `manpages.rb`.
Roff compilation uses Homebrew's internal Ronn converter (`manpages/parser/ronn` +
`manpages/converter/roff`) inline in the command itself, with the `man` bundler gem group (`kramdown`).

Regenerate man page sources and roff after any `cmd_args` change by running `brew generate-tap-man-completions`. CI verifies sources are current.

Note: `Homebrew.install_bundler_gems!` is restricted to `dev-cmd/` by Homebrew's Rubocop rules,
so a `# rubocop:disable Homebrew/InstallBundlerGems` with a preceding clarifying comment is used
in the command to allow inline roff compilation.

For shell completion architecture details, see [`docs/architecture.md`](docs/architecture.md).

