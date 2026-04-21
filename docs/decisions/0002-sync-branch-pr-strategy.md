<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# ADR 0002: Sync branch PR existence strategy

## Status
Accepted

## Context

A GitHub Actions workflow synchronizes shared configuration files using a dedicated branch (`sync-shared-config`). The branch is:

- bot-managed
- fully regenerated on each workflow run
- force-pushed on each run (`git push --force`)
- used as the source of a pull request for review and visibility

Workflow concurrency is configured (via GitHub Actions `concurrency`), ensuring that only one instance of the workflow mutates repository state at a time. In-progress runs are canceled in favor of the latest execution, eliminating race conditions between branch updates and PR creation.

Pull requests are not long-lived development artifacts. They represent a view of the current state of the sync branch.

Requirements:

- Ensure an open PR exists for the sync branch when needed
- Create a PR if none exists
- Avoid reliance on assumptions about PR uniqueness across GitHub UI/API edge cases
- Maintain deterministic behavior under serialized workflow execution

Evaluated approaches:

- `gh pr view` → rejected (object-resolution semantics, not set-based query)
- `gh pr list` → valid but requires parsing for control flow
- `gh api` (REST pulls endpoint) → explicit set query over PR collection

## Decision

Use GitHub REST API via `gh api` combined with `jq --exit-status` to determine whether an open PR exists for the sync branch.

PR existence is defined as:

- any open pull request where:
  - `head = <repo_owner>:sync-shared-config`
  - `state = open`

Control flow:

- query `/repos/{owner}/{repo}/pulls`
- filter by `head` and `state=open`
- evaluate result as a set using `jq --exit-status 'length == 0'`
- create PR only when no matching PR exists

## Consequences

### Positive

- Explicit and correct set-based PR existence detection
- Deterministic under serialized execution (concurrency group prevents races)
- Works correctly even if multiple PRs exist for a branch
- Clear separation of responsibilities:
  - git: branch state management
  - GitHub API: PR lifecycle management

### Negative

- Requires `jq`
- More verbose than higher-level CLI abstractions
- Couples logic to REST API response shape

### Neutral

- Workflow concurrency ensures single active execution, simplifying correctness guarantees
- PRs are opportunistic artifacts derived from branch state
- Force-push ensures PR content always reflects latest computed state when present

## Rationale

Although GitHub CLI (`gh pr view`, `gh pr list`) provides higher-level abstractions, they were rejected due to:

- lack of reliable set-based exit-code semantics
- object-resolution ambiguity in multi-match scenarios
- requirement for deterministic boolean control flow

REST API plus `jq --exit-status` provides a direct reduction from a set query to a shell-compatible exit code.

Workflow concurrency removes the need for more complex coordination strategies (e.g., immutable per-run branches or Dependabot-style PR tracking), since only one execution mutates state at a time.

## Future considerations

This design may be simplified if GitHub CLI introduces a native existence-check command with exit-code semantics (e.g. `gh pr exists`).

If requirements shift toward per-run traceability or independent update streams, an immutable branch-per-run model may be reconsidered. However, given current concurrency guarantees and low-frequency updates, the rolling branch model remains optimal.
