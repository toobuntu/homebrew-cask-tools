<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# AST migration plan

## Current state

`cmd/cask-extract.rb` post-processes an extracted cask file
when `--no-quarantine` is passed. The relevant code path
(roughly lines 200-330):

1. `add_quarantine_postflight(cask_path)` is called.
2. Reads the file. Checks
   `content.include?("com.apple.quarantine")` and bails
   early if matched.
3. `Prism.parse(content)` produces a `Prism::ParseResult`.
4. `find_cask_block` walks `program.statements.body` for the
   first `Prism::CallNode` with `name == :cask` having a
   block.
5. `cask_block_stmts` flattens the block body to a list of
   top-level statement nodes.
6. `extract_app_names` recursively descends those statements
   collecting `app "Foo.app"` string arguments. The descent
   is recursive — it finds apps inside `on_arm`/`on_intel`/
   `if`. The postflight traversal that follows is **not**
   recursive, which produces the asymmetry described in the
   forthcoming bug catalog.
7. `stmts.find` (top-level only) looks for an existing
   `postflight do ... end` block.
8. If found, `append_to_postflight` computes
   `pf_block.closing_loc.start_offset`, finds the line
   start, inspects the prefix, and does
   `content.dup.insert(...)` with the xattr lines.
9. If not found, `insert_new_postflight` looks for the first
   stanza canonically following postflight (per
   `STANZAS_AFTER_POSTFLIGHT = [:uninstall_preflight,
   :uninstall_postflight, :uninstall, :zap, :caveats]`),
   computes its line-start offset, and inserts a new
   `postflight do ... end` block above it.
10. `cask_path.write(modified)`.

The implementation has been correct for the common case but
carries structural weaknesses:

- **Substring idempotency check** matches comments,
  `xattr -l` listings, and `caveats` strings that happen to
  mention `com.apple.quarantine`. False-positive: skip a
  cask that doesn't actually have quarantine removal.
  False-negative: a cask that removes
  `com.apple.provenance` only (different xattr) isn't
  detected, and we add a duplicate-ish postflight.
- **Top-level-only postflight traversal** misses postflight
  stanzas nested inside `on_*` blocks. The
  recursive-vs-non-recursive asymmetry with the app-stanza
  traversal is silent and easy to miss.
- **Manual string-offset insertion** is brittle if the
  file's formatting is unusual (e.g., a multi-line block
  opener on a separate line from `do`, blank lines around
  the closing `end`, comment lines immediately above the
  insertion point).
- **The hardcoded `STANZAS_AFTER_POSTFLIGHT` constant**
  duplicates knowledge already encoded in `rubocop-cask`'s
  `Cop::Cask::StanzaOrder` cop.
- **Caveats injection is absent entirely.**
- **No tests cover the AST mutation paths.** All current
  cask-extract tests target the resolve / token /
  destination-path / git-history helpers, not the
  mutation. Recorded in `docs/tech-debt.md` as item #3.

## Target state

Replace the Prism + string-offset implementation with
`Utils::AST::CaskAST` + `Parser::Source::TreeRewriter`,
mirroring the patterns established in upstream PR #22220 and
the existing `FormulaAST` implementation.

### Shape

```ruby
# cmd/cask-extract.rb after migration (sketch)

require "utils/ast"
require_relative "../lib/homebrew/cask_tools/cask_ast_helpers"
# Module path TBD; see "Decision points to confirm" below.

# Top-level entry point for the --no-quarantine post-processing.
sig { params(cask_path: Pathname, app_names: T::Array[String]).void }
def add_quarantine_handling(cask_path, app_names)
  if app_names.empty?
    opoo "No app stanza found; quarantine removal may need " \
         "to be configured manually."
    return
  end

  contents = cask_path.read
  ast = Utils::AST::CaskAST.new(contents)
  helpers = Homebrew::CaskTools::CaskASTHelpers.new(ast)

  helpers.insert_quarantine_postflight(app_names)
  helpers.insert_gatekeeper_caveats

  cask_path.write(ast.process)

  opoo <<~EOS
    A postflight block and caveats warning have been added.
    This bypasses macOS Gatekeeper. Verify the safety of
    this software.
  EOS
rescue => e
  opoo "Could not parse cask for AST mutation (#{e.message}); " \
       "quarantine handling not added. Add it manually."
end
```

### The internal CaskAST helpers

`Utils::AST::CaskAST` currently provides
`replace_first_stanza_value`, `replace_stanza_value`,
`depends_on_macos?`, and `process` (which returns the
`TreeRewriter`-processed source). It does **not** currently
provide insertion helpers.

One structural primitive is needed for cask-extract:

- **`add_top_level_block_stanza(name, body:)`** — inserts a
  new top-level block stanza at the canonical position per
  the Cask Cookbook stanza order. `body` is a string
  containing the full `name do ... end` source, indented
  appropriately. Mirrors `FormulaAST#add_stanza` but for
  block-form stanzas and respecting the cask ordering.

This helper lives in
`lib/homebrew/cask_tools/cask_ast_helpers.rb` (or another
path; see "Decision points" below) in this tap initially.
It is an upstream candidate (W8.3) but does not depend on
upstream landing it.

### On idempotency

The original Prism implementation guards against duplicate
insertion with
`if content.include?("com.apple.quarantine")`. The migration
**removes that guard entirely** without a replacement.
Rationale:

- The substring check has clear false-positive modes
  (matches comments, `xattr -l` listings, caveats strings
  that happen to mention the xattr) and a clear
  false-negative mode (a cask that strips
  `com.apple.provenance` only is treated as "already
  handled" for quarantine even though it isn't). Either
  way, the user gets the wrong outcome silently.
- The replacement was originally going to be an AST
  predicate over postflight bodies. The predicate's value
  is purely cosmetic — to keep the cask file tidy on
  re-runs of `cask-extract --no-quarantine`. It has no
  runtime-correctness value because
  `xattr -d com.apple.quarantine PATH` exits 0 with no
  output when the xattr is absent (duplicate calls are
  harmless), and multiple `caveats` stanzas concatenate at
  runtime (duplicate caveats are visible but harmless).
- `cask-extract --no-quarantine` is normally one-shot per
  cask extraction. Re-runs are rare. The cosmetic value of
  avoiding duplicate stanzas in that rare case doesn't
  justify the predicate's variant-matching complexity
  (`-d` vs `-dr`, `args:` keyword array vs splat, nested vs
  top-level), the test cases each variant requires, or the
  ongoing maintenance burden.

If real-world use surfaces duplicate-insertion as a genuine
irritant, the simplest possible AST predicate — "does any
`postflight` body call `system_command "/usr/bin/xattr"` at
all?" — can be added later. It won't be as precise as the
flag-and-arg-matching variant originally sketched, but the
imprecision is acceptable: false positives (skipping when a
cask uses xattr for a different attribute) just leave the
user to add quarantine handling manually, which is the same
outcome they have today when extraction fails.

### The macOS gating question

Most casks are macOS-only by default — the Cask DSL is
macOS-centric and Linux cask support exists but is rare.
The quarantine xattr is a macOS-only concept. So the
question "should the postflight be gated to macOS?" has two
reasonable answers:

1. **No gating in the body.** Insert a plain
   `postflight do ... end` at the top level. If the cask is
   somehow installed on Linux (uncommon), the `xattr`
   invocation fails. Could rely on `must_succeed: false` or
   on cask DSL semantics (a cask without `depends_on macos:`
   is implicitly macOS-only on most install paths).
2. **Explicit `next unless OS.mac?` in the body.**
   Belt-and-suspenders. Adds two lines, costs nothing at
   runtime, makes the intent explicit.

Recommendation: option 2 (explicit gate in body). One extra
line per postflight body, clear intent, zero ambiguity for
readers. Avoids needing an `on_macos do` wrapper at the
stanza level — keeping insertion at the top-level position.

The caveats text is similarly written to make sense in a
macOS context (mentioning Gatekeeper, etc.) but doesn't
need runtime gating; caveats are output text, not code.

### Stanza ordering

The Cask Cookbook stanza order is currently encoded in
`rubocop-cask`'s `Cop::Cask::StanzaOrder` cop as a
`STANZA_ORDER` array (or similar — exact constant name to
be verified during implementation). cask-extract currently
duplicates a subset (`STANZAS_AFTER_POSTFLIGHT`) for its
insertion-position lookup.

For the migration, `add_top_level_block_stanza(name, body:)`
needs the full canonical order. Two options:

1. **Read it from `rubocop-cask`'s cop class at runtime.**
   Brittle: the cop class is internal to the gem, and the
   constant could be renamed. Also requires the gem to be
   loaded.
2. **Maintain our own constant in this tap.** Duplicates
   knowledge but is stable.

Recommendation: option 2 (own constant) for W8.2, with W8.3
proposing the constant be refactored to
`Library/Homebrew/ast_constants.rb` upstream so both the
cop and `Utils::AST::CaskAST` (and downstream consumers
like this tap) can share it. If W8.3 lands, this tap
deletes its copy and switches to the upstream constant.

### Test coverage

Tests for the AST mutation paths are currently absent
(tech-debt #3). The migration adds, at minimum:

- Unit tests for `add_top_level_block_stanza` round-trip
  through `ast.process`. Cases:
  - cask with no existing postflight — insertion at
    canonical position (after artifact stanzas, before
    `uninstall`)
  - cask with existing top-level `postflight` — second one
    appears alongside it, at the canonical position
  - cask with existing nested `on_intel do postflight ... end`
    — new top-level postflight inserted; nested one
    untouched
  - cask with `caveats "string form"` — new block-form
    `caveats` inserted alongside; existing string-form
    untouched
  - cask with no `app` stanza but artifacts of other types
    — verifies the insertion position is still correct
  - cask with comments around the insertion point —
    verifies comment preservation
- Round-trip parsing test: after `ast.process`, the
  resulting source parses again as a valid Ruby file and as
  a valid cask block (no mid-block syntax errors).
- Integration test for a sample cask file with the full
  `add_quarantine_handling` flow, asserting the resulting
  source is valid Ruby and parses as a cask block with the
  expected stanza count, ordering, and a `system_command
  "/usr/bin/xattr"` call inside the inserted postflight
  body.

Note that no idempotency-predicate tests are needed because
no idempotency check is implemented (see "On idempotency"
above). If a check is added later, it gets its own test
coverage at that time.

## Internal vs upstream split

**What lives in this tap** (`cmd/cask-extract.rb` plus the
new helpers module):

- Quarantine xattr removal policy (which xattrs, which
  paths, the exact `system_command` invocation shape).
- The Gatekeeper-warning caveats prose.
- The cask stanza-order constant and the
  `add_top_level_block_stanza` helper.

**What is a candidate for upstream contribution in W8.3:**

- The stanza-order constant, refactored from
  `Cop::Cask::StanzaOrder`'s internal constant into a
  shared `CASK_COMPONENT_PRECEDENCE_LIST` in
  `Library/Homebrew/ast_constants.rb`. Existing consumer:
  the cop. New consumer: `Utils::AST::CaskAST`.
- `Utils::AST::CaskAST#add_stanza_after`, mirroring
  `FormulaAST#add_stanza`. Existing upstream consumers:
  none yet. Motivated by potential future use in
  `bump-cask-pr` (which currently only replaces values)
  and by third-party taps doing AST mutation.

**What is NOT a candidate for upstream contribution:**

- The quarantine policy, the xattr command shape, the
  caveats prose. These are quarantine-specific application
  logic, not AST infrastructure.
- An `each_stanza_with_body` (or `enclosing_blocks`)
  traversal helper. Originally proposed to support an
  idempotency predicate; no longer needed because the
  migration removes the idempotency check entirely (see
  "On idempotency" above). If a future workstream re-adds
  a check, this helper can be re-proposed at that time.
- The five-category applicability taxonomy. Not needed for
  cask-extract; not motivated by any upstream consumer.
- A "MutationPlanner" abstraction. Not consistent with
  upstream's revealed style of concrete helpers on the AST
  class.

See the forthcoming `04-upstream-strategy.md` for the W8.3
PR framing.

## Migration sequence

W8.2 implementation order:

1. **Add the internal CaskAST helpers module** at the path
   confirmed during the decision-points discussion below.
   Implements `add_top_level_block_stanza`.
2. **Add cask stanza-order constant** in the same module,
   sourced from the Cookbook and cross-referenced against
   `Cop::Cask::StanzaOrder`. Comment in the constant
   pointing at both sources as canonical.
3. **Migrate the cask-extract entry point** from
   `add_quarantine_postflight` to
   `add_quarantine_handling`. Delete the Prism-specific
   helpers (`find_cask_block`, `cask_block_stmts`, the
   Prism-based `extract_app_names`, `append_to_postflight`,
   `insert_new_postflight`, `line_start_offset`, the
   `STANZAS_AFTER_POSTFLIGHT` constant, and the substring
   `if content.include?("com.apple.quarantine")` guard).
   `extract_app_names` is preserved but ported to walk the
   rubocop-ast tree rather than Prism's.
4. **Add caveats injection** via the same flow.
5. **Add tests** per the test plan above.
6. **Update `docs/architecture.md`** to reflect the new
   approach (replace the "Why Prism instead of regex"
   section with "AST-based mutation via CaskAST"), and
   update `docs/tech-debt.md` (renamed to
   `docs/technical-debt.md` in W8.5) to mark item #3 as
   superseded.
7. **Regenerate completions and man pages** if `cmd_args`
   changes (it shouldn't, but verify via
   `scripts/run-generate-tap-man-completions.sh`).

Each step is ideally a separate commit for
review-traceability. W8.2 is one Claude Code session at
Tier 3; if it splits, the natural break point is between
step 5 (tests passing locally) and steps 6-7 (docs and
regeneration).

## Risks

- **`Utils::AST::CaskAST` internal API surface is small**
  and cask-tools' helpers module needs to interact with it.
  If upstream changes the internal `cask_block`,
  `processed_source`, or `tree_rewriter` attribute
  accessors in a future PR, the helpers could break.
  Mitigation: minimal coupling — operate on the public
  `process` method and on AST nodes obtained via
  `each_node`. If the helpers need to call
  `tree_rewriter.insert_after` directly, that's a
  legitimate public-ish surface used by `FormulaAST` itself
  via `delegate process: :tree_rewriter`.
- **Cookbook stanza order drift.** The Cookbook is the
  authoritative source; the cop encodes it; we duplicate
  it. If Homebrew adds a new cask stanza in the future,
  the duplicated list goes out of date silently.
  Mitigation: a comment in the constant pointing at the
  Cookbook + cop as canonical; occasional cross-reference
  during routine maintenance. W8.3's success would
  eliminate the duplication.
- **TreeRewriter formatting quirks.** TreeRewriter inserts
  text at byte offsets and doesn't reformat surrounding
  source. If the inserted body's indentation doesn't match
  the surrounding cask block exactly, the output is ugly
  (functional but ugly). Mitigation: build the inserted
  body with the correct two-space indentation up front;
  add a formatting verification step in tests.
- **`rubocop-ast` version skew.** Homebrew bundles
  `rubocop-ast`; the version available at runtime is
  Homebrew's version. If cask-tools' helper code uses APIs
  introduced in a newer version than Homebrew bundles, it
  breaks at runtime. Mitigation: stick to the API surface
  used by `Utils::AST::FormulaAST` and `CaskAST`
  themselves (a stable, conservative subset).
- **Parse failures.** A malformed cask file makes
  `CaskAST.new(contents)` raise during the `process_cask`
  step. Currently `cask-extract` warns and continues for
  Prism parse errors; with rubocop-ast, parse failures are
  harder to recover from. Mitigation: wrap CaskAST
  construction in a rescue that surfaces a clear error and
  skips quarantine processing (leaving the file otherwise
  unmodified). The cask is still extracted; the user is
  told to add quarantine handling manually. Sketch shown
  in the entry-point code above.

## Decision points to confirm in W8.2

These are not yet locked; W8.2's Claude Code session
should confirm or revise:

- **Module path for the internal helpers.** Recommendation:
  `lib/homebrew/cask_tools/cask_ast_helpers.rb`, but the
  repo doesn't currently have a `lib/` tree. Alternatives:
  - `cmd/cask_extract/ast_helpers.rb` (sibling subdir
    next to `cmd/cask-extract.rb`)
  - inline private module inside `cmd/cask-extract.rb`
    itself

  For maintainability and testability, a separate file is
  better than inlining. The `lib/` vs `cmd/cask_extract/`
  decision depends on whether other cask-tools commands
  will share AST helpers in the future. If yes, `lib/` is
  preferable. If no, `cmd/cask_extract/` is more local.
  W7's `BundleDiscovery` extraction will face the same
  question; coordinating the two is worth a half hour.

- **macOS gating style in the postflight body.** Confirmed
  recommendation is `next unless OS.mac?`, but other
  options (`if OS.mac?` block, `return unless OS.mac?`,
  no gate) are defensible.

- **Whether to keep `--no-quarantine` as a single flag** or
  split into separate flags for postflight-only /
  caveats-only control. Recommendation: keep one flag; the
  postflight and caveats are paired (xattr removal without
  a warning is bad UX; warning without removal is
  half-done).

- **Exact AST predicate logic, if a check is added at all.**
  The migration plan removes the substring idempotency
  check without a default replacement (see "On idempotency"
  above). If W8.2 or a later session decides a replacement
  is warranted, the simplest variant is "any postflight
  call to `system_command "/usr/bin/xattr"`" — no
  flag-or-arg matching. Implement that variant only if real
  use surfaces duplicate-insertion as an irritant; otherwise
  leave the check out.

- **Whether to fail loudly or quietly on parse errors.**
  The sketch above does `opoo` and continues without
  modifying the cask. Alternative: `odie` and stop the
  extraction entirely. Recommendation: `opoo` because the
  cask itself is still successfully extracted; the
  quarantine handling is opt-in via `--no-quarantine`, so
  failing only that opt-in feature is the proportional
  response.
