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

Homebrew does not load `dev-cmd/` from third-party taps automatically.
To use this command locally, create a symlink:

```sh
ln -s ../dev-cmd/generate-tap-man-completions.rb cmd/generate-tap-man-completions.rb
```

The symlink is already listed in `.gitignore`.

### Usage

```sh
HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions [--tap=<user>/<repo>] [--no-exit-code]
```

---

## License

GPL-3.0-or-later or [BSD-2-Clause](LICENSE) Copyright 2026 Todd Schulman
