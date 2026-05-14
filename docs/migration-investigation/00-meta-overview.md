<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

last_reviewed: 2026-05-12
-->

# Meta overview

## What is being investigated

`cmd/cask-extract.rb` is a Homebrew external command that
extracts a cask from Homebrew's git history into a personal
tap, optionally adding a `postflight` block to strip
`com.apple.quarantine` from installed bundles so
un-notarized apps launch without Gatekeeper blocking them.
The intended end-state also adds a `caveats` block warning
the user that Gatekeeper protections are bypassed.

The command was originally implemented using
[Prism](https://ruby.github.io/prism/) — Ruby's built-in AST
parser — paired with manual string-offset arithmetic
(`location.start_offset`, `content.dup.insert`) to inject
the new stanzas. The implementation has been correct for the
common case (no existing postflight, top-level `app` stanza,
simple version stanza) but has structural weaknesses around
the less common cases (nested postflight inside an
`on_intel do` block, existing quarantine handling not
reliably detected, caveats injection contemplated but
unimplemented).

On 2026-05-11 Mike McQuaid merged Homebrew
[PR #22220](https://github.com/Homebrew/brew/pull/22220),
introducing `Utils::AST::CaskAST` and migrating
`bump-formula-pr`, `bump-cask-pr`, PyPI/CPAN resource
updates, and the audit Linux-path cask inspection from
regex-based and `Utils::Inreplace`-based source rewrites to
AST-based ones via `rubocop-ast` and
`Parser::Source::TreeRewriter`. The direction is
unambiguous: AST-based mutation is now the upstream
standard for source rewrites.

This investigation answers four questions:

1. **What should the cask-extract migration look like?**
2. **What of it belongs upstream in Homebrew, what stays
   here?**
3. **What concrete bugs does the migration fix?**
4. **What alternative directions were considered and
   rejected?**

A separate ChatGPT design-review session on 2026-05-12
proposed a broad "MutationPlanner" abstraction with a
five-category applicability taxonomy
(`:global`/`:macos`/`:linux`/`:arch_specific`/
`:version_specific`/`:conditional_unknown`). The structural
concerns the session raised are valid — most importantly,
that blindly mutating the first matching `postflight` block
is incorrect for casks where the existing postflight is
nested inside an `on_*` or conditional block. The
architectural framing, however, was too speculative for an
upstream Homebrew contribution.

The investigation reconciles the two positions and lands on
a narrower, more upstream-friendly direction (documented
across `01-ast-migration-plan.md` and the forthcoming
`04-upstream-strategy.md`; the ChatGPT review itself will
be preserved under `reviews/`).

## Timeline

- **Pre-2026** — Original `cmd/cask-extract.rb`
  implementation: Prism + manual string-offset insertion.
  `docs/architecture.md` documents the rationale ("regex-
  based code injection is fragile for Ruby DSLs"). Test
  coverage exists for the resolve / extracted-token /
  destination-path paths but not for the AST mutation paths
  themselves. Recorded in `docs/tech-debt.md` as item #3.

- **2026-05-11** — Homebrew PR #22220 merged. New
  `Utils::AST::CaskAST` API available; `FormulaAST` extended
  with `replace_resource_stanzas`, `add_stanza`, and others.
  `bump-cask-pr` switches from inreplace/regex to AST-based
  rewrites. Setting the new upstream standard for source
  mutation.

- **2026-05-12** — Chat session identifies cask-extract as
  out-of-step with the new upstream direction. ChatGPT
  design-review session proposes "MutationPlanner"
  abstraction (over-broad on the first pass, narrower on
  the second pass after pushback). Investigation initiated.
  `cmd/man.rb` "system pages" suspicion investigated and
  confirmed not-a-bug. This investigation's initial docs
  (README, `00-meta-overview`, `01-ast-migration-plan`)
  drafted.

## What's being adopted

The migration plan converges on a deliberately simple
architecture (details in `01-ast-migration-plan.md`):

- **Parsing via `Utils::AST::CaskAST`** instead of Prism.
  Aligns with the upstream direction set by PR #22220 and
  uses the same `rubocop-ast` parser stack Homebrew's
  RuboCop integration uses.

- **Mutation via `Parser::Source::TreeRewriter`** instead of
  manual string-offset arithmetic. Atomic, comment-aware,
  formatting-preserving.

- **Top-level postflight + top-level caveats** as the
  insertion pattern. The Cask DSL allows multiple
  `postflight` blocks (all bodies execute) and multiple
  `caveats` blocks (text concatenates), so injecting a new
  top-level stanza alongside any existing nested ones is
  structurally safe. This avoids the scope-classification
  complexity that would otherwise be needed to mutate
  nested stanzas correctly.

- **macOS gating via `on_macos do` wrappers** around the
  inserted `postflight` and `caveats`. Body-level
  alternatives (`if OS.mac?`, `next unless OS.mac?`,
  `return unless OS.mac?`) all trip the
  `Homebrew/MoveToExtendOS` cop. The cask DSL's `on_macos`
  and `on_linux` are NOT in `ON_SYSTEM_METHODS_STANZA_ORDER`
  (see `Library/Homebrew/rubocops/cask/constants/stanza.rb`
  in Homebrew/brew — only the macOS-version symbols plus
  `on_arm` / `on_intel` participate in that ordering), so
  wrapping doesn't introduce a stanza-position quandary.
  Increasingly relevant as Linux casks grow in the
  ecosystem and Gatekeeper is macOS-only.

- **Idempotency via marker comments.** Each inserted stanza
  is preceded by a unique sentinel comment line
  (`# cask-extract: quarantine xattr removal` above the
  postflight, `# cask-extract: Gatekeeper bypass warning`
  above the caveats). The idempotency check becomes
  `content.include?(marker)` for each. This replaces the
  current substring check
  (`content.include?("com.apple.quarantine")`), which has
  both false-positive modes (matches comments, `xattr -l`
  listings, caveats strings) and a false-negative mode
  (casks stripping `com.apple.provenance` only are silently
  skipped). The marker-comment approach is greppable,
  survives `rubocop --autocorrect`, has effectively zero
  false-positive rate, and doubles as a manual opt-out
  (adding the marker to a hand-rolled stanza suppresses
  re-insertion). Design parallels Homebrew's own
  `.github/workflows/sync-shared-config.yml` marker line.
  Full rationale in `01-ast-migration-plan.md` §
  "Idempotency via marker comments".

- **Caveats injection**, which the original implementation
  contemplated but didn't ship. Inserts a top-level
  `caveats` block warning that Gatekeeper protections are
  bypassed for the cask, alongside (not in place of) any
  existing caveats.

The migration preserves the existing two-path extraction
strategy (delegate to `brew extract --cask` when available;
fall back to manual git-history extraction otherwise). The
AST mutation happens in `post_process_extracted_cask` /
`fallback_extract`, which currently call
`add_quarantine_postflight`. After the migration these call
a new pair: `add_quarantine_handling` (which dispatches to
postflight injection and caveats injection through a unified
flow).

## What's being left behind

- **Prism** — replaced by `rubocop-ast`. Prism is faster and
  is becoming Ruby's default parser, but Homebrew's choice
  is `rubocop-ast` (built on the `parser` gem) for AST work,
  and the cask-tools alignment with upstream matters more
  than parser performance for this use case.
- **Manual string-offset insertion** — replaced by
  `Parser::Source::TreeRewriter`. `closing_loc.start_offset`
  + `content.dup.insert` is exactly the pattern PR #22220
  migrated upstream code away from.
- **Substring-based idempotency check** — replaced by a
  marker-comment scheme (`# cask-extract: ...` sentinel
  lines above each inserted stanza, with
  `content.include?(marker)` as the idempotency predicate).
  See `02-known-bugs-and-rough-edges.md` for the
  false-positive / false-negative modes of the original
  substring approach, and `01-ast-migration-plan.md` §
  "Idempotency via marker comments" for the marker design.
- **Top-level-only stanza traversal via `stmts.find`** —
  replaced by the simpler "always insert top-level"
  insertion pattern. The current implementation's
  `stmts.find` was already top-level only (and silently
  asymmetric with `extract_app_names`, which recurses);
  the migration keeps top-level insertion as the deliberate
  choice rather than the accidental one.
- **The hardcoded `STANZAS_AFTER_POSTFLIGHT` constant** —
  replaced by reading the canonical cask stanza order from
  a single source (initially a cask-tools-internal
  constant; potentially upstream in W8.3).

What's also being left behind, but at the
upstream-vs-internal boundary (covered in detail in
`03-rejected-directions.md` and `04-upstream-strategy.md`
when those land):

- **The "MutationPlanner" abstraction** proposed in the
  ChatGPT review. It doesn't appear in upstream's existing
  AST code, and Mike McQuaid's revealed preference (PR
  #22220) is for concrete helper methods on the AST class,
  not for abstract planner objects. Kept out of both
  upstream and this tap.
- **The five-category applicability taxonomy**
  (`:global`/`:macos`/`:linux`/`:arch_specific`/
  `:version_specific`/`:conditional_unknown`). Conceptually
  fine but overspecified for what cask-extract needs.
  Replaced by the simpler top-level +
  multiple-stanzas-allowed insertion model.
- **A speculative five-PR upstream sequence.** Collapsed to
  at most one focused upstream PR (W8.3) that has a real
  upstream consumer story (refactoring the existing
  `Cop::Cask::StanzaOrder` to consume a shared constant),
  plus a tiny separate docs PR (W8.4).

## Why preserve

Three reasons that mirror babble's W2 preservation
rationale:

1. **Decision durability.** The migration is straightforward
   in hindsight, but several plausible directions were
   considered and discarded. Future readers (Claude Code in
   W8.2, the maintainer six months from now, a reviewer of
   the W8.3 upstream PR) need to find the rationale without
   re-running the conversation.
2. **Pushback context.** A future tool or contributor may
   re-propose the rejected directions ("MutationPlanner",
   semantic applicability categories, broad upstream
   contribution sequence). The rejected-directions doc lets
   the maintainer point at a prior decision rather than
   re-litigating from scratch.
3. **Upstream PR support.** When W8.3 is drafted, the PR
   description benefits from being able to cite a concrete
   downstream consumer (this tap) and a concrete motivating
   bug pattern (the nested-postflight semantic-correctness
   case, even if W8.2 ends up not needing scope awareness
   for the cask-extract policy). The investigation docs
   are that support.

## Status of related technical debt

`docs/tech-debt.md` items that fold into the migration:

- **#3** (Prism AST parse failures in cask-extract):
  resolved by the migration; superseded by the new test
  coverage that W8.2 will land. To be removed from
  tech-debt.md once W8.2 ships.
- **#8** (git output not validated in cask-extract):
  adjacent to the migration but not blocked by it; the AST
  migration doesn't touch `find_cask_in_history`. Stays in
  tech-debt.md.

Other tech-debt items (test coverage for
`candidate_bundle_names`, `escape_glob`, `interactive_select`
paths; bundler gem install error handling; completion file
syntax validation; AGENTS.md/CLAUDE.md drift) are unrelated
to the migration and remain in tech-debt.md.

The `cmd/man.rb` system-pages investigation is documented
in the forthcoming `02-known-bugs-and-rough-edges.md` as
resolved-not-a-bug, to prevent re-investigation. The system
page for the test case (`openssl`) simply does not exist on
macOS (`find /usr/share/man -name "*openssl*"` returns
nothing); system pages for formulae that do ship one
(`curl`, `ls`) are found correctly by
`brew man --find <name>`.
