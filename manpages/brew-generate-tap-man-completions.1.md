brew-generate-tap-man-completions(1) -- Generate shell completions and man pages for a tap's commands
=====================================================================================================

## SYNOPSIS

`brew` `generate-tap-man-completions` [`--tap=`<tap>] [`--no-exit-code`] [`--open-pr`] [`--no-pull-requests`] [`--no-fork`]

## DESCRIPTION

Generate shell completions and man pages for a tap's commands.

Reads each `*.rb` file in `cmd/` and `dev-cmd/` and writes Bash, ZSH, and
Fish completion files into `completions/`, and Ronn man page sources (`.1.md`)
and compiled roff (`.1`) into `manpages/`. Stale files for removed commands are
cleaned up automatically. The tap is auto-detected from the location of this
command file. Use `--tap` to override.

Exits non-zero when no files change (like `git diff --exit-code`). This is the
same convention used by Homebrew's `generate-man-completions`. Pass
`--no-exit-code` to always exit 0.

Pass `--verbose` for a summary of what was processed (commands found, files
written/skipped, stale files removed). Pass `--debug` for detailed diagnostics
about tap resolution, command discovery, and per-file write decisions.

## OPTIONS

`-d`, `--debug`

: Display any debugging information.

`-q`, `--quiet`

: Make some output more quiet.

`-v`, `--verbose`

: Make some output more verbose.

`-h`, `--help`

: Show this message.

`--tap`

: Generate completions for <tap> (default: auto-detected from command location).

`--no-exit-code`

: Exit with code 0 even if no changes were made.

`--open-pr`

: Check for duplicate pull requests before allowing a PR to be opened.

`--no-pull-requests`

: Do not check for duplicate pull requests.

`--no-fork`

: Don't try to fork the repository.

