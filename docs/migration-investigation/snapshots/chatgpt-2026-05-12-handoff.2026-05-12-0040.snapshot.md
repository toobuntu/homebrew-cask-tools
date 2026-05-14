<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
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
Block 3's structure with two further simplifications that
emerged in the Claude chat after Block 3:

1. **`enclosing_blocks(node)` (or `each_stanza_with_body`)
   is not needed.** Block 3 still proposed `quarantine_handler_present?(ast)`
   and `gatekeeper_warning_present?(ast)` predicates, which
   would have required traversing nested stanzas. After
   further discussion, the predicates themselves were
   identified as YAGNI: duplicate `xattr -d
   com.apple.quarantine PATH` is harmless (exits 0 with no
   output when the xattr is absent), and duplicate `caveats`
   stanzas concatenate at runtime. The cosmetic value of
   avoiding duplicates on the rare re-run of
   `cask-extract --no-quarantine` doesn't justify the
   variant-matching complexity. The substring idempotency
   check is **removed**, not replaced. Full rationale lives
   in `../01-ast-migration-plan.md` § "On idempotency".
2. **macOS gating moves into the postflight body** as
   `next unless OS.mac?`, rather than wrapping the postflight
   in `on_macos do ... end`. Belt-and-suspenders; keeps
   insertion at the top-level position without needing
   scope-classification at all.

The resulting upstream candidate (W8.3) is therefore even
narrower than Block 3 proposed: a single focused PR that
(a) refactors `Cop::Cask::StanzaOrder`'s stanza-order data
into a reusable constant in
`Library/Homebrew/ast_constants.rb`, and (b) adds
`CaskAST#add_stanza_after` mirroring `FormulaAST`. No
`enclosing_blocks`, no `each_stanza_with_body`, no
applicability taxonomy.

The cask-tools-internal helpers module is correspondingly
small: one helper (`add_top_level_block_stanza`) plus the
cask stanza-order constant. See
`../01-ast-migration-plan.md` § "The internal CaskAST
helpers" for the current shape.

The full set of rejected directions (the planner
abstraction, the applicability taxonomy, the five-PR
upstream sequence, the substring idempotency check, and
the originally-proposed AST replacement check) is
catalogued in `../03-rejected-directions.md` (forthcoming).

The W8.3 upstream PR framing is documented in
`../04-upstream-strategy.md` (forthcoming).
