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
| `<cask>` | The cask token to extract (required) |
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

## License

[MIT](LICENSE)
