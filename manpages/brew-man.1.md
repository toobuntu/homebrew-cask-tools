brew-man(1) -- Display a man page bundled with an installed formula
===================================================================

## SYNOPSIS

`brew` `man` [<options>] [<section>] <formula> [<manpage>]

`brew` `man` `--find` [<options>] <manpage>

`brew` `man` `--list` [`--interactive`] [<options>] <formula>

## DESCRIPTION

Display a man page bundled with an installed formula.

Homebrew kegs (especially keg-only formulae) are not on the default
`MANPATH`, so `man` does not reliably find their pages. When multiple
providers ship the same page name, `man` silently returns the first
match. This command resolves man pages **by formula** and makes
ambiguity explicit.

By default, `brew man <formula>` resolves man pages within the
specified formula only. The optional <manpage> argument defaults to
the formula name; when the formula name has no man page, the
formula's executables are tried as fallback (e.g. `brew man libressl`
finds `openssl(1)`). An optional <section> number (e.g. `1`, `3`)
before the formula name restricts the search to that man section.
With `--html`, renders the man page via `mandoc -T html` and opens it
in a browser (respecting `HOMEBREW_BROWSER` or `BROWSER`).

Use `--find` to search across all installed formulae and the system
for a man page by name. Shows all locations where a man page name is
found. Formulae that provide a binary matching the page name are
also included.

Use `--list` to list every man page an installed formula provides.
Add `--interactive` to present a numbered list for selecting which
page to view.

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

`-f`, `--find`

: Find all installed formulae that provide the named man page.

`-l`, `--list`

: List every man page provided by the named formula.

`-i`, `--interactive`

: Present a numbered list for interactive selection. Requires `--list`.

