<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# Migration investigation — cask-extract Prism → CaskAST (2026-05)

This directory documents the investigation that preceded
migrating `cmd/cask-extract.rb` from Prism-with-manual-string-
offsets to `Utils::AST::CaskAST` with
`Parser::Source::TreeRewriter`, and the related decisions
about what belongs upstream in Homebrew versus what stays in
this tap.

## How to read this

If you only read one file, read
[`00-meta-overview.md`](00-meta-overview.md) — it summarizes
what's being investigated, what direction is being adopted,
and what's been rejected.

For specific topics:

- [`00-meta-overview.md`](00-meta-overview.md) — entry point,
  timeline, scope, what survives the migration, what doesn't
- [`01-ast-migration-plan.md`](01-ast-migration-plan.md) —
  the technical migration plan: current state, target state,
  internal-vs-upstream split, the proposed module shape
- `02-known-bugs-and-rough-edges.md` (forthcoming) — the
  cask-extract correctness issues being fixed; the `man`
  "system pages" investigation as resolved-not-a-bug
- `03-rejected-directions.md` (forthcoming) — what was
  considered and discarded: the "MutationPlanner"
  abstraction, the five-category applicability taxonomy
  upstream, the substring-based idempotency check
- `04-upstream-strategy.md` (forthcoming) — what to upstream
  (stanza-order constant refactor, narrow helpers); what to
  keep internal (quarantine policy, caveats text,
  idempotency heuristics)
- `adrs/` (forthcoming) — Architecture Decision Records
  relevant to the migration: Prism→CaskAST, postflight
  insertion policy, caveats-as-new-stanza
- `reviews/chatgpt-2026-05-12-handoff.md` (forthcoming) —
  preserves the ChatGPT design-review session, including
  pushback, the simplified end-state, and the resolved
  upstream-vs-internal split

## Sources

- Homebrew PR
  [#22220](https://github.com/Homebrew/brew/pull/22220)
  (merged 2026-05-11) introducing `Utils::AST::CaskAST` and
  setting the new upstream direction for source rewrites
- Homebrew PR
  [#22238](https://github.com/Homebrew/brew/pull/22238)
  (merged 2026-05-12) — unrelated to this work but referenced
  in the master plan; documented for context
- `Library/Homebrew/utils/ast.rb` at upstream main (664 lines
  post-#22220) — the reference shape for `FormulaAST` that
  `CaskAST` should mirror for structural mutation
- `rubocop-cask`'s `Cop::Cask::StanzaOrder` — current home of
  the canonical cask stanza order; a candidate upstream
  refactor target for W8.3
- The Cask Cookbook stanza order section
  (https://docs.brew.sh/Cask-Cookbook#stanza-order) — the
  human-readable authoritative source
- ChatGPT design-review session (2026-05-12, to be preserved
  in `reviews/`)

## Status

The work this directory documents is **active**. The
migration implementation is workstream W8 in
`~/devel/claude/desktop/workspace/master-plan.md`.

Tactical debt items (test coverage gaps, error handling
hardening) remain in [`../tech-debt.md`](../tech-debt.md) and
are tracked separately. Items #3 (Prism AST parse failures)
and #8 (git output not validated) are folded into this
investigation's bug catalog; the rest stay tactical.
