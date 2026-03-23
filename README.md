# homebrew-cask-tools

A Homebrew tap providing external commands for working with casks.

## Install

```sh
brew tap toobuntu/cask-tools
```

---

## `brew purge-quarantine`

Remove macOS quarantine and provenance extended attributes from installed cask
app bundles. Useful for apps that were downloaded with Gatekeeper quarantine
flags that you have already verified as safe.

### Usage

```sh
brew purge-quarantine <cask> [<cask> ...]
```

### Arguments

| Argument / Flag | Description |
|---|---|
| `<cask>` | One or more installed cask tokens (required) |
| `--debug` | Print debug output (inherited from Homebrew global flags) |
| `--verbose` | Make some output more verbose (inherited from Homebrew global flags) |

### Examples

Remove quarantine from a single cask:

```sh
brew purge-quarantine some-app
```

Remove quarantine from multiple casks:

```sh
brew purge-quarantine app-one app-two app-three
```

With debug output:

```sh
brew purge-quarantine --debug some-app
```

### How it works

1. Resolves the Caskroom path using the `HOMEBREW_CASKROOM` constant.
2. Finds `.app` bundles at `#{HOMEBREW_CASKROOM}/#{cask}/*/*.app`.
3. Resolves symlinks to real paths using `Pathname#realpath`.
4. Validates each app bundle by checking for `Contents/Info.plist`.
5. Removes the `com.apple.quarantine` and `com.apple.provenance` extended
   attributes using `/usr/bin/xattr -d -r`.
6. Verifies removal by inspecting xattrs after each operation.

### Security notice

Removing quarantine bypasses macOS Gatekeeper for the affected app bundles.
Only use this command with software you trust.

---

## License

[MIT](LICENSE)
