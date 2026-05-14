<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

last_reviewed: 2026-05-12
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
- [`02-known-bugs-and-rough-edges.md`](02-known-bugs-and-rough-edges.md)
  — the cask-extract correctness issues being fixed; the
  `man` "system pages" investigation as resolved-not-a-bug
- `03-rejected-directions.md` (forthcoming) — what was
  considered and discarded: the "MutationPlanner"
  abstraction, the five-category applicability taxonomy
  upstream, the substring-based idempotency check, the
  ChatGPT-proposed AST predicate as a replacement
- `04-upstream-strategy.md` (forthcoming) — W8.3 framing
  for the single upstream PR (adding
  `CaskAST#add_stanza_after`); what stays internal
  (quarantine policy, caveats text, marker-comment
  strings)
- [`reviews/chatgpt-2026-05-12-handoff.md`](reviews/chatgpt-2026-05-12-handoff.md)
  — preserves the ChatGPT design-review session, including
  pushback, the simplified end-state, and the resolved
  upstream-vs-internal split

## Architecture Decision Records

ADRs for this migration follow the org-wide MADR 4.0
convention (see the "MADR 4.0 org-wide ADR convention" item
in `~/devel/claude/desktop/workspace/master-plan.md`'s
"Open organizational questions" and the `adrs-formula` repo
for the format and tooling). They live in cask-tools'
canonical `docs/decisions/` directory, not in this
investigation tree, and continue the numbering from
existing ADRs:

- `../decisions/0003-prism-to-cask-ast.md` (forthcoming)
  — the parser switch from Prism to rubocop-ast +
  TreeRewriter; the context, decision, and consequences
- `../decisions/0004-postflight-insertion-policy.md`
  (forthcoming) — top-level insertion, `on_macos do`
  wrapping, marker-comment idempotency
- `../decisions/0005-caveats-as-new-stanza.md` (forthcoming)
  — caveats injection always adds a new stanza, never
  modifies existing ones; relies on Cask DSL's concatenation
  semantics for multiple caveats blocks

Existing cask-tools ADRs (`0001-pipx-for-ci-python-tools`,
`0002-sync-branch-pr-strategy`) are in Nygard format and
will be converted to MADR 4.0 as part of W8.5.

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
