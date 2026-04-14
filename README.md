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

## `brew cask-extract`

Extract a cask from Homebrew's git history into a personal tap, optionally adding
a postflight block to remove macOS's quarantine extended attribute.

### Usage

```sh
brew cask-extract [--no-quarantine] [--version=<version>] [--unversioned] [--force] [--no-shard] <cask> <tap>
```

### Arguments

| Argument / Flag | Description |
|---|---|
| `<cask>` | The cask token to extract (required). Use `user/repo/cask` form to extract from a non-default tap. |
| `<tap>` | The destination tap, e.g. `user/tap` (required) |
| `--version=<version>` | Extract a specific version from git history |
| `--no-quarantine` | Add a `postflight` block that removes `com.apple.quarantine` |
| `--unversioned` | Copy without adding a version suffix to the cask name |
| `--force` | Overwrite the destination file if it already exists |
| `--no-shard` | Write to a flat `Casks/` directory instead of a sharded one |

### Examples

Extract the `iterm2` cask to your personal tap:

```sh
brew cask-extract iterm2 user/my-tap
```

Extract an un-notarized cask and strip Gatekeeper's quarantine attribute on install:

```sh
brew cask-extract --no-quarantine silverlock user/old-casks
```

Extract a specific historical version:

```sh
brew cask-extract --version=3.4.0 iterm2 user/my-tap
```

Extract a cask from a non-default tap (e.g. `homebrew/cask-versions`):

```sh
brew cask-extract homebrew/cask-versions/firefox user/my-tap
```

### How it works

1. **Delegates to `brew extract --cask`** when the installed Homebrew supports it,
   passing all relevant flags through.
2. **Falls back to manual extraction** by searching the source tap's git history for
   the cask file when `brew extract --cask` is not available.
3. **Post-processes the extracted file** when `--no-quarantine` is supplied:
   - Parses `app "Foo.app"` stanzas from the cask content.
   - Inserts a `postflight` block that runs `/usr/bin/xattr -dr com.apple.quarantine`
     on each app bundle.
   - Prints a security warning reminding you to verify the software.

### Security notice

Using `--no-quarantine` bypasses macOS Gatekeeper for the installed app.
Only use this flag with software you trust.

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

## `brew man`

Display a man page bundled with an installed formula.

Homebrew kegs (especially keg-only formulae) are not on the default `MANPATH`,
so `man` does not reliably find their pages. When multiple providers ship the
same page name, `man` silently returns the first match. This command resolves
man pages **by formula** and makes ambiguity explicit.

### Usage

```
brew man [--html] <formula> [<manpage>]
brew man --list <manpage>
brew man --interactive <manpage>
```

By default, `brew man <formula>` resolves man pages within the specified
formula only. Use `--list` or `--interactive` to search across system and
other Homebrew formulae.

### Arguments and flags

| Argument / Flag | Description |
|---|---|
| `<formula>` | The installed formula whose keg to search (default mode) |
| `[<manpage>]` | Man page name to look up (defaults to `<formula>`) |
| `<manpage>` | Man page name to search for (`--list` / `--interactive` mode) |
| `--html`, `-H` | Render the man page as HTML and open it in a browser (respects `HOMEBREW_BROWSER` or `BROWSER`) |
| `--list`, `-l` | List all locations where the named man page is found |
| `--interactive`, `-i` | Present a numbered list with origin labels for interactive selection |

### Behavior

| Mode | Scope | Behavior |
|---|---|---|
| `brew man <formula>` | Formula-scoped | Opens `<formula>(1)` from the named formula's keg |
| `brew man <formula> <manpage>` | Formula-scoped | Opens `<manpage>(1)` from the named formula's keg |
| `brew man --list <manpage>` | Global | Lists every location (system + all formula kegs) where the page is found |
| `brew man --interactive <manpage>` | Global | Presents a numbered list with origin labels for interactive selection |

### Examples

Open `openssl(1)` from the `libressl` (keg-only) formula's keg:

```sh
brew man libressl openssl
```

Open `openssl(1)` from the `openssl@3` formula's keg:

```sh
brew man openssl@3 openssl
```

Open `curl(1)` from the `curl` formula's keg (man page defaults to formula name):

```sh
brew man curl
```

List every location where `openssl(1)` is found (system, libressl, openssl@3):

```sh
brew man --list openssl
```

Interactively choose which copy of `openssl(1)` to view:

```sh
brew man --interactive openssl
```

Render the `curl` man page as HTML and open in a browser:

```sh
brew man --html curl
```

---

## `brew generate-tap-man-completions` (developer only)

A developer-only command that generates Bash, ZSH, and Fish shell completions and
Ronn man pages for all user-facing commands in this tap. Requires `HOMEBREW_DEVELOPER=1`.
Primarily used by maintainers to keep the pre-committed `completions/`
and `manpages/` directories up to date.

### Setup

Homebrew does not load `dev-cmd/` from third-party taps automatically.
To use this command locally, create a hardlink:

```sh
ln -f dev-cmd/generate-tap-man-completions.rb cmd/generate-tap-man-completions.rb
```

The hardlink is listed in `.gitignore`. To automate re-linking after `git pull`,
enable the included git hooks once:

```sh
git config core.hooksPath .githooks
```

With hooks enabled, `.githooks/post-merge` and `.githooks/post-rewrite` silently
re-create the hardlink after every `git pull` (merge or rebase mode).

### Usage

```sh
HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions [--tap=<user>/<repo>] [--no-exit-code]
```

---

## License

GPL-3.0-or-later OR BSD-2-Clause Copyright 2026 Todd Schulman
