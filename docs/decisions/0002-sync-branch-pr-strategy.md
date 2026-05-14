---
# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

number: 2
title: Sync branch PR existence strategy
status: accepted
date: 2026-05-13
decision-makers:
  - toobuntu
---

# Sync branch PR existence strategy

## Context and Problem Statement

A GitHub Actions workflow synchronizes shared configuration files using
a dedicated branch (`sync-shared-config`). The branch is:

* bot-managed
* fully regenerated on each workflow run
* force-pushed on each run (`git push --force`)
* used as the source of a pull request for review and visibility

Workflow concurrency is configured (via GitHub Actions `concurrency`),
ensuring that only one instance of the workflow mutates repository state
at a time. In-progress runs are canceled in favor of the latest
execution, eliminating race conditions between branch updates and PR
creation.

Pull requests are not long-lived development artifacts. They represent
a view of the current state of the sync branch.

The workflow needs to ensure an open PR exists for the sync branch when
needed, creating one if none exists. The detection mechanism must:

* avoid reliance on assumptions about PR uniqueness across GitHub UI/API
  edge cases
* maintain deterministic behavior under serialized workflow execution
* be representable as a single shell-compatible boolean for control flow

## Decision Drivers

* Determinism under serialized execution
* Set-based query semantics — existence-of-any-match, not
  first-match-found
* No reliance on object-resolution edge cases in higher-level CLI
  commands
* Direct shell exit code for use in workflow control flow
* Minimal dependency surface — expressible with tools already required
  for the workflow's other operations

## Considered Options

* **`gh pr view`** — object-resolution semantics; not set-based. Rejected.
* **`gh pr list`** — valid but requires output parsing for control flow.
* **`gh api` REST `/pulls` endpoint + `jq --exit-status`** — explicit
  set query over the PR collection; `jq --exit-status` produces a
  direct shell exit code.

## Decision Outcome

Chosen option: **`gh api` REST query + `jq --exit-status`**, because it
gives explicit set-based detection with deterministic
shell-compatible control flow, and works correctly even if multiple PRs
exist for a branch.

PR existence is defined as: any open pull request where
`head = <repo_owner>:sync-shared-config` and `state = open`.

Control flow:

* query `/repos/{owner}/{repo}/pulls`
* filter by `head` and `state=open`
* evaluate result as a set using `jq --exit-status 'length == 0'`
* create PR only when no matching PR exists

### Consequences

* Good, because PR existence detection is explicit and correct.
* Good, because it is deterministic under serialized execution
  (concurrency group prevents races).
* Good, because it works correctly even if multiple PRs exist for a
  branch.
* Good, because responsibilities are clearly separated — git manages
  branch state, GitHub API manages PR lifecycle.
* Bad, because it requires `jq`.
* Bad, because it is more verbose than higher-level CLI abstractions
  like `gh pr view`.
* Bad, because it couples logic to REST API response shape.
* Neutral, because workflow concurrency ensures single active
  execution, simplifying correctness guarantees.
* Neutral, because PRs are opportunistic artifacts derived from branch
  state.
* Neutral, because force-push ensures PR content always reflects latest
  computed state when present.

## More Information

Although GitHub CLI (`gh pr view`, `gh pr list`) provides higher-level
abstractions, they were rejected due to lack of reliable set-based
exit-code semantics, object-resolution ambiguity in multi-match
scenarios, and the requirement for deterministic boolean control flow.

REST API plus `jq --exit-status` provides a direct reduction from a set
query to a shell-compatible exit code.

Workflow concurrency removes the need for more complex coordination
strategies (e.g., immutable per-run branches or Dependabot-style PR
tracking), since only one execution mutates state at a time.

### Future considerations

This design may be simplified if GitHub CLI introduces a native
existence-check command with exit-code semantics (e.g.
`gh pr exists`).

If requirements shift toward per-run traceability or independent update
streams, an immutable branch-per-run model may be reconsidered. However,
given current concurrency guarantees and low-frequency updates, the
rolling branch model remains optimal.
