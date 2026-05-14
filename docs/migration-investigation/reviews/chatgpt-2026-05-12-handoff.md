<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

last_reviewed: 2026-05-12
-->

# ChatGPT design review — 2026-05-12

This file preserves a ChatGPT design-review session about
the cask-extract AST migration. The session ran in parallel
with a Claude chat on the same date. ChatGPT's first pass
proposed a broad "MutationPlanner" abstraction with a
five-category applicability taxonomy. The Claude chat
pushed back; ChatGPT iterated to a simpler position. Both
iterations are preserved here because:

- The **rejected** directions (Block 1 below) inform
  `../03-rejected-directions.md` (when it lands).
- The **accepted** simplification (Block 3 below) informs
  `../01-ast-migration-plan.md` (already written).

The file is intended to be write-once and immutable. Any
revision should snapshot the prior version as
`chatgpt-2026-05-12-handoff.<DATE>.snapshot.md` before
editing.

## Framing and timeline

- **2026-05-11:** Homebrew PR #22220 merged, introducing
  `Utils::AST::CaskAST` and setting AST-based source
  rewrites as the new upstream standard. cask-extract's
  Prism + manual string-offset implementation became
  out-of-step with that direction.
- **2026-05-12 (morning):** the maintainer started a
  ChatGPT session to discuss the architectural shape of
  the migration. ChatGPT produced the design-review
  document reproduced as Block 1 below.
- **2026-05-12 (afternoon):** the maintainer brought the
  ChatGPT proposal into a Claude chat for evaluation.
  Claude's first response engaged sceptically with the
  "MutationPlanner" framing and the upstream contribution
  ambition.
- **2026-05-12 (during the Claude chat):** the maintainer
  copied Claude's pushback back into the ChatGPT session.
  ChatGPT replied with Block 2 below (defense of the
  semantic-applicability concern as structurally real, not
  cosmetic).
- **2026-05-12 (further in the Claude chat):** the
  maintainer noted that for the cask-extract use case
  specifically, top-level postflight + top-level caveats
  with macOS gating in the body should be sufficient,
  given that the Cask DSL allows multiple of each.
  ChatGPT responded with Block 3 below, the simplified
  end-state proposal.
- **2026-05-12 (end of Claude chat):** the migration plan
  in `../01-ast-migration-plan.md` was finalised based on
  Block 3's shape, with a further simplification (no
  idempotency check by default — see § "On idempotency"
  in 01).

Three pieces of content are preserved verbatim below. Light
formatting fixes (line wrapping, minor punctuation) have
been applied for readability; the substance is unchanged.

---

## Block 1 — ChatGPT's original design-review document

> # Homebrew Cask AST / Mutation Planning Design Review
>
> I am designing a structural AST mutation system for
> Homebrew Casks and would like help refining the
> architecture, tradeoffs, boundaries, and implementation
> strategy.
>
> The concrete use case is an external Homebrew command that
> extracts casks into a personal tap and optionally mutates
> them to:
>
> 1. add or modify a `postflight` block to remove the
>    quarantine xattr
> 2. add or modify `caveats` warning text informing the user
>    that Gatekeeper protections are bypassed
>
> However, I do NOT want to upstream quarantine-specific
> policy into Homebrew core. I instead want to upstream
> reusable AST / mutation infrastructure into
> `Utils::AST::CaskAST`.
>
> The goal is:
>
> - minimal diffs
> - semantic correctness
> - Homebrew-reviewable architecture
> - reusable AST infrastructure
> - separation of generic AST mutation from policy-specific
>   mutation logic
>
> Please deeply evaluate:
>
> - what belongs upstream vs external command
> - whether the proposed abstractions are correct
> - what edge cases are still missing
> - whether the architecture is too complicated or not
>   sophisticated enough
> - how Homebrew maintainers would likely react
> - whether there are simpler ways to accomplish the same
>   goals without sacrificing correctness
> - how this should evolve incrementally without
>   destabilizing Homebrew
>
> ---
>
> ## Relevant upstream context
>
> Homebrew already has:
>
> - `Utils::AST::FormulaAST`
> - `Utils::AST::CaskAST`
> - RuboCop AST integration
> - `TreeRewriter`
> - ordering-aware insertion logic for formulae
>
> Homebrew also already has a canonical stanza order for
> casks: https://docs.brew.sh/Cask-Cookbook#stanza-order
>
> Notably:
>
> - casks are declarative
> - stanza ordering is canonical
> - nested `on_*` blocks exist
> - conditional Ruby still exists in the ecosystem
> - multiple occurrences of `postflight` and `caveats` are
>   allowed
> - `caveats` may be string or block form
> - `postflight` blocks contain deferred Ruby execution
>
> Existing `FormulaAST` already contains hidden
> "proto-planner" behavior:
>
> - insertion-point selection
> - ordering-aware insertion
> - TreeRewriter-based mutation
>
> But it does NOT model semantic scopes or applicability.
>
> ---
>
> ## Architectural direction
>
> I currently believe the correct split is:
>
> ### Upstream Homebrew
>
> Extend `Utils::AST::CaskAST` with:
>
> - scoped stanza traversal
> - conditional ancestry inspection
> - stanza ordering rules
> - insertion point planning
> - TreeRewriter mutation helpers
> - block stanza mutation APIs
> - semantic scope classification
>
> But NOT:
>
> - quarantine semantics
> - xattr detection
> - Gatekeeper caveats
> - shell command heuristics
> - security policy
>
> ### External command
>
> Contains:
>
> - quarantine-removal policy
> - xattr command generation
> - caveat wording
> - idempotency heuristics for quarantine handling
> - "should mutate?" decisions
>
> ---
>
> ## Important design constraints
>
> ### 1. Semantic correctness matters
>
> I strongly want to avoid heuristic insertion.
>
> Example:
>
> ```ruby
> postflight do
>   # ...
> end
> ```
>
> is NOT enough. We must know:
>
> - whether it applies globally
> - only on macOS
> - only on Linux
> - only on Intel
> - only on ARM
> - only on certain macOS versions
>
> because quarantine removal only makes sense in
> macOS-applicable scopes.
>
> Examples:
>
> ```ruby
> on_linux do
>   postflight do
>   end
> end
> ```
>
> must NOT be mutated for quarantine removal.
>
> Likewise:
>
> ```ruby
> on_intel do
>   caveats "..."
> end
> ```
>
> must not receive a globally-applicable warning if the
> warning applies to ARM too.
>
> ### 2. Existing conditional Ruby still exists
>
> Even though Homebrew has DSL replacements for many cases
> (`on_arm`, `on_intel`, `on_macos`, etc.), arbitrary Ruby
> conditionals still exist in historical casks and
> third-party taps.
>
> Examples:
>
> ```ruby
> if Hardware::CPU.arm?
> if MacOS.version <= :ventura
> ```
>
> The mutation system must decide:
>
> - whether to understand these
> - whether to classify them conservatively
> - whether to bail
> - whether to treat them as unknown applicability
>
> ### 3. Minimal diffs matter
>
> Homebrew maintainers strongly prefer:
>
> - deterministic mutations
> - minimal diffs
> - formatting preservation
> - DSL-aware insertion
> - avoiding unnecessary rewrites
>
> Therefore:
>
> - converting all caveats strings to blocks automatically
>   may be too invasive
> - but appending to string caveats may be semantically
>   impossible
> - planner behavior matters
>
> ---
>
> ## Current thinking: semantic applicability categories
>
> I am considering upstream support for classifying scopes
> into categories like:
>
> ```
> :global
> :macos
> :linux
> :arch_specific
> :version_specific
> :conditional_unknown
> ```
>
> Mutation policy could then decide:
>
> - mutate existing stanza
> - create sibling stanza
> - insert globally
> - bail conservatively
>
> ---
>
> ## Current thinking: planner responsibilities
>
> I think the missing abstraction is a semantic mutation
> planner. Not necessarily public API, but internally
> something like:
>
> ```ruby
> planner = ast.insertion_planner
> scope = planner.find_applicable_scope(
>   stanza: :postflight,
>   applicability: :macos,
> )
> planner.insert_block_stanza(
>   :postflight,
>   scope: scope,
>   body: ruby_source,
> )
> ```
>
> This would:
>
> - understand stanza ordering
> - understand nested on_* scopes
> - understand applicability
> - compute insertion points
> - use TreeRewriter underneath
>
> ---
>
> ## Important distinction
>
> I do NOT think upstream Homebrew would accept:
>
> - quarantine-specific AST helpers
> - xattr detection
> - "contains com.apple.quarantine"
> - shell semantic analysis
> - security-policy logic
>
> Those belong in the external command. The AST layer
> should remain generic.
>
> ---
>
> ## Proposed incremental upstream plan
>
> **Commit 1.** Add reusable cask stanza ordering constants
> and traversal helpers.
>
> **Commit 2.** Add scoped stanza traversal and conditional
> ancestry inspection.
>
> **Commit 3.** Add insertion planning helpers using
> TreeRewriter.
>
> **Commit 4.** Add block stanza mutation APIs.
>
> **Commit 5.** External command migrates from Prism-based
> heuristics to CaskAST planner APIs.
>
> ---
>
> ## Existing external command problems
>
> Current implementation uses:
>
> - Prism
> - flat traversal
> - heuristic insertion
> - manual string offsets
>
> Example:
>
> ```ruby
> if content.include?("com.apple.quarantine")
> ```
>
> and:
>
> ```ruby
> insert_new_postflight(...)
> ```
>
> This is structurally weak and not upstreamable.
>
> ---
>
> ## Proposed upstream APIs (pseudocode)
>
> ### Scope classification
>
> ```ruby
> scope = ast.scope_for(node)
> scope.global?
> scope.macos?
> scope.linux?
> scope.arch_specific?
> scope.version_specific?
> scope.unknown?
> ```
>
> ### Scoped traversal
>
> ```ruby
> ast.each_stanza(:postflight) do |stanza, scope|
> end
> ```
>
> ### Ordered insertion planning
>
> ```ruby
> planner.insertion_point(
>   stanza: :postflight,
>   scope: target_scope,
> )
> ```
>
> ### Block stanza insertion
>
> ```ruby
> planner.insert_block_stanza(
>   :postflight,
>   body: <<~RUBY,
>     system_command "/usr/bin/xattr",
>                    args: ["-dr", "com.apple.quarantine", "#{appdir}/Foo.app"]
>   RUBY
>   scope: target_scope,
> )
> ```
>
> ### Caveats mutation
>
> ```ruby
> planner.ensure_caveats_warning(
>   warning_text,
>   applicability: :macos,
> )
> ```
>
> (Though perhaps this last API belongs only in the external
> command.)
>
> ---
>
> ## Important open questions
>
> ### 1. How much conditional understanding belongs upstream?
>
> Should upstream:
>
> - understand only official DSL (`on_arm`, `on_macos`, etc.)
> - classify arbitrary Ruby conditionals as unknown
> - attempt limited interpretation of common Ruby patterns
> - never attempt interpretation
>
> ### 2. How conservative should mutations be?
>
> Example:
>
> - existing postflight exists inside unknown conditional
> - planner cannot prove applicability
>
> Should it:
>
> - mutate anyway
> - create sibling global stanza
> - create sibling macOS stanza
> - bail entirely
>
> ### 3. How should string caveats be handled?
>
> Example:
>
> ```ruby
> caveats "Some message"
> ```
>
> Possible strategies:
>
> - leave untouched and create second caveats block
> - convert to block form
> - prepend/append string
> - bail conservatively
>
> What is most Homebrew-like?
>
> ### 4. Should "MutationPlanner" exist as a named abstraction?
>
> Or should this instead be:
>
> - incremental extension of CaskAST
> - private insertion helpers
> - no explicit planner type
>
> Would maintainers likely reject a formal "planner"
> abstraction as overengineering?
>
> ### 5. Is applicability modeling too ambitious?
>
> Would Homebrew likely accept:
>
> - global/macos/linux/unknown
>
> but reject:
>
> - symbolic applicability graphs
> - richer semantic modeling
>
> Where is the likely acceptable boundary?

---

## Block 2 — ChatGPT's defense-of-applicability pushback

After Claude's first response challenged the
"MutationPlanner" framing and the upstream contribution
ambition, ChatGPT replied with this defense. Verbatim:

> The reason semantic applicability matters is not "because
> cask-extract wants sophistication." It's because blindly
> mutating the first matching stanza is actually incorrect
> for real casks.
>
> Examples already present in the Cookbook:
>
> - on_arm
> - on_intel
> - on_<macos>
> - nested conditional blocks
> - legacy Hardware::CPU / MacOS.version Ruby conditionals
> - arbitrary Ruby methods and variables
>
> If a cask has:
>
> - a postflight only inside on_intel,
> - or only inside on_sonoma,
> - or only inside a conditional branch,
>
> then appending globally-applicable quarantine removal into
> that block is semantically wrong.
>
> Likewise for caveats.
>
> That semantic reasoning does not belong upstream. But the
> structural capability to identify:
>
> - where a stanza lives,
> - whether it is top-level,
> - and what enclosing blocks contain it,
>
> does belong in a reusable AST layer.
>
> The proposed upstream work is therefore intentionally
> narrow:
>
> 1. extend CaskAST from scalar replacement into structural
>    mutation,
> 2. codify canonical stanza ordering from the Cookbook,
> 3. expose contextual stanza metadata,
> 4. provide minimal-diff insertion APIs.
>
> Everything quarantine-specific remains downstream.
>
> Also, the "too many commits" concern misunderstands the
> intent of the commit decomposition. The decomposition was
> architectural, not a requirement that Homebrew merge five
> speculative infrastructure PRs independently. In practice
> this would likely collapse into:
>
> - one focused AST enhancement PR,
> - then a downstream consumer PR in the external command.

---

## Block 3 — ChatGPT's simplified end-state proposal

After the maintainer pointed out (in the Claude chat) that
top-level postflight and top-level caveats might be
sufficient given that the Cask DSL allows multiples of
each, ChatGPT replied with this simplified proposal.
Verbatim:

> For our use case, the model can become:
>
> 1. Detect whether the cask is macOS-capable.
> 2. Detect whether quarantine handling already plausibly
>    exists.
> 3. If not:
>    - insert a new top-level postflight,
>    - insert a new top-level caveats,
>    - place both according to canonical stanza ordering.
>
> That avoids almost all of the earlier semantic complexity.
>
> The remaining edge cases are much smaller:
>
> - Linux-only casks.
> - Existing quarantine-removal behavior.
> - Weird Ruby metaprogramming that obscures artifacts.
> - Existing top-level postflight already doing equivalent
>   work.
> - Existing caveat already warning about Gatekeeper.
>
> But critically:
>
> - none of those require AST semantic evaluation upstream,
> - and most can remain "best effort" heuristics in your
>   external command.
>
> I think your latest direction strongly argues for this
> split:
>
> **Upstream: minimal structural AST improvements**
>
> Extend Utils::AST::CaskAST only enough to support:
>
> - top-level stanza enumeration,
> - top-level block stanza lookup,
> - stanza insertion by canonical ordering,
> - block stanza insertion,
> - minimal-diff TreeRewriter support.
>
> Something like:
>
> ```ruby
> cask_ast.top_level_stanzas
> cask_ast.stanzas(:postflight, type: :block_call, top_level: true)
>
> cask_ast.add_stanza(
>   :postflight,
>   <<~RUBY,
>     postflight do
>       ...
>     end
>   RUBY
>   type: :block_call,
> )
> ```
>
> I would not build semantic guard evaluation infrastructure
> just to avoid duplicate xattr calls.
>
> The ideal end-state now looks more like:
>
> ```ruby
> ast = Utils::AST::CaskAST.new(contents)
>
> unless quarantine_handler_present?(ast)
>   ast.add_top_level_block_stanza(
>     :postflight,
>     body: quarantine_postflight_body(apps),
>   )
> end
>
> unless gatekeeper_warning_present?(ast)
>   ast.add_top_level_block_stanza(
>     :caveats,
>     body: gatekeeper_warning_body,
>   )
> end
>
> path.write(ast.process)
> ```
>
> with canonical ordering internally encoded.

---

## Resolution

The migration plan in `../01-ast-migration-plan.md` adopts
Block 3's structure with three refinements that emerged in
the Claude chat after Block 3, all from the maintainer:

1. **The `quarantine_handler_present?` and
   `gatekeeper_warning_present?` predicates are
   implemented, but not via AST traversal as ChatGPT
   proposed.** Instead, each inserted stanza is preceded
   by a unique sentinel comment line
   (`# cask-extract: quarantine xattr removal` /
   `# cask-extract: Gatekeeper bypass warning`) and the
   predicate is `content.include?(marker)`. This idea was
   the maintainer's contribution in chat, paralleling
   Homebrew's own `.github/workflows/sync-shared-config.yml`
   marker-line pattern at lines 89-91. It is greppable,
   survives `rubocop --autocorrect`, has effectively zero
   false-positive rate, and doubles as a deliberate manual
   opt-out. The marker-comment design eliminates the need
   for AST traversal of postflight bodies, which in turn
   eliminates the need for an `enclosing_blocks(node)` or
   `each_stanza_with_body` traversal helper at any layer.
   Full design in `../01-ast-migration-plan.md` §
   "Idempotency via marker comments".
2. **macOS gating uses `on_macos do` wrappers**, not
   body-level `OS.mac?` checks. Body-level alternatives all
   trip the `Homebrew/MoveToExtendOS` cop. The cask DSL's
   `on_macos` and `on_linux` are NOT in
   `ON_SYSTEM_METHODS_STANZA_ORDER` (see
   `Library/Homebrew/rubocops/cask/constants/stanza.rb` in
   Homebrew/brew — only the macOS-version symbols plus
   `on_arm` / `on_intel` participate in that ordering),
   confirmed empirically. The maintainer verified that
   multiple top-level `on_macos do` blocks at arbitrary
   positions all pass rubocop. See
   `../01-ast-migration-plan.md` § "The macOS gating
   question".
3. **The cask stanza-order constant is consumed directly
   from upstream, not refactored.** Block 2's pitch
   included "codify canonical stanza ordering from the
   Cookbook" as one of the four narrow upstream
   extensions. After the chat verified that the constant
   already exists at `RuboCop::Cask::Constants::STANZA_ORDER`
   in `Library/Homebrew/rubocops/cask/constants/stanza.rb`
   (consumed today by `rubocops/os_depends_on.rb` and
   `rubocops/cask/ast/stanza.rb`), the W8.3 upstream PR
   reduces to just `CaskAST#add_stanza_after`. cask-tools
   consumes the existing constant directly via `require`.

The resulting upstream candidate (W8.3) is therefore
narrower than Block 3 proposed: a single focused PR adding
`CaskAST#add_stanza_after` mirroring `FormulaAST`. No
stanza-order refactor, no `enclosing_blocks`, no
`each_stanza_with_body`, no applicability taxonomy. The
cask-tools-internal helpers module is correspondingly
small: one helper (`add_top_level_block_stanza`) plus the
marker-comment idempotency predicates. See
`../01-ast-migration-plan.md` § "The internal CaskAST
helpers" and § "Idempotency via marker comments" for
the current shape.

The full set of rejected directions (the planner
abstraction, the applicability taxonomy, the five-PR
upstream sequence, the substring idempotency check, and
ChatGPT's originally-proposed AST predicate as a
replacement) is catalogued in
`../03-rejected-directions.md` (forthcoming).

The W8.3 upstream PR framing is documented in
`../04-upstream-strategy.md` (forthcoming).
