brew-man(1) -- Display a man page bundled with an installed formula
===================================================================

## SYNOPSIS

`brew` `man` [<options>] [<section>] <formula> [<manpage>]

`brew` `man` (`--list`|`--interactive`) [<options>] <manpage>

`brew` `man` (`--list`|`--interactive`) `--all` [<options>] <formula>

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

Use `--list` or `--interactive` to search across system and other
Homebrew formulae. Shows all locations where a man page name is
found. Formulae that provide a binary matching the page name are
also included. Add `--all` to list every man page an installed
formula provides instead of searching by page name.

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

`-a`, `--all`

: List every man page provided by the named formula. Requires `--list` or `--interactive`.

