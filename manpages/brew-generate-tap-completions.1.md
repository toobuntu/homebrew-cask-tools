brew-generate-tap-completions(1) -- Generate shell completions and man pages for a tap's commands
=================================================================================================

## SYNOPSIS

`brew` `generate-tap-completions` [`--tap=`<tap>] [`--no-exit-code`]

## DESCRIPTION

Generate shell completions and man pages for a tap's commands.

Reads each `*.rb` file in `cmd/` and writes Bash, ZSH, and Fish completion
files into `completions/`, and Ronn man page sources into `manpages/`. The tap
is auto-detected from the location of this command file. Use `--tap` to override.
Compile man page sources to roff with `scripts/generate-man-pages.sh`.

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

