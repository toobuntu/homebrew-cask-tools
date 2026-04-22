---
number: 3
title: "`brew man --interactive` cancellation exit behavior"
status: accepted
date: 2026-04-21
---

<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# `brew man --interactive` cancellation exit behavior

## Context and Problem Statement

`brew man --interactive` presents an fzf selector (or a paged TTY fallback) for
choosing a man page. Three code paths exist where the user makes no selection:

1. **fzf Escape / Ctrl+C** — fzf exits with code 130 and returns empty output
2. **TTY EOF (Ctrl+D)** — `/dev/tty` `gets` returns `nil`
3. **Non-TTY nil stdin** — stdin is not a TTY; interactive selection is
   structurally impossible

The original code called `odie "No selection made."` in all three paths, which
printed `Error: No selection made.` to stderr and exited 1 — treating a
deliberate user cancellation the same as a hard failure.

Cases 1 and 2 are user-initiated dismissals. Case 3 is different: the command
was invoked in a mode it cannot fulfill (no TTY means interactive selection is
structurally impossible). What should the exit code and diagnostic output be for
each path?

## Decision Outcome

Chosen option: differentiate user cancellation (exit 0) from environmental
precondition failure (exit 1), because exit codes should reflect *why* execution
ended, not merely *that* it ended without a result.

| Case | Exit code | Message |
|---|---|---|
| fzf Escape / Ctrl+C (empty output) | 0 | `$stderr.puts "No selection made."` if `--verbose` |
| TTY EOF (Ctrl+D) | 0 | `$stderr.puts "No selection made."` if `--verbose` |
| Non-TTY nil stdin | 1 | `Error: brew man: --interactive requires a TTY` (stderr, suppressed by `--quiet`) |

### Consequences

* Good, because users pressing Escape or Ctrl+D see no output — consistent with
  how interactive Unix tools (fzf, vim, git interactive rebase) behave on
  cancellation.
* Good, because `--verbose` users see `No selection made.` on stderr, confirming
  the command ran and exited cleanly without a selection.
* Good, because a caller piping or scripting `brew man --interactive` in a
  non-TTY context receives exit 1 and an error message, suppressible with
  `--quiet` while still observing the exit code.
* Neutral, because `--debug` behavior is unchanged; no additional output is
  emitted for these paths at the debug level.

## More Information

The correct implementation for Cases 1 and 2 is:

```ruby
$stderr.puts "No selection made." if args.verbose?
exit 0
```

No `Utils::Output::Mixin` method maps to this combination of verbose-gating,
stderr destination, and neutral informational register (see reference table
below). Forcing a fit onto an existing mixin trades semantic correctness for
cosmetic idiomaticity — the worse tradeoff.

### `Utils::Output::Mixin` method map

Source: [`utils/output.rb`](https://github.com/Homebrew/brew/blob/master/Library/Homebrew/utils/output.rb)
Docs: <https://docs.brew.sh/rubydoc/Utils/Output/Mixin.html>

| Method | Destination | Prefix / format | Flag gate | Exit effect |
|---|---|---|---|---|
| `ohai(title, *sput)` | **stdout** | `==>` bold blue; truncated unless `--verbose` or non-TTY | None (unconditional) | None |
| `oh1(title, truncate: :auto)` | **stdout** | `==>` bold green; same truncation logic | None (unconditional) | None |
| `odebug(title, *sput, always_display: false)` | **stderr** | Bold magenta headline (no label) | `--debug` (or `always_display: true`) | None |
| `opoo(message)` | **stderr** | `Warning:` yellow | None (unconditional) | None |
| `opoo_outside_github_actions(message)` | **stderr** | `Warning:` yellow | None, but suppressed entirely in GitHub Actions | None |
| `onoe(message)` | **stderr** | `Error:` red | None (unconditional) | None |
| `ofail(error)` | **stderr** (via `onoe`) | `Error:` red | None (unconditional) | Sets `Homebrew.failed = true`; deferred exit 1 at program end |
| `odie(error)` | **stderr** (via `onoe`) | `Error:` red | None (unconditional) | **Immediate** `exit 1` |

Notable gaps relevant to this ADR:

- No method is both **verbose-gated** and writes to **stderr**.
- `odebug` with `always_display: true` and an `if args.verbose?` guard was
  considered: it reaches stderr but applies magenta headline formatting
  inappropriate for a plain status notice, and the double-gating (mixin's own
  debug check plus the explicit verbose guard) is confusing.
- `ohai` / `oh1` with `if args.verbose?` was considered: verbose-gated but
  writes to stdout and carries step-announcement weight (`==>`) that
  overstates a soft cancellation notice.
- `$stderr.puts … if args.verbose?` is raw Ruby but is the most accurate
  expression of the intent.
