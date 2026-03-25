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

### Security notice

Removing quarantine bypasses macOS's Gatekeeper for the affected apps.
Please use this command only with software you trust.

---

## License

GPL-3.0-or-later and [BSD-2-Clause](LICENSE) Copyright 2006 Todd Schulman
