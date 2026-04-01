brew-cask-extract(1) -- Extract a cask from Homebrew's git history into a personal tap
======================================================================================

## SYNOPSIS

`brew` `cask-extract` [<options>] <cask> <tap>

## DESCRIPTION

Extract a cask from Homebrew's git history into a personal tap.
Optionally add a postflight block to remove macOS's quarantine
extended attribute so un-notarized apps can launch without
Gatekeeper blocking them.

## OPTIONS

`-d`, `--debug`

: Display any debugging information.

`-q`, `--quiet`

: Make some output more quiet.

`-v`, `--verbose`

: Make some output more verbose.

`-h`, `--help`

: Show this message.

`--version`

: Extract the cask at this specific version from git history.

`--no-quarantine`

: Add a `postflight` block that removes the quarantine xattr.

`--unversioned`

: Copy without adding a version suffix to the cask token.

`--force`

: Overwrite the destination file if it already exists.

`--no-shard`

: Write to a flat `Casks/` directory instead of a sharded one.

