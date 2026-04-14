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

With an explicit <formula> and optional <manpage> (defaulting to the
formula name), always opens that formula's copy using the system `man`
viewer. With `--html`, renders the man page via `mandoc -T html` and
opens it in a browser (respecting `HOMEBREW_BROWSER` or `BROWSER`).

With a single <manpage> argument (no explicit formula), searches all
installed formula kegs and system paths. If exactly one copy is found,
opens it. If multiple copies are found, exits with an actionable error
listing all matches and suggesting next steps.

With `--list`, shows all locations where a given man page is found
(both system paths and Homebrew formula kegs).

With `--interactive`, presents a numbered list to interactively resolve
ambiguity when multiple copies of a man page are found.

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

