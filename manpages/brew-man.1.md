brew-man(1) -- Display a man page bundled with an installed formula
===================================================================

## SYNOPSIS

`brew` `man` [<options>] <formula> [<manpage>]
`man` (`--list`|`--interactive`) <manpage>

## DESCRIPTION

Display a man page bundled with an installed formula.

Homebrew kegs (especially keg-only formulae) are not on the default
`MANPATH`, so `man` does not reliably find their pages. When multiple
providers ship the same page name, `man` silently returns the first
match. This command resolves man pages **by formula** and makes
ambiguity explicit.

By default, `brew man <formula>` resolves man pages within the
specified formula only. The optional <manpage> argument defaults to
the formula name. With `--html`, renders the man page via
`mandoc -T html` and opens it in a browser (respecting
`HOMEBREW_BROWSER` or `BROWSER`).

Use `--list` or `--interactive` to search across system and other
Homebrew formulae. With `--list`, shows all locations where a given
man page is found (both system paths and Homebrew formula kegs).

With `--interactive`, presents a numbered list with origin labels
to interactively select which copy of a man page to view.

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

: Render the man page as HTML and open it in a browser (respects `HOMEBREW_BROWSER` or `BROWSER`).

`-l`, `--list`

: List all locations where the named man page is found.

`-i`, `--interactive`

: Interactively resolve ambiguity when multiple copies of a man page are found.

