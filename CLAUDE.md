<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# CLAUDE.md

This file provides technical notes for AI agents and contributors working in this repository.

## Repository overview

This is a Homebrew external tap hosting `brew purge-quarantine` and `brew generate-tap-man-completions`.
`brew purge-quarantine` removes macOS quarantine (`com.apple.quarantine`) and provenance
(`com.apple.provenance`) extended attributes from installed cask bundles to satisfy Gatekeeper.
`brew generate-tap-man-completions` is a developer-only command (requires `HOMEBREW_DEVELOPER=1`)
that generates shell completions and Ronn man page sources for commands in `cmd/`.

Commands are implemented as Ruby files in `cmd/` (user-facing) and `dev-cmd/` (developer-only)
using Homebrew's `AbstractCommand` infrastructure. Since Homebrew does not support external
`dev-cmd/` in third-party taps, a local symlink from `cmd/` to `dev-cmd/` is needed for
development use (the symlink is gitignored). CI hardlinks the file directly.

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
scripts/run-tests.sh --only=cmd/generate-tap-man-completions

# Regenerate shell completions, man page sources, and compiled roff after any cmd_args change
brew generate-tap-man-completions
```

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
- `named_args min: 1` — required for `purge-quarantine` because deprecated/removed casks are a primary use case; `:installed_cask` validates against tapped sources at parse time and must not be used.
- `rescue => e` (idiomatic Ruby; equivalent to `rescue StandardError => e`). Never use bare `rescue Exception` — that catches `SystemExit` and `Interrupt`.
- `T.unsafe()` for Sorbet strict typing with dynamic Cask artifact APIs.
- `include SystemCommand::Mixin` (top-level, not `Homebrew::SystemCommand::Mixin`).
- **Output ordering**: `ohai`/`oh1` write to `$stdout`; `opoo`/`ofail` write to `$stderr`. When mixed in the same code path the two streams can interleave (system commands run in-order, but Ruby buffers stdout and stderr independently). Emit multiple related warning lines as one `opoo <<~EOS … EOS` block so they reach stderr atomically and cannot be split by stdout output.
- **RuboCop disables**: Homebrew's custom `Cop/DisableComment` cop requires a comment on the line immediately above a `# rubocop:disable` line. The inline `--` RuboCop syntax is not accepted.

## macOS compatibility

The Copilot Coding Agent runs on Ubuntu, but this tap targets macOS end-users. All
implementations must be compatible with macOS:

- Use POSIX/BSD-compatible CLI syntax — macOS ships BSD variants of `sed`, `awk`, `find`,
  `xargs`, `date`, `grep`, etc.; GNU extensions are not available by default on macOS.
- Do not rely on Linux-specific paths (`/proc`, `/sys`) or package managers (`apt`, `dpkg`).
- Ruby code that shells out should use commands available on macOS (`xattr`, `pkgutil`, etc.).
- Shell scripts with `#!/bin/sh` must be POSIX-compatible; scripts with `#!/usr/bin/env bash`
  may use bash features but must avoid GNU coreutil extensions.

## REUSE / licensing

Files must carry SPDX headers. Run `scripts/annotate.sh` to annotate non-compliant files.
The `reuse` tool is pre-installed in the Copilot sandbox; do **not** hand-write SPDX headers —
run `scripts/annotate.sh` so that formatting and copyright info are standardised throughout.

`scripts/annotate.sh` special-cases `.fish` completion files and man page files (`.1`, `.1.md`):
because the generator overwrites their content, they use `.license` sidecars created with
`--force-dot-license` rather than inline `#` comment headers.

License texts are committed in `LICENSES/` (populated via `reuse download --all`).

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

