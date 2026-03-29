# CLAUDE.md

This file provides technical notes for AI agents and contributors working in this repository.

## Repository overview

This is a Homebrew external tap hosting `brew purge-quarantine`, a command that removes
macOS quarantine (`com.apple.quarantine`) and provenance (`com.apple.provenance`) extended
attributes from installed cask bundles to satisfy Gatekeeper.

The command is implemented as a single Ruby file at `cmd/purge-quarantine.rb` using
Homebrew's `AbstractCommand` infrastructure.

## Commands

```sh
# Lint (must pass before committing)
brew style --fix --changed

# Type-check
brew typecheck

# Run tests (requires hardlinks — use the script instead of running directly)
scripts/run-tests.sh

# Run a single test example
scripts/run-tests.sh --only=cmd/purge-quarantine:LINE
```

## Architecture: tiered bundle discovery

`quarantinable_bundles_for` uses seven tiers in order, stopping at the first non-empty result:

| Tier | Method | When it works |
|------|--------|---------------|
| 1 | Caskroom glob | Standard DMG casks with bundles staged in `HOMEBREW_CASKROOM/<token>/<version>/` |
| 2 | `bundles_from_cask_definition` | Cask still tapped; reads `Moved` targets and `uninstall.delete` paths via CaskLoader |
| 3 | `bundles_from_cask_metadata` | Cask removed from taps; `.metadata` dir remains in Caskroom |
| 4 | `bundles_from_lsregister` | App registered with macOS Launch Services; dump cached for 5 min |
| 5 | `bundles_from_pkgutil_receipts` | Pkg still registered with macOS; `pkgutil --pkg-info` gives install prefix |
| 6 | `bundles_from_pkgutil_bom` | `.pkg` file still staged in Caskroom; BOM gives bundle names to search |
| 7 | `bundles_from_mdfind` | Spotlight has indexed the bundle; last resort |

Tiers 4–7 need **candidate bundle names** (from `candidate_bundle_names`) to target their
search. This helper extracts names from `.metadata` JSON `app` stanzas, `uninstall.delete`
paths, and `pkgutil` receipt file lists.

### Common install directories

`install_dirs(cask_dir)` returns `[configured appdir, /Applications, ~/Applications]`
(deduped). The configured appdir is read from `.metadata/config.json` if present.

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
- `named_args min: 1` — not `:cask` (crashes on deprecated casks) or `:token` (silently empty).
- `rescue StandardError => e` not `rescue => e` (bare rescue catches `SystemExit`/`Interrupt`).
- `T.unsafe()` for Sorbet strict typing with dynamic Cask artifact APIs.
- `include SystemCommand::Mixin` (top-level, not `Homebrew::SystemCommand::Mixin`).

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
