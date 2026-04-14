brew-man(1) -- Display a man page bundled with an installed formula
===================================================================

## SYNOPSIS

`brew` `man` [<options>] <formula> [<manpage>]

## DESCRIPTION

Display a man page bundled with an installed formula.

Homebrew kegs are not on the default `MANPATH`, so `man` does not find
their pages. When multiple providers ship the same page name, `man`
silently returns the first match. This command resolves man pages
**by formula** and makes ambiguity visible.

In normal mode, shows the man page for <manpage> (defaulting to the
formula name) from <formula>'s keg using the system `man` viewer.
With `--html`, renders the man page via `mandoc -T html` and opens it
in a browser.

In `--list` mode, shows all locations where a given man page is found
(both system paths and Homebrew formula kegs).

In `--select` mode, presents a numbered list to interactively choose
which copy of a man page to view.

## OPTIONS

`-d`, `--debug`

: Display any debugging information.

`-q`, `--quiet`

: Make some output more quiet.

`-v`, `--verbose`

: Make some output more verbose.

`-h`, `--help`

: Show this message.

`-H`, `--html`

: Render the man page as HTML and open it in a browser.

`--list`

: List all locations where the named man page is found.

`--select`

: Interactively select which copy of the man page to view.

