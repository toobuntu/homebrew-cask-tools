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
glob patterns for searching man pages. The binary-fallback logic also appears
in both methods.

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
