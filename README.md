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
their installed `.app` bundles.

### Usage

```sh
brew purge-quarantine <cask> [<cask> ...]
```

### Arguments

| Argument / Flag | Description |
|---|---|
| `<cask>` | One or more Homebrew-installed cask tokens (required) |
| `--debug` | Print debug output (inherited from Homebrew global flags) |
| `--verbose` | Make some output more verbose (inherited from Homebrew global flags) |

### Examples

Disable Gatekeeper for a single cask:

```sh
brew purge-quarantine some-app
```

Disable Gatekeeper for multiple casks:

```sh
brew purge-quarantine app-one app-two app-three
```

With debug output:

```sh
brew purge-quarantine --debug some-app
```

### Security notice

Removing quarantine bypasses macOS Gatekeeper for the affected app bundles.
Only use this command with software you trust.

---

## License

[MIT](LICENSE)
