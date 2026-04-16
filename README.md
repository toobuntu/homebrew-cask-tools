<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# homebrew-cask-tools

A Homebrew tap providing external commands for working with casks and formulae.

## Table of Contents

- [Install](#install)
- [Commands](#commands)
  - [`brew cask-extract`](#brew-cask-extract)
  - [`brew purge-quarantine`](#brew-purge-quarantine)
  - [`brew man`](#brew-man)
  - [`brew generate-tap-man-completions`](#brew-generate-tap-man-completions-developer-only) (developer only)
- [License](#license)

## Install

```sh
brew tap toobuntu/cask-tools
```

## Commands

### `brew cask-extract`

Extract a cask from Homebrew's git history into a personal tap, optionally adding
a postflight block to remove macOS's quarantine extended attribute.

#### Usage

```sh
brew cask-extract [--no-quarantine] [--version=<version>] [--unversioned] [--force] [--no-shard] <cask> <tap>
```

#### Arguments

| Argument / Flag | Description |
|---|---|
| `<cask>` | The cask token to extract (required). Use `user/repo/cask` form to extract from a non-default tap. |
| `<tap>` | The destination tap, e.g. `user/tap` (required) |
| `--version=<version>` | Extract a specific version from git history |
| `--no-quarantine` | Add a `postflight` block that removes `com.apple.quarantine` |
| `--unversioned` | Copy without adding a version suffix to the cask name |
| `--force` | Overwrite the destination file if it already exists |
| `--no-shard` | Write to a flat `Casks/` directory instead of a sharded one |

#### Examples

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

#### How it works

1. **Delegates to `brew extract --cask`** when the installed Homebrew supports it,
   passing all relevant flags through.
2. **Falls back to manual extraction** by searching the source tap's git history for
   the cask file when `brew extract --cask` is not available.
3. **Post-processes the extracted file** when `--no-quarantine` is supplied:
   - Parses `app "Foo.app"` stanzas from the cask content.
   - Inserts a `postflight` block that runs `/usr/bin/xattr -dr com.apple.quarantine`
     on each app bundle.
   - Prints a security warning reminding you to verify the software.

#### Security notice

Using `--no-quarantine` bypasses macOS Gatekeeper for the installed app.
Only use this flag with software you trust.

---

### `brew purge-quarantine`

Disables macOS's Gatekeeper for the named casks by removing the
`com.apple.quarantine` and `com.apple.provenance` extended attributes from
their installed `.app` and plugin bundles (for example: `.component`, `.colorpicker`, `.saver`, `.vst3`).

#### Usage

```sh
brew purge-quarantine <cask> [<cask> ...]
```

#### Security notice

Removing quarantine bypasses macOS's Gatekeeper for the affected apps.
Please use this command only with software you trust.

---

### `brew man`

Homebrew kegs (especially keg-only formulae like `libressl`) are
not on the default `MANPATH`, so `man` does not reliably find their pages. When
multiple providers ship the same page name, `man` silently returns the first
match. `brew man` resolves man pages **by formula** and makes ambiguity explicit.

#### Usage

```
brew man [<section>] <formula> [<manpage>]
brew man --find [--interactive] <manpage>
brew man --list [--interactive] <formula>
```

| Use case | Syntax |
|---|---|
| View a formula's default page | `brew man openssl@3` |
| View a specific page within a formula | `brew man openssl@3 openssl.1ssl` |
| Restrict to a man section | `brew man 1 libressl openssl` |
| Find all providers of a page | `brew man --find openssl` |
| Pick from providers interactively | `brew man --find --interactive openssl` |
| List all pages a formula provides | `brew man --list libressl` |
| Pick from all formula pages | `brew man --list --interactive libressl` |
| Render as HTML in a browser | `brew man --html curl` |

When no `<manpage>` is given, `brew man <formula>` defaults to the formula name.
If no man page matches the formula name, the formula's executables are tried as
fallback — for example, `brew man libressl` resolves to `openssl(1)` because
`libressl` ships a `bin/openssl` executable.

#### Arguments and flags

| Argument / Flag | Description |
|---|---|
| `[<section>]` | Optional man section number (e.g. `1`, `3`) before the formula name |
| `<formula>` | The installed formula whose keg to search (default mode) |
| `[<manpage>]` | Man page name to look up (defaults to `<formula>`) |
| `--html`, `-H` | Render the man page as HTML and open it in a browser (respects `HOMEBREW_BROWSER` or `BROWSER`) |
| `--find`, `-f` | Find all installed formulae that provide the named man page |
| `--list`, `-l` | List every man page provided by the named formula |
| `--interactive`, `-i` | Present a numbered list for interactive selection (requires `--find` or `--list`) |
| `--debug`, `-d` | Show detailed search steps for troubleshooting |

#### Examples

Open `openssl(1)` from the `libressl` formula (resolved via binary fallback):

```sh
brew man libressl
```

Open `curl(1)` from the `curl` formula's keg (man page defaults to formula name):

```sh
brew man curl
```

Open `openssl(1)` from the `openssl@3` formula's keg:

```sh
brew man openssl@3 openssl
```

List every location where `openssl(1)` is found (system, libressl, openssl@3):

```sh
brew man --find openssl
```

List all man pages that the `libressl` formula provides:

```sh
brew man --list libressl
```

Interactively choose which copy of `openssl(1)` to view:

```sh
brew man --find --interactive openssl
```

Render the `curl` man page as HTML and open in a browser:

```sh
brew man --html curl
```

---

### `brew generate-tap-man-completions` (developer only)

A developer-only command that generates Bash, ZSH, and Fish shell completions and
Ronn man pages for all user-facing commands in this tap. Requires `HOMEBREW_DEVELOPER=1`.
Primarily used by maintainers to keep the pre-committed `completions/`
and `manpages/` directories up to date.

#### Setup

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

#### Usage

```sh
HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions [--tap=<user>/<repo>] [--no-exit-code]
```

## License

GPL-3.0-or-later OR BSD-2-Clause Copyright 2026 Todd Schulman
