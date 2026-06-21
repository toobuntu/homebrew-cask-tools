<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# Technical Debt Assessment

Prioritized areas to address, identified during the `brew man` feature work (PR #25).

## High Priority

### 1. Interactive Input Not Mockable End-to-End

`interactive_manpage` and `interactive_all_formula_manpages` in `cmd/man.rb`
read from `$stdin.gets` directly. While unit tests mock `$stdin`, there are no
integration-level tests for the full `--interactive` dispatch (option parsing →
prompt → render).

**Acceptance criteria:**

- Tests cover successful selection, boundary inputs (1 and N), and error cases
  (out-of-range, empty, EOF)
- Both `--find --interactive` and `--list --interactive` dispatch paths are
  exercised

**Files:** `cmd/man.rb`, `test/cmd/man_spec.rb`

### 2. HTML Rendering Code Path Untested

`render_html` in `cmd/man.rb` calls `mandoc -T html` and `exec_browser` but
is never exercised by tests. Failure scenarios (mandoc not found, mandoc
produces empty output) are only checked at runtime.

**Acceptance criteria:**

- Test mandoc-not-found error message
- Test empty-output error path
- Test successful rendering via mock (mandoc output → tempfile → browser)

**Files:** `cmd/man.rb`, `test/cmd/man_spec.rb`

### 3. Prism AST Parse Failures in `cask-extract`

`add_quarantine_postflight` in `cmd/cask-extract.rb` catches Prism parse errors
with `opoo` but proceeds anyway, potentially leaving the cask file in an
unexpected state. Edge cases (malformed Ruby, missing `cask` block, nested
`on_arm`/`on_intel` with `app` stanzas) have limited test coverage.

**Acceptance criteria:**

- Distinguish recoverable vs. fatal parse errors
- Test malformed Ruby, no-cask-block, and nested-app-stanza edge cases
- Verify output messages for each error path

**Files:** `cmd/cask-extract.rb`, `test/cmd/cask-extract_spec.rb`

### 4. `candidate_bundle_names` Missing Direct Tests

The `candidate_bundle_names` method in `cmd/purge-quarantine.rb` extracts names
from metadata JSON and shells out to `pkgutil`. It is only tested indirectly
through higher-level integration tests.

**Acceptance criteria:**

- Unit tests for various metadata JSON shapes
- Mock `pkgutil --pkgs` and `pkgutil --files`
- Test empty metadata, no-app stanzas, and pkgutil failures

**Files:** `cmd/purge-quarantine.rb`, `test/cmd/purge-quarantine_spec.rb`

### 5. Bundler Gem Install Failure in `generate-tap-man-completions`

`Homebrew.install_bundler_gems!(groups: ["man"])` is called unconditionally.
If it fails (network, permissions), the command dies with a cryptic error and
no guidance.

**Acceptance criteria:**

- Wrap gem install in error handling with an informative message
- Test the failure path (mock `install_bundler_gems!` raising)

**Files:** `dev-cmd/generate-tap-man-completions.rb`,
`test/cmd/generate-tap-man-completions_spec.rb`

## Medium Priority

### 6. Duplicate Glob Patterns (DRY Violation)

`collect_manpages` and `find_formula_manpage` in `cmd/man.rb` share similar
glob patterns for searching man pages. The `all_formula_manpages` signature was
refactored to accept a `Formula` object (PR #25), but the underlying glob
patterns in `collect_manpages` and `find_formula_manpage` remain duplicated.
The binary-fallback logic also appears in both methods.

**Acceptance criteria:**

- Extract common glob patterns into a shared helper
- Extract binary fallback into a shared method
- All existing tests pass with identical behavior

**Files:** `cmd/man.rb`

### 7. `escape_glob` Untested

The `escape_glob` helper in `cmd/man.rb` is security-critical (prevents glob
injection) but has no dedicated tests.

**Acceptance criteria:**

- Unit tests for each metacharacter: `*`, `?`, `[`, `]`, `{`, `}`, `\`
- Test combinations and ensure escaped patterns do not match unintended files

**Files:** `test/cmd/man_spec.rb`

### 8. Git Output Not Validated in `cask-extract`

`find_cask_in_history` in `cmd/cask-extract.rb` uses `git log --all` and
`git show`. If git returns empty or unexpected output, the method may write
empty content to the destination file without error.

**Acceptance criteria:**

- Validate git output (non-empty) before returning
- Test git failures (no history, invalid repo, empty output)
- Clear error messages for each failure mode

**Files:** `cmd/cask-extract.rb`, `test/cmd/cask-extract_spec.rb`

### 9. Architecture Documentation Gaps

`docs/architecture.md` lacks rationale for the seven-tier discovery strategy,
why Prism is used (vs. regex), and macOS version compatibility notes.

**Acceptance criteria:**

- Document rationale for each tier
- Add macOS version compatibility notes
- Add performance characteristics/warnings

**Files:** `docs/architecture.md`

## Low Priority

### 10. Completion File Syntax Not Validated

Generated completion files in `completions/{bash,zsh,fish}/` are committed
pre-generated but never syntax-checked. A broken completion file is invisible
until a user sources it.

**Acceptance criteria:**

- CI validates generated bash completions via `shellcheck` or `bash -n`
- Generated zsh completions have correct function signatures
- Document validation in `AGENTS.md` or CI workflow comments

**Files:** `.github/workflows/autogenerated-files.yml`,
`test/cmd/generate-tap-man-completions_spec.rb`

### 11. `generate-tap-man-completions` Sparse Test Coverage

The 380-line command has gaps: `man_page_markdown` string building untested,
`retrieve_pull_requests` error handling untested, stale-file cleanup edge
cases uncovered.

**Acceptance criteria:**

- Test `man_page_markdown` with various banner formats
- Test GitHub API errors in `retrieve_pull_requests`
- Test stale file cleanup with nested directories

**Files:** `test/cmd/generate-tap-man-completions_spec.rb`

### 12. AGENTS.md / CLAUDE.md Content Overlap

The two files have overlapping content. Changes to one should be reflected in
the other, but this is manual and error-prone.

**Acceptance criteria:**

- Consolidate common content (e.g. into `docs/CONTRIBUTING.md`)
- Have `AGENTS.md` and `CLAUDE.md` reference shared content
- Or add CI checks for content drift

**Files:** `AGENTS.md`, `CLAUDE.md`

### 13. Tier 3 hand-parses a fragile, mid-migration metadata schema

Investigating Homebrew/brew#22346 confirmed its absolute-path `target` sibling is
runtime-only (never persisted; only the relative `target:` kwarg is on disk), and that
Tier 2 already reads the resolved path in-process via `Cask::CaskLoader.load(token)` +
`artifact.target`. **Won't-do: do not wire up `brew info` or the JSON sibling. Tier 2 is
already correct and is not changed by this item.**

Tier 3 remains a necessary distinct tier — it must work from the unambiguous Caskroom
directory, not from a token, because (a) `CaskLoader.load` needs a *bare* token while users
may pass a fully-qualified `user/repo/token` to disambiguate a collision, and the qualified
form raises `TapCaskUnavailableError` once the source tap is gone; and (b) the source tap
may be absent entirely. Its current implementation is unsound:

- It reads the versioned metadata file, whose schema is mid-migration: `<token>.json`
  (default/API), `<token>.internal.json` (`HOMEBREW_DEVELOPER`/eventual default; schema is
  `raw_artifacts` tuples, not `artifacts` hashes), and `<token>.rb` (source installs). The
  `**/Casks/<token>.json` glob and `data["artifacts"]` parse silently yield `[]` for the
  latter two.
- It crashes on `target:`-renamed bundles: `Array(a["app"])` includes the nested
  `{"target"=>...}` hash; `dir / hash` raises `TypeError`, caught by the method `rescue`,
  so the tier returns `[]`.

Fix: source Tier 3 from `cask_dir`'s `INSTALL_RECEIPT.json` `uninstall_artifacts` (locally
written by brew, schema-stable across API/internal-API/source installs, already in the
`{"app"=>[...]}` / `{"binary"=>[...]}` shape) rather than the versioned cask file. Apply the
same rename-aware parsing to `candidate_bundle_names`. `config.json` remains the source for
`install_dirs`.

**Acceptance criteria:**
- A cask installed under the internal API (only `<token>.internal.json` on disk) resolves
  via the receipt.
- `app "Src.app", target: "Dst.app"` resolves to `<appdir>/Dst.app`.
- `candidate_bundle_names` never emits a non-String element.
- Tier 3 keys off `cask_dir`, never the (possibly fully-qualified) input token.
- Verify pkg casks expose `pkgutil` patterns under `uninstall_artifacts`; graceful
  fall-through when an older receipt lacks the field.
- Red/green: internal-API fixture, renamed-app fixture.

**Files:** `cmd/purge-quarantine.rb`, `test/cmd/purge-quarantine_spec.rb`. Adjacent to #4;
Tiers 2 and 5–6 are explicitly out of scope and unchanged.

### 14. Suite artifacts skip nested apps (Info.plist filter)

The downstream `Contents/Info.plist` gate in `purge_quarantine_for_cask` is correct for
fonts/plain artifacts (not Gatekeeper-gated) but rejects `suite` containers, whose nested
`.app`s are then never reached. Fix: special-case `Cask::Artifact::Suite` to recurse to its
`*.app` children rather than dropping the filter.

**Acceptance criteria:** a suite cask de-quarantines each nested `.app`; fonts/plain
artifacts remain skipped.

**Files:** `cmd/purge-quarantine.rb`, `test/cmd/purge-quarantine_spec.rb`.

### 15. Binary artifacts from casks are never de-quarantined

purge-quarantine's contract is to clear the Gatekeeper limitation so an installed cask can
run. Binaries a cask ships fall under that contract, but are currently missed:
`Cask::Artifact::Binary` is `Symlinked` (not `Moved`), so Tier 2 excludes it, and the
`Contents/Info.plist` gate in `purge_quarantine_for_cask` skips the staged executable.

The trigger is solely the presence of `com.apple.quarantine`/`com.apple.provenance` — not
notarization or signing state. A quarantined ad-hoc/modified binary is hard-blocked by
Gatekeeper on first run ("…is damaged and can't be opened"); removing the xattr clears the
gate. The tool must therefore apply its existing xattr-presence logic to binary artifacts;
it must NOT attempt to assess signing/notarization (`spctl`/`codesign` are unreliable
proxies and irrelevant to the action taken).

In-bundle binaries (e.g. `…/App.app/Contents/MacOS/foo`) are already covered by the
enclosing app's recursive removal; the genuinely uncovered surface is the standalone binary
staged in the Caskroom and symlinked into `bin`. Idempotent removal makes any overlap
harmless, so no app-vs-standalone distinction is needed in the code.

**Acceptance criteria:**

- Binary artifacts are included as candidates (in addition to `Moved` bundles).
- Operate on the real file via `realpath`, not the `bin` symlink; bypass the
  `Contents/Info.plist` gate for binaries.
- Decision is xattr-presence only; no `spctl`/`codesign` calls.
- Update the command description, README, and `BUNDLE_EXTENSIONS` framing to state that
  cask-shipped binaries are in scope.
- Red/green: a standalone quarantined binary fixture is cleaned; a binary with no
  quarantine xattr is a no-op.

**Files:** `cmd/purge-quarantine.rb`, `test/cmd/purge-quarantine_spec.rb`, `README.md`.
