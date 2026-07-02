<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

last_reviewed: 2026-05-12
-->

# Known bugs and rough edges

This doc catalogs the cask-extract correctness issues that
W8.2 will fix, plus adjacent issues surfaced during the W8
investigation. It is **not** an exhaustive cask-tools tech-
debt register — that scope is covered by `docs/tech-debt.md`
(to be renamed `docs/technical-debt.md` in W8.5) and by the
W8.5 holistic-review workstream tracked in
`~/devel/claude/desktop/workspace/master-plan.md`.

The boundary between "items in this doc" and "items in
tech-debt.md" is: this doc covers issues fixed (or
deliberately not fixed) by the cask-extract Prism → CaskAST
migration plan (W8.2). Tech-debt.md covers everything else.
Tech-debt items #3 (Prism AST parse failures) and #8 (git
output not validated) overlap with this doc and are
cross-referenced where appropriate.

---

## Part 1 — cask-extract bugs being fixed by W8.2

### 1.1 Substring idempotency check is unreliable

**Where:** `cmd/cask-extract.rb`, in `add_quarantine_postflight`:

```ruby
if content.include?("com.apple.quarantine")
  ohai "#{cask_path.basename} already has quarantine handling; skipping."
  return
end
```

**Failure modes:**

- **False positive — comment.** A cask containing the
  comment `# Note: don't strip com.apple.quarantine here`
  is skipped even though it has no actual handling.
- **False positive — listing-only.** A cask whose postflight
  body calls `xattr -l com.apple.quarantine` (listing, not
  deleting) is skipped.
- **False positive — caveats text.** A cask whose `caveats`
  mentions Gatekeeper or quarantine in human prose is
  skipped.
- **False negative — different xattr.** A cask that strips
  `com.apple.provenance` but not `com.apple.quarantine` is
  treated as "needs handling" — the new postflight is
  inserted alongside the existing one, producing a duplicate
  pattern even though both attributes commonly need removal.

**Fix in W8.2:** the substring check is replaced with a
marker-comment scheme. Each inserted stanza is preceded by
a unique sentinel comment line
(`# cask-extract: quarantine xattr removal` above the
postflight, `# cask-extract: Gatekeeper bypass warning`
above the caveats). The idempotency predicate becomes
`content.include?(marker)` for each. The markers are
greppable, survive `rubocop --autocorrect`, have
effectively zero false-positive rate against arbitrary
cask content, and double as a deliberate manual opt-out
(a maintainer who adds the marker comment to a hand-rolled
stanza opts out of re-insertion on subsequent
`cask-extract --no-quarantine` runs). The design parallels
Homebrew's own `.github/workflows/sync-shared-config.yml`
marker line. See `01-ast-migration-plan.md` § "Idempotency
via marker comments" for the full design and rationale.

Original idea: the maintainer in chat, 2026-05-12.

### 1.2 Top-level-only postflight traversal asymmetric with app-name extraction

**Where:** `cmd/cask-extract.rb`, in the search for an
existing `postflight` block:

```ruby
existing_pf = stmts.find do |n|
  n.is_a?(Prism::CallNode) && n.name == :postflight && n.block.is_a?(Prism::BlockNode)
end
```

`stmts` is `cask_block_stmts(cask_block)`, which returns
**only top-level** statements. Compare to
`extract_app_names_from_node`, which recurses:

```ruby
def extract_app_names_from_node(node)
  app_names = T.let([], T::Array[String])

  if node.is_a?(Prism::CallNode) && node.name == :app
    first_arg = node.arguments&.arguments&.first
    app_names << first_arg.content if first_arg.is_a?(Prism::StringNode)
  end

  node.compact_child_nodes.each do |child|
    app_names.concat(extract_app_names_from_node(child))
  end

  app_names
end
```

**The bug:** app names are collected from nested `on_arm` /
`on_intel` / `if` blocks (good — we want to clean every
app the cask installs), but the postflight search only
looks at the top level (bad — a cask with its postflight
inside an `on_intel do` is treated as "no existing
postflight", and a new top-level postflight is inserted).
The asymmetry is silent — there's no warning.

The downstream effect is bounded: in the
worst case the cask ends up with two postflight stanzas
(the original Intel-only one, plus our new top-level one).
Both will run on Intel; only ours runs on ARM. Not strictly
wrong for the quarantine-removal use case (we want xattr
removal on both arches), but cosmetically untidy.

**Fix in W8.2:** the migration adopts top-level insertion
as the **deliberate** policy rather than the accidental
one. `add_top_level_block_stanza` always inserts at the
canonical top-level position. Existing nested postflight
stanzas are left untouched. The Cask DSL runs all
postflight blocks regardless of nesting, so duplicate
behavior is harmless.

### 1.3 Manual string-offset insertion is brittle

**Where:** `cmd/cask-extract.rb`, in `append_to_postflight`
and `insert_new_postflight`:

```ruby
def append_to_postflight(content, pf_block, xattr_lines)
  closing_offset = pf_block.closing_loc.start_offset
  line_start = line_start_offset(content, closing_offset)
  prefix = content[line_start...closing_offset]

  if T.must(prefix).strip.empty?
    content.dup.insert(line_start, "    #{xattr_lines}\n")
  else
    content.dup.insert(closing_offset, "\n    #{xattr_lines}\n  ")
  end
end
```

**Brittleness sources:**

- Unusual formatting (multi-line block opener like
  `postflight do |x|\n` on a separate line from `do`)
  shifts the offset calculation.
- Blank lines around the closing `end` change the prefix
  inspection.
- Comment lines immediately above the insertion point are
  handled by neither branch; the new content gets inserted
  in front of the comment rather than after it.
- Hard-coded indentation (`    ` four spaces) assumes a
  specific surrounding context. A cask file with
  non-standard indentation (rare but legal Ruby) gets
  mis-indented output.

**Fix in W8.2:** replace with
`Parser::Source::TreeRewriter`. The TreeRewriter operates
on byte ranges semantically anchored to AST nodes; it
handles comments and whitespace through its standard
mechanisms. The insertion API
(`tree_rewriter.insert_before(range, text)` /
`tree_rewriter.insert_after(range, text)`) is the same API
`FormulaAST` uses internally, with established behavior
across the upstream test suite.

### 1.4 Caveats injection is absent

**Where:** the original `--no-quarantine` design called for
both a `postflight` and a `caveats` stanza. The current
implementation ships only the postflight.
`docs/architecture.md` describes the postflight injection
in detail but doesn't mention caveats. `cmd/cask-extract.rb`
has `add_quarantine_postflight` but no
`add_quarantine_caveats`.

**The gap:** a cask extracted with `--no-quarantine` gets
its Gatekeeper protections bypassed silently. The user
sees an `opoo` message at extraction time, but the
extracted cask itself has no in-file warning. Downstream
users who install the cask (e.g., from a personal tap)
have no indication that Gatekeeper has been bypassed for
that cask.

**Fix in W8.2:** add a top-level `caveats` stanza with a
human-readable warning. Multiple `caveats` stanzas in a
cask concatenate at runtime; if a cask already has caveats,
ours appears alongside (not in place of) them. Sample text
to be locked in W8.2; rough shape:

```
caveats <<~EOS
  Gatekeeper has been bypassed for this cask.
  The com.apple.quarantine attribute is removed from
  installed bundles via a postflight block. Verify the
  safety of this software before launching it.
EOS
```

### 1.5 Prism + manual offsets is out of step with PR #22220

**Where:** the entire `add_quarantine_postflight` code path
(plus the helpers it calls) uses Prism for parsing and
manual string-offset arithmetic for mutation. Homebrew's
upstream direction, set by PR #22220 (merged 2026-05-11),
is `rubocop-ast` for parsing and `Parser::Source::TreeRewriter`
for mutation.

**The gap:** the implementation is incompatible with
upstreaming. Any future PR that wanted to upstream
quarantine-handling helpers (this is not the plan — see
`04-upstream-strategy.md` when it lands — but if it were)
would have to be rewritten first. It's also incompatible
with the existing `Utils::AST::CaskAST` (which provides
`replace_first_stanza_value`, `replace_stanza_value`,
`depends_on_macos?`) since those operate on rubocop-ast
nodes, not Prism nodes.

**Fix in W8.2:** the migration adopts CaskAST + TreeRewriter
throughout. This brings cask-extract into alignment with
the upstream direction. Whether or not the
cask-tools-internal helpers are ever upstreamed (see W8.3),
the foundation is consistent.

### 1.6 STANZAS_AFTER_POSTFLIGHT duplicates rubocop-cask cop knowledge

**Where:** `cmd/cask-extract.rb`:

```ruby
STANZAS_AFTER_POSTFLIGHT = T.let([
  :uninstall_preflight, :uninstall_postflight, :uninstall, :zap, :caveats
].freeze, T::Array[Symbol])
```

This is a subset of the canonical Cask Cookbook stanza
order, encoded for one specific purpose: finding the
anchor stanza for inserting a new postflight. The full
canonical order is encoded in `rubocop-cask`'s
`Cop::Cask::StanzaOrder` cop. cask-extract duplicates a
fragment of that knowledge.

**The gap:** drift. If Homebrew adds a new cask stanza
that should appear between `postflight` and `uninstall`
(unlikely but possible), the cop is updated but cask-extract
isn't, and the new postflight ends up inserted in the
wrong relative position. Silent.

**Fix in W8.2:** the migration uses the full canonical
stanza order via a cask-tools-internal constant
(initially) or via an upstream `CASK_COMPONENT_PRECEDENCE_LIST`
(if W8.3 lands). Comments in the local constant point at
the Cookbook and the cop as canonical references.

### 1.7 No tests cover the AST mutation paths

**Where:** `test/cmd/cask-extract_spec.rb` covers
`resolve_cask_spec`, `extracted_cask_token`,
`parse_version_from_content`, `destination_cask_path`, and
parts of the git-history extraction. It does **not** cover
`add_quarantine_postflight`, `find_cask_block`,
`cask_block_stmts`, `extract_app_names`,
`extract_app_names_from_node`, `build_xattr_lines`,
`append_to_postflight`, `insert_new_postflight`, or
`line_start_offset`.

**The gap:** the most structurally complex code in the file
is untested. Regression risk on any modification.

**Fix in W8.2:** the migration adds unit tests for
`add_top_level_block_stanza` (round-trip with several cask
shapes), a round-trip parsing test, and an integration
test for the full `add_quarantine_handling` flow. See
`01-ast-migration-plan.md` § "Test coverage" for the case
list.

This supersedes existing tech-debt item #3 (Prism AST
parse failures), since the Prism code path is removed.

---

## Part 2 — Adjacent issues surfaced in this investigation

These are real but minor issues not in cask-extract's
scope. They came up while investigating the
"`brew man` doesn't find system pages" suspicion and are
recorded here so they aren't lost.

### 2.1 `cmd/man.rb`'s `list_manpages` has inconsistent empty-result UX

**Where:** `cmd/man.rb`. Two paths handle empty `collect_manpages`
results differently:

`interactive_manpage` exits cleanly:

```ruby
def interactive_manpage(name)
  choices = collect_manpages(name)
  odie "No man pages found for: #{name}" if choices.empty?
  # ...
end
```

`list_manpages` does not:

```ruby
def list_manpages(name)
  results = collect_manpages(name)

  with_pager(lines: results.length + 1) do
    ohai "#{name} found in:"
    results.each do |provider, file|
      puts "  #{provider}: #{file}"
    end
  end
end
```

**The failure mode:** when results is empty, `list_manpages`
outputs `==> openssl found in:` followed by nothing, which
the user reasonably interprets as "the command broke or
hung." This was the symptom that prompted the
"doesn't find system pages" investigation. (Resolved as
not-a-bug for openssl specifically — see § 3.1 below —
but the empty-result UX is a real issue regardless of
which formula or page name triggers it.)

**Fix (one-line, not part of W8.2):** add
`odie "No man pages found for: #{name}" if results.empty?`
before `with_pager`. Mirrors `interactive_manpage`'s
handling. No quirk list, no per-formula special cases.

**Workstream assignment:** not W8 (which is cask-extract-
specific). Add to `docs/tech-debt.md` as a new item
"man.rb `--find` lacks empty-result message" so W8.5's
refresh picks it up.

---

## Part 3 — Investigated, not a bug

Items recorded here have a paper trail so they aren't
re-investigated in future sessions.

### 3.1 `/usr/bin/openssl` has no system man page on modern macOS

**Symptom:**

```
$ brew man --find openssl
==> openssl found in:
  libressl: /opt/homebrew/opt/libressl/share/man/man1/openssl.1
  openssl:  /opt/homebrew/opt/openssl/share/man/man1/openssl.1ssl
  openssl@4: /opt/homebrew/opt/openssl@4/share/man/man1/openssl.1ssl

$ find /usr/share/man -name "*openssl*"
(no output)
```

Homebrew formula man pages are found; no system man page
is found. Initially read as a bug in `cmd/man.rb`.

**Resolution:** not a bug. macOS ships `/usr/bin/openssl`
(Apple's LibreSSL port) but does **not** install the
corresponding man page in `/usr/share/man/` or in the
Xcode SDK manpaths. The binary is retained for legacy
script compatibility; the documentation has been removed.

`brew man --find curl curl` correctly returns the system
curl page at `/usr/share/man/man1/curl.1`, confirming the
implementation can find system pages when they exist.

**Background:** Apple has been progressively deprecating
user-facing OpenSSL/LibreSSL since approximately macOS 10.7
(Lion). On older macOS releases (Mojave / 10.14 era), the
man page was installed and `man openssl` worked. By
modern macOS (Big Sur / 11.x and later, certainly Sequoia),
Apple has removed it from system man paths. Inferred
rationale: Apple wants developers to use Security framework,
Network framework, and CryptoKit instead of the openssl
CLI; removing the man page removes a documentation surface
that would otherwise encourage shell-script use of
`/usr/bin/openssl`. Not officially documented anywhere.

**Action:** none in cask-tools code. No special-casing in
`cmd/man.rb` — a quirk list of "things macOS deprecated"
is not a maintainable shape. The general empty-result UX
fix (§ 2.1 above) covers this and every analogous case
without enumerating quirks.

### 3.2 Tap-based external commands don't need the `brew-` prefix

**Symptom:** cask-tools' commands are `cmd/cask-extract.rb`,
`cmd/man.rb`, `cmd/purge-quarantine.rb` — no `brew-`
prefix. Homebrew's
[External-Commands.md](https://github.com/Homebrew/brew/blob/main/docs/External-Commands.md)
states that external Ruby commands "should be named
`brew-extcmd.rb`". Initially read as a possible bug.

**Resolution:** not a bug. External-Commands.md describes
**two distinct mechanisms** that are easy to conflate:

1. **PATH-based external commands** (the legacy mechanism
   the docs lead with): must be named `brew-extcmd` (or
   `brew-extcmd.rb`), `chmod +x`, live somewhere on
   `$PATH`. Homebrew dispatches by `exec`ing the script
   (shell) or `require`ing it (Ruby).
2. **Tap-based external commands** (the modern,
   `AbstractCommand` mechanism, also documented in the
   same file's Ruby template section): live in a tap's
   `cmd/` (or `dev-cmd/`) directory, do **not** need a
   `brew-` prefix, must have class
   `Homebrew::Cmd::Foo < AbstractCommand`. Homebrew
   discovers these by enumerating tap `cmd/` directories,
   not by name match.

The
[DeepWiki summary of brew.rb](https://deepwiki.com/Homebrew/brew/3-command-line-interface)
makes the dispatch logic explicit: `Library/Homebrew/brew.rb:131-134`
loads tap `cmd/` files by directory enumeration;
`:135-140` execs PATH-based `brew-<name>` executables.

cask-tools uses the tap-based mechanism. `brew tap-info`
confirms the three commands are discovered correctly.

**Action items:**

- **W8.4 (optional):** small docs PR to upstream
  `External-Commands.md` clarifying that the `brew-`
  prefix applies only to PATH-based commands, not tap
  `cmd/` files. Low-stakes, would be welcomed. Tracked in
  master-plan.md.
- **CLAUDE.md / AGENTS.md note (W8.5 scope):** a one-paragraph
  note for future contributors who read External-Commands.md
  and try to "fix" the missing prefix. Trivial; can go in
  CLAUDE.md's "Homebrew-specific conventions" section.

### 3.3 The "extend `brew man` to query SS64 (or man.openbsd.org) on empty result" suggestion

**Context:** while investigating § 3.1, it was observed
that SS64 (https://ss64.com/mac/) does host a community
mirror of an openssl(1) man page, suggesting `brew man`
could fall back to a network query when local search comes
up empty.

**Resolution:** rejected. Four reasons:

1. **Staleness.** SS64's content has unrelated text
   intermixed (the maintainer observed a reference to
   `Install macOS Sequoia 15.7.4` inside the openssl
   page). It's a community mirror, not authoritative
   documentation.
2. **Contract violation.** `brew man` advertises finding
   **local** man pages. Surreptitiously consulting the web
   changes the contract from "where on disk is this man
   page?" to "what does this thing do?" — a different
   question that belongs in a different command.
3. **Performance surprise.** Users expect `man` to be
   instant. A network fallback adds 200-2000ms on misses
   and depends on connectivity.
4. **Scope creep.** `brew man` is a thin, well-scoped
   utility. Online documentation lookup belongs in a
   separate command (`brew docs <thing>`, perhaps) if
   wanted at all.

**Action:** none. The empty-result UX fix in § 2.1 is the
right response to the user-confusion case that motivated
the suggestion.

---

## Part 4 — Relationship to existing `docs/tech-debt.md`

(Note: `tech-debt.md` will be renamed to `technical-debt.md`
in W8.5 per the org-wide convention. References below use
the current filename.)

- **#3** (Prism AST parse failures in cask-extract) —
  **superseded by W8.2.** The Prism code path is removed
  entirely. Remove from tech-debt.md when W8.2 ships.
- **#8** (git output not validated in cask-extract) —
  **adjacent but distinct.** The AST migration does not
  touch `find_cask_in_history`; that helper's git-output
  validation gap remains. Keep in tech-debt.md.

All other items in tech-debt.md (everything except #3
and #8 above) are unrelated to the cask-extract AST
migration and stay where they are. W8.5 will validate
each against current code.

---

## Part 5 — Out of scope for W8 (flagged for W8.5)

The W8 investigation focused on cask-extract specifically.
A holistic cask-tools code review has not been done in this
session sequence. The following are explicitly out of scope
for W8 and will be addressed in W8.5:

- `dev-cmd/generate-tap-man-completions.rb` beyond its
  first 120 lines (~260 unread lines).
- `test/cmd/purge-quarantine_spec.rb` (full file).
- `test/cmd/generate-tap-man-completions_spec.rb` (full
  file).
- The remainder of `test/cmd/cask-extract_spec.rb` and
  `test/cmd/man_spec.rb`.
- `README.md`, `AGENTS.md`, `docs/shared-guidelines.md`,
  `docs/decisions/0001-pipx-for-ci-python-tools.md`,
  `docs/decisions/0002-sync-branch-pr-strategy.md`,
  `docs/homebrew-brew-external-dev-cmd.patch`.
- All contents of `scripts/`, `completions/`, `manpages/`,
  `.github/workflows/`, `.githooks/`, `LICENSES/`.
- `.mcp.json`, `.vscode/` configuration.
- Git history beyond the two most recent commits.

W8.5 will read these systematically, validate the existing
tech-debt items against current code, and produce a fresh
`technical-debt.md` that supersedes today's `tech-debt.md`.
