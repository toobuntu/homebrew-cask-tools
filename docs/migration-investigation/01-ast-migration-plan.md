<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

last_reviewed: 2026-05-12
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

**Note on Prism.** Prism remains in active Homebrew use for
other purposes (notably
`Library/Homebrew/dev-cmd/typecheck.rb`, which uses
`Prism.parse` for RBI file manipulation). The choice of
rubocop-ast for cask-extract is not a rejection of Prism;
it's driven by tool fit: `Parser::Source::TreeRewriter`
(the comment-aware, conflict-detecting source mutator we
need for stanza insertion) ships with the `parser` gem on
which `rubocop-ast` is built. Prism does not have an
equivalent. A Prism-based migration would still require
manual byte-offset insertion — the same brittleness we're
leaving behind.

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

  helpers.insert_quarantine_postflight(app_names) \
    unless helpers.quarantine_handler_present?
  helpers.insert_gatekeeper_caveats \
    unless helpers.gatekeeper_warning_present?

  cask_path.write(ast.process)

  # Mitigate any TreeRewriter formatting quirks. Per
  # Homebrew/brew AGENTS.md key guideline #8, shell out
  # via HOMEBREW_BREW_FILE rather than requiring cmd/ or
  # invoking a shim path directly. `brew rubocop` runs
  # Homebrew's bundled rubocop. `--config` is required;
  # rubocop errors without it. Excludes Sorbet sigil cops
  # and the frozen-string-literal cop — neither applies to
  # cask source. `must_succeed: false` so an uncorrectable
  # offense doesn't block extraction.
  system_command HOMEBREW_BREW_FILE,
                 args: [
                   "rubocop",
                   "--config", "#{HOMEBREW_LIBRARY}/.rubocop.yml",
                   "--except", "Sorbet/StrictSigil,Sorbet/TrueSigil,Style/FrozenStringLiteralComment",
                   "--autocorrect",
                   cask_path.to_s,
                 ],
                 must_succeed: false

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
  containing the full source (marker comment +
  `on_macos do ... end` wrapper + inner stanza), indented
  appropriately. Mirrors `FormulaAST#add_stanza` but for
  block-form stanzas and respecting the cask ordering.

This helper lives in
`lib/homebrew/cask_tools/cask_ast_helpers.rb` (path to be
confirmed during W8.2; see "Decision points" below) in this
tap initially. It is an upstream candidate (W8.3) but does
not depend on upstream landing it.

The cask stanza-order constant is **not** maintained
locally. cask-tools consumes it directly from Homebrew core
via `require "rubocops/cask/constants/stanza"`, then
references `RuboCop::Cask::Constants::STANZA_ORDER` (see
"Stanza ordering" below).

### Idempotency via marker comments

The original Prism implementation guards against duplicate
insertion with
`if content.include?("com.apple.quarantine")`. The migration
replaces it with a **marker-comment scheme**: each inserted
stanza is preceded by a unique sentinel comment line that
cask-extract owns and grep can reliably find.

```ruby
# cask-extract: quarantine xattr removal
on_macos do
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Foo.app"]
  end
end

# cask-extract: Gatekeeper bypass warning
on_macos do
  caveats <<~EOS
    Gatekeeper has been bypassed for this cask. The
    com.apple.quarantine attribute is removed from
    installed bundles via a postflight block. Verify the
    safety of this software before launching it.
  EOS
end
```

The idempotency predicates are:

```ruby
QUARANTINE_MARKER = "# cask-extract: quarantine xattr removal"
CAVEATS_MARKER = "# cask-extract: Gatekeeper bypass warning"

def quarantine_handler_present? = @ast.source.include?(QUARANTINE_MARKER)
def gatekeeper_warning_present? = @ast.source.include?(CAVEATS_MARKER)
```

Why this design:

- **Specific.** The marker strings are unique enough that
  arbitrary cask content won't match by accident. No
  false positives from comments, `xattr -l` invocations,
  or `caveats` strings that happen to mention the xattr.
- **Greppable.** Operators can
  `grep -rn 'cask-extract:' Casks/` to find every cask that
  cask-extract has touched. Useful for audits.
- **Survives `rubocop --autocorrect`.** Rubocop doesn't
  strip comments. The marker persists through formatting
  fixups.
- **Manual opt-out.** A maintainer who hand-rolls a
  quarantine-removal postflight and prefixes it with the
  marker comment opts out of re-insertion on subsequent
  `cask-extract --no-quarantine` runs. Documented behavior.
- **Parallels existing Homebrew patterns.** Homebrew's own
  `.github/workflows/sync-shared-config.yml` uses an
  identical comment-prefix idiom (lines 89-91) to mark
  generated content. The maintainer surfaced this parallel
  in chat on 2026-05-12.

The substring check (and its known false-positive /
false-negative modes) is documented in
`02-known-bugs-and-rough-edges.md` § 1.1.

### The macOS gating question

The `xattr` binary and the quarantine attribute are
macOS-only concepts. The Gatekeeper warning is
macOS-specific prose. Both should run only on macOS
installs.

Three gating styles were considered:

1. **No gating.** Plain `postflight do ... end` and
  `caveats <<~EOS ... EOS`. Relies on cask DSL semantics
  (most casks are macOS-only by default).
2. **Body-level gating.** `next unless OS.mac?` (or
  equivalent) inside the postflight body; a conditional
  around `caveats`.
3. **`on_macos do` wrappers** around the stanzas.

**Recommendation: option 3 (`on_macos do` wrappers).**
Verified via rubocop on test casks. Rationale:

- Option 2 trips the `Homebrew/MoveToExtendOS` cop. Every
  body-level `OS.mac?` / `OS.linux?` variant
  (`if OS.mac?`, `next unless OS.mac?`,
  `return unless OS.mac?`) is flagged. The cop directs the
  fix to `extend/os/`, which doesn't apply to cask source.
- Option 1 is technically functional but unhelpful as
  Linux cask support grows. A future Linux user installing
  the cask sees an `xattr` invocation fail noisily; we can
  do better.
- Option 3 passes rubocop, makes the macOS-only intent
  explicit, and — contrary to an earlier concern — does
  not introduce a stanza-ordering quandary. The cask DSL's
  `on_macos` and `on_linux` are NOT in
  `ON_SYSTEM_METHODS_STANZA_ORDER` (see
  `Library/Homebrew/rubocops/cask/constants/stanza.rb` in
  Homebrew/brew — only the macOS-version symbols plus
  `on_arm` / `on_intel` participate in that ordering).
  Multiple top-level `on_macos do` blocks at arbitrary
  positions all pass rubocop, confirmed empirically.

The inserted postflight and caveats are both wrapped in
fresh `on_macos do` blocks (one per stanza, not a shared
wrapper). One-per-stanza keeps the marker-comment
idempotency local to each insertion and keeps the diff
semantics simple (insert two top-level constructs in their
canonical positions).

### Stanza ordering

The canonical cask stanza order is encoded in Homebrew/brew
at `Library/Homebrew/rubocops/cask/constants/stanza.rb` as
`RuboCop::Cask::Constants::STANZA_ORDER` (the flattened
`STANZA_GROUPS` array). This constant is already structurally
reusable: `Library/Homebrew/rubocops/os_depends_on.rb`
references it as `CASK_STANZA_ORDER = T.let(RuboCop::Cask::Constants::STANZA_ORDER, T::Array[Symbol])`,
and `Library/Homebrew/rubocops/cask/ast/stanza.rb` consumes
it directly as `Constants::STANZA_ORDER`. cask-tools does
the same:

```ruby
require "rubocops/cask/constants/stanza"

module Homebrew
  module CaskTools
    module CaskASTHelpers
      STANZA_ORDER = RuboCop::Cask::Constants::STANZA_ORDER

      # ... add_top_level_block_stanza implementation ...
    end
  end
end
```

No local constant. If Homebrew adds a new cask stanza, the
cop's constant updates and our consumer picks it up
automatically. No drift risk. No upstream refactor needed.

(An earlier draft of this plan proposed refactoring the
constant into `Library/Homebrew/ast_constants.rb`; that was
based on a misreading. The constant is already in the right
shape and the right location.)

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
- Unit tests for `quarantine_handler_present?` /
  `gatekeeper_warning_present?`:
  - cask with neither marker — both predicates false
  - cask with quarantine marker only — quarantine
    predicate true, caveats predicate false
  - cask with caveats marker only — mirror of the above
  - cask with both markers — both predicates true
  - cask with marker text embedded in a `caveats "..."`
    string (rather than as a comment) — predicate false
    if the implementation requires it to be a comment;
    true if substring-match is used. The recommendation is
    plain substring match (`@ast.source.include?(MARKER)`),
    accepting that an unusually self-referential cask could
    trick it; trade-off documented.
- Unit test for `rubocop --autocorrect` integration: a
  deliberately under-indented inserted body becomes
  correctly indented after the autocorrect pass.
- Round-trip parsing test: after `ast.process` (and
  optional autocorrect), the resulting source parses again
  as a valid Ruby file and as a valid cask block (no
  mid-block syntax errors).
- Integration test for a sample cask file with the full
  `add_quarantine_handling` flow, asserting the resulting
  source is valid Ruby and parses as a cask block with the
  expected stanza count, ordering, both marker comments
  present, and a `system_command "/usr/bin/xattr"` call
  inside the inserted postflight body.
- Idempotency integration test: running
  `add_quarantine_handling` twice on the same cask
  produces the same source as running it once.

## Internal vs upstream split

**What lives in this tap** (`cmd/cask-extract.rb` plus the
new helpers module):

- Quarantine xattr removal policy (which xattrs, which
  paths, the exact `system_command` invocation shape).
- The Gatekeeper-warning caveats prose.
- The marker-comment strings
  (`# cask-extract: quarantine xattr removal`,
  `# cask-extract: Gatekeeper bypass warning`) and the
  idempotency predicates that consume them.
- The `add_top_level_block_stanza` helper.
- The `rubocop --autocorrect` post-pass invocation.

**What is a candidate for upstream contribution in W8.3:**

- `Utils::AST::CaskAST#add_stanza_after`, mirroring
  `FormulaAST#add_stanza`. Existing upstream consumers:
  none yet. Motivated by potential future use in
  `bump-cask-pr` (which currently only replaces values) and
  by third-party taps doing AST mutation. Acceptance odds
  reduced (likely 30/70 against) since there's no existing
  upstream consumer to point at; framing is
  "enabling-infrastructure for third-party taps doing AST
  mutation."

**What is NOT a candidate for upstream contribution:**

- The cask stanza-order constant. Already reusable at
  `RuboCop::Cask::Constants::STANZA_ORDER` in
  `Library/Homebrew/rubocops/cask/constants/stanza.rb`. No
  refactor needed; cask-tools consumes it directly.
- The quarantine policy, the xattr command shape, the
  caveats prose, the marker-comment strings. These are
  quarantine-specific application logic, not AST
  infrastructure.
- An `each_stanza_with_body` (or `enclosing_blocks`)
  traversal helper. Originally proposed to support an
  AST-predicate idempotency check; not needed with the
  marker-comment approach.
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
   Implements `add_top_level_block_stanza` plus the
   marker-comment predicates
   (`quarantine_handler_present?`,
   `gatekeeper_warning_present?`). Imports
   `RuboCop::Cask::Constants::STANZA_ORDER` via
   `require "rubocops/cask/constants/stanza"`.
2. **Migrate the cask-extract entry point** from
   `add_quarantine_postflight` to
   `add_quarantine_handling`. Delete the Prism-specific
   helpers (`find_cask_block`, `cask_block_stmts`, the
   Prism-based `extract_app_names`, `append_to_postflight`,
   `insert_new_postflight`, `line_start_offset`, the
   `STANZAS_AFTER_POSTFLIGHT` constant, and the substring
   `if content.include?("com.apple.quarantine")` guard).
   `extract_app_names` is preserved but ported to walk the
   rubocop-ast tree rather than Prism's.
3. **Add caveats injection** via the same flow.
4. **Add the `rubocop --autocorrect` post-pass** invocation
   after `cask_path.write(ast.process)`. Uses Homebrew's
   rubocop config with Sorbet sigil cops and
   `Style/FrozenStringLiteralComment` excluded (the cask
   DSL doesn't use these). Run with `must_succeed: false`
   so a rubocop offense that can't be autocorrected doesn't
   block the extraction.
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
- **Cookbook stanza order drift.** Not applicable to this
  migration. The cask stanza order is consumed from
  Homebrew core's `RuboCop::Cask::Constants::STANZA_ORDER`
  via `require`; if Homebrew adds a stanza, the cop's
  constant updates and our consumer picks it up
  automatically. No local copy to drift.
- **TreeRewriter formatting quirks.** TreeRewriter inserts
  text at byte offsets and doesn't reformat surrounding
  source. If the inserted body's indentation doesn't match
  the surrounding cask block exactly, the output is
  functional but ugly. **Primary mitigation:** the
  `rubocop --autocorrect` post-pass in migration step 4
  fixes indentation, trailing whitespace, and most other
  formatting quirks automatically. **Secondary
  mitigation:** build the inserted body with the correct
  two-space indentation up front, so autocorrect has less
  to do.
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

- **macOS gating style.** Confirmed: `on_macos do` wrappers
  around the inserted postflight and caveats. Body-level
  `OS.mac?` variants all trip
  `Homebrew/MoveToExtendOS`; the cask DSL's `on_macos` /
  `on_linux` are not in `ON_SYSTEM_METHODS_STANZA_ORDER` so
  wrapping is structurally clean. See "The macOS gating
  question" above.

- **Whether to keep `--no-quarantine` as a single flag** or
  split into separate flags for postflight-only /
  caveats-only control. Recommendation: keep one flag; the
  postflight and caveats are paired (xattr removal without
  a warning is bad UX; warning without removal is
  half-done).

- **Marker comment exact wording.** Recommended:
  `# cask-extract: quarantine xattr removal` and
  `# cask-extract: Gatekeeper bypass warning`. Unique
  enough to avoid arbitrary-content matches; descriptive
  enough that a reader who encounters one without context
  understands what it marks. Lock in W8.2 with the test
  cases serving as the regression baseline. If the wording
  changes, the change is breaking for existing extracted
  casks (their markers wouldn't match the new predicates).
  Worth pinning early.

- **Whether to fail loudly or quietly on parse errors.**
  The sketch above does `opoo` and continues without
  modifying the cask. Alternative: `odie` and stop the
  extraction entirely. Recommendation: `opoo` because the
  cask itself is still successfully extracted; the
  quarantine handling is opt-in via `--no-quarantine`, so
  failing only that opt-in feature is the proportional
  response.
