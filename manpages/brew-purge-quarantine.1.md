brew-purge-quarantine(1)
========================

## SYNOPSIS

`brew` `purge-quarantine` <cask> [<cask> ...]

## DESCRIPTION

Disables macOS's Gatekeeper for the named casks by removing the
`com.apple.quarantine` and `com.apple.provenance` extended attributes
from their installed macOS bundles (`.app`, `.component`, `.colorPicker`,
`.saver`, `.webplugin`, and other artifact types).

## OPTIONS

`-d`, `--debug`

: Display any debugging information.

`-q`, `--quiet`

: Make some output more quiet.

`-v`, `--verbose`

: Make some output more verbose.

`-h`, `--help`

: Show this message.

