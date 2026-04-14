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

Explicit formula (always deterministic — looks up from a specific formula's keg):

```sh
brew man [--html] <formula> [<manpage>]
```

Single manpage argument (searches all formula kegs and system paths):

```sh
brew man <manpage>
brew man --list <manpage>
brew man --interactive <manpage>
```

### Arguments and flags

| Argument / Flag | Description |
|---|---|
| `<formula>` | The installed formula whose keg to search (explicit mode) |
| `[<manpage>]` | Man page name to look up (defaults to `<formula>`) |
| `<manpage>` | Man page name to search for (single-arg / list / interactive mode) |
| `--html`, `-H` | Render the man page as HTML and open it in a browser (respects `HOMEBREW_BROWSER` or `BROWSER`) |
| `--list`, `-l` | List all locations where the named man page is found |
| `--interactive`, `-i` | Interactively resolve ambiguity when multiple copies are found |

### Behavior

| Invocation | Behavior |
|---|---|
| `brew man <manpage>` | Search all kegs + system. If one match: open it. If multiple: exit with actionable error. |
| `brew man --interactive <manpage>` | Same search; if multiple matches, prompts for selection. |
| `brew man <formula> <manpage>` | Always opens from the named formula's keg (bypasses ambiguity). |
| `brew man --list <manpage>` | List every location where the page is found. |

### Examples

When `libressl` (keg-only) and `openssl@3` both ship an `openssl(1)` page,
`brew man openssl` exits with an actionable error:

```console
$ brew man openssl
Error: multiple matches found for 'openssl':

  system:    /usr/share/man/man1/openssl.1
  libressl:  /opt/homebrew/opt/libressl/share/man/man1/openssl.1
  openssl@3: /opt/homebrew/opt/openssl@3/share/man/man1/openssl.1

Use one of:
  brew man <formula> openssl
  brew man --interactive openssl
  brew man --list openssl
```

Open the man page for `openssl` from the `libressl` keg explicitly:

```sh
brew man libressl openssl
```

Open `openssl(1)` from the `openssl@3` keg explicitly:

```sh
brew man openssl@3 openssl
```

Let `brew man` search automatically when there is only one match:

```sh
brew man gitk
```

Interactively choose which copy of `openssl(1)` to view:

```sh
brew man --interactive openssl
```

Render the `curl` man page as HTML and open in a browser:

```sh
brew man --html curl
```

List every location where the `openssl` man page is found:

```sh
brew man --list openssl
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
