<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# homebrew-cask-tools

A Homebrew tap providing external commands for working with casks.

## Install

```sh
brew tap toobuntu/cask-tools
```

---

## `brew purge-quarantine`

Disables macOS's Gatekeeper for the named casks by removing the
`com.apple.quarantine` and `com.apple.provenance` extended attributes from
their installed `.app` and plugin bundles (for example: `.component`, `.colorpicker`, `.saver`, `.vst3`).

### Usage

```sh
brew purge-quarantine <cask> [<cask> ...]
```

### Security notice

Removing quarantine bypasses macOS's Gatekeeper for the affected apps.
Please use this command only with software you trust.

---

## `brew generate-tap-man-completions` (developer only)

A developer-only command that generates Bash, ZSH, and Fish shell completions and
Ronn man pages for all user-facing commands in this tap. Requires `HOMEBREW_DEVELOPER=1`.
Primarily used by maintainers to keep the pre-committed `completions/`
and `manpages/` directories up to date.

### Setup

The command is available automatically in the taproom after `brew tap toobuntu/cask-tools`.
No additional setup is required to run `brew generate-tap-man-completions`.

To enable code-quality pre-commit linting for contributors:

```sh
git config core.hooksPath .githooks
```

### Usage

```sh
HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions [--tap=<user>/<repo>] [--no-exit-code]
```

---

## License

GPL-3.0-or-later OR BSD-2-Clause Copyright 2026 Todd Schulman
