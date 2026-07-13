<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

<!--
This file is synced from toobuntu/repo-foundation
(docs/agent-principles.md) by sync-to-consumers.yml; do not modify it
directly.
-->

# Agent operating principles

This file is committed to the repository so every contributor — human
or AI — has access to it. It is imported into `AGENTS.md` (the file
Claude Code reads automatically on every session) via the
`@docs/agent-principles.md` directive near the top of `AGENTS.md`.
Project-specific context lives in `AGENTS.md`; this file is the
cross-cutting rules.

It is intentionally narrow in scope: rules that should apply to
**any** agent working on **any** project. Project-specific rules
(architecture, build commands, conventions) live in `AGENTS.md`.

## Pre-action discipline

Before any action that mutates the working tree, the index, branches,
files, or external state — including `git stash`, `git switch`,
`git restore`, `git commit`, `git rm`, `git worktree`, any `make`
target that installs / mounts / writes outside the repo,
`bundle install`, `gem install`, `npm install`, `pip install`,
running project scripts that mutate state, file edits, daemon
preference writes, anything calling `launchctl`, anything that runs
`sudo` — state:

1. The exact command intended.
2. The expected post-state in a sentence.
3. The recovery path if it goes wrong.
4. Whether the operation is reversible. If irreversible, halt and ask.

Then wait for explicit approval before running. The permission
prompts in `.claude/settings.json` are a backstop, not the primary
review mechanism — they don't show post-state or recovery.

This costs ~20 seconds per state-changing turn. The cost is
intentional. Sessions that try to compress it produce mistakes.

## Read before write

Before editing a file, read it. Before testing a script that mutates
the repo, ask whether a worktree is appropriate. Before installing
gems or other dependencies, check for project-local config that
governs install location (`.bundle/config`, `package.json`,
`pyproject.toml`, etc.). Before disabling a sandbox or escalating
permissions, check whether the request can be satisfied from inside
the sandbox by adjusting approach.

## Engineering principles

These software-engineering principles apply to any code or
configuration the agent writes, edits, or proposes. They are not
Claude-Code-specific; they describe what good code looks like. The
list mixes always-applicable principles (DRY, YAGNI, KISS, idiomatic
patterns, comments-minimum) with context-dependent ones (SRP,
fail-fast, make-illegal-states-unrepresentable). The agent applies
each one with judgment about whether it fits the situation.

- **DRY (Don't Repeat Yourself).** When the same logic, value, or
  configuration appears in multiple places, that is duplication and
  should be factored out unless there is a specific reason to keep
  duplicates (different evolution paths, different audiences,
  shipped-vs-derived). The principle is a tendency, not a rigid
  rule — three trivial similar lines are often clearer than one
  abstracted three-place call.
- **YAGNI (You Aren't Gonna Need It).** Don't build for hypothetical
  future requirements. Add code, parameters, configuration, and
  abstraction *when* you need it, not because you might need it
  later. Generality has a real cost in readability and maintenance;
  specificity is cheaper. If a future use case actually arrives, the
  refactor will be obvious. If it doesn't arrive, the speculative
  code is just clutter.
- **KISS (Keep It Simple).** Prefer the most direct solution that
  works. Clever code is harder to debug at 2am. If you find yourself
  reaching for a metaprogramming trick, an inheritance hierarchy, or
  a custom DSL, ask whether plain functions or straight-through data
  flow would do.
- **Idiomatic patterns.** Follow the conventions of the language and
  ecosystem you're working in: Ruby idioms in Ruby (RuboCop, Sorbet
  conventions, `do...end` for multi-line blocks), Bash idioms in
  Bash (`set -euo pipefail`, POSIX where portability matters),
  Objective-C idioms in ObjC (ARC, ivar prefix `_`, NSError**
  out-params), and so on. Don't transplant patterns from one
  language to another. The best style for a project is the one its
  existing files already use.
- **Comments minimum.** Self-documenting names beat explanatory
  comments. Code that needs a comment to explain *what* it does
  usually wants to be rewritten; code that needs a comment to
  explain *why* it does it that way (non-obvious tradeoff, link to
  bug or RFC, "this looks wrong but isn't because...") is fine.
  Inline first-person (`we ask`, `we check`) doesn't add information;
  the imperative voice ("ask", "check") is enough.
- **Document public APIs and complex logic.** Distinct from
  comments-minimum: public interfaces deserve doc comments
  describing inputs, outputs, side effects, and error conditions
  (callers will read these). Implementation details usually don't.
  When a non-trivial algorithm is the right answer, leave a
  one-paragraph block comment explaining the approach and any
  references — that's not what comments-minimum prohibits.
- **Inline rule.** A new helper method or named local variable is
  worth introducing only when it's reused 2+ times or required by a
  unit test. A one-call wrapper around a clear expression is
  abstraction without payoff and obscures the original computation.
  This is the "rule of three" pattern, applied at the
  function/variable level rather than the larger structural level.
- **SRP (Single Responsibility Principle).** A function, class,
  module, or script doing one thing is usually easier to understand
  and change than one doing many things. If a description of what
  it does requires "and", that's often a signal it should be split.
  Caveat: applied dogmatically, SRP produces a maze of tiny
  single-purpose units that obscure flow. The "right" granularity
  depends on the audience and the change-cadence of the code. Use
  judgment.
- **Make illegal states unrepresentable.** If a value can only be
  one of three things, use an enum or three named constants — not a
  string that could in principle be anything. State that's enforced
  at the type / data-structure level can't drift; state that's
  enforced by convention will. Most valuable for state machines
  (where invariants are central) and long-lived domain types; less
  valuable for one-shot scripts and ephemeral data.
- **Fail fast and surface errors.** Detect errors at the boundary
  closest to where the bad input enters. Validate user input on
  receipt; validate config on load; check return codes. The opposite
  pattern — catching errors silently and continuing with degraded
  state — is much harder to debug. Caveat: for internal helpers
  whose callers can sensibly recover, returning a typed result
  (success/error pair) is sometimes cleaner than throwing.
- **Tests for new functionality.** Match the project's existing
  testing pattern. Some projects use unit tests, some use
  integration tests, some rely on a manual testing checklist (per
  AGENTS.md). If a project has tests, new functionality gets tests.
  If introducing a new testing approach (e.g., adding RSpec to a
  project that previously had no Ruby tests), surface that as a
  separate proposal rather than slipping it into a feature commit.
- **Suggest `docs/` updates when appropriate.** When a feature
  changes user-visible behavior, a public API, an installation
  procedure, or a developer workflow, propose corresponding
  documentation updates as part of the same change. Don't ship a
  feature whose users can't discover how to use it.

These principles are mutual constraints, not independent rules. DRY
taken to extremes produces over-abstraction (violating KISS). YAGNI
taken to extremes produces fragile code that breaks on the next
minor extension. SRP taken to extremes produces a maze of tiny
methods. The agent should hold all of them and pick the one that
applies most strongly to the situation.

## Citing external code

When using code, configuration, or technique borrowed from a public
discussion forum (Stack Exchange, Hacker News, Reddit, blog posts,
GitHub Gists, mailing-list archives, etc.):

1. **Surface the source URL** in the proposal. The maintainer should
   be able to follow the link.
2. **Briefly evaluate why the code is correct or applicable** — not
   a full audit, but a one-line "this matches the use case because
   X" or "the answer is from Y who is a recognized authority on Z."
3. **Wait for approval** before applying.

Forum code is unsigned by definition. It can be wrong, outdated,
malicious, or correct-for-a-different-context. The agent's training
discourages blind copy-paste, but the structural defense is to make
the source explicit. The maintainer's quick read of the link is the
review step.

This applies even to code the agent writes "from scratch" if it
relied on a forum-sourced approach to inform the structure. If the
algorithm came from Stack Overflow, say so.

## Errors are evidence, not obstacles

When a command fails, the first response is to read the error
carefully, not retry with a workaround. Surprising errors usually
reveal something important about the system; the right response is
"interesting — let me think about what this means," not "let me try
the next variant."

When a sandbox or permission block surfaces, before proposing a
workaround, ask: is the operation that's blocked actually the right
operation? Is there a narrower or more correct version of the
operation that wouldn't hit the block at all? Sometimes the block is
the system telling you the operation was sloppily framed.

## Fail forward to the human, not to capability inflation

If a tool call is denied, sandboxed-out, or fails for a reason that
suggests escalation might fix it: stop and surface with exact command,
exact error, and the minimum scope-widening that would fix it. Never
propose `dangerouslyDisableSandbox`. Never `chmod -x` a hook to
silence it. Only propose editing permission rules when the rule
itself is incomplete or strictly wrong, not when the operation is.

`dangerouslyDisableSandbox: true` is disabled by policy
(`sandbox.allowUnsandboxedCommands: false` in settings). Attempting
to use it is a failure mode, not a workaround.

## Accurate narration

The agent's narration about what it just did must match what
actually happened. Specific traps:

- Do not describe a command as "bypassing the sandbox" unless there
  is direct evidence the bypass succeeded. `sh -c 'cmd'` does NOT
  bypass the sandbox; `sh` is sandboxed the same as `bash`. If a
  followup command then fails with a sandbox error, that proves the
  preceding command did not bypass the sandbox either.
- Do not describe a permission-denied error as the sandbox blocking,
  or vice versa. They look similar but the recoveries differ.
  Permission denial says `Bash(...)` is not allowed; sandbox denial
  says `Operation not permitted` or `cannot create temp file` or
  similar OS-level message. Identify which it is before proposing a
  fix.

When unsure, say so explicitly: "I'm not sure whether this failed
because of the sandbox or the permission system; the error suggests
X but Y is also possible — running this single test to disambiguate
before proposing a fix."

## One change at a time

Changes that touch unrelated subsystems should land in separate
commits, ideally separate sessions. If a session needs to fix a bug,
update docs, AND test a new script — propose those as three commits
and ask which to do first. Don't bundle.

## Silent state changes are forbidden

If something requires altering project configuration (`.bundle/config`,
`.gitignore`, `.clang-format`, `.claude/settings.json`, etc.) to do
a task, that configuration change is a separate proposal and gets
its own approval. Don't slip configuration mutations into a task that's
ostensibly about something else.

## Modern git CLI verbs

`git checkout` is overloaded — branch switching, file restoration,
detached HEAD, and blob extraction all share one verb. Prefer the
split forms introduced in git 2.23 (Aug 2019):

| Avoid                              | Use                                       |
|------------------------------------|-------------------------------------------|
| `git checkout <branch>`            | `git switch <branch>`                     |
| `git checkout -b <branch>`         | `git switch -c <branch>`                  |
| `git checkout -B <branch>`         | `git switch -C <branch>`                  |
| `git checkout <commit>`            | `git switch --detach <commit>`            |
| `git checkout -- <path>`           | `git restore <path>`                      |
| `git checkout HEAD~1 <path>`       | `git restore --source=HEAD~1 <path>`      |
| `git checkout --staged <path>`     | `git restore --staged <path>`             |

`checkout` may still appear in `permissions.ask` for legacy
compatibility, but day-to-day work uses `switch` and `restore`. They
are clearer about intent and harder to misuse — `git restore --staged
<path>` cannot accidentally discard a working-tree change the way
`git checkout HEAD <path>` can.

## Worktrees over stash for testing

When testing a script that mutates the repo, use `git worktree add`
to get an isolated working copy of the same branch rather than
stashing the current work. Stashing creates a recovery risk on `pop`
(especially `--include-untracked` with merge-base churn); a worktree
has no such risk. The throwaway dir is removed at end of test.

Worktrees go UNDER the project tree at `worktrees/` (gitignored)
because the Claude Code sandbox writable area is the project tree
and its subdirectories — sibling directories are not writable.

## Park merged branches; delete only on the remote

After a branch merges, the local branch is not deleted. It is renamed
into the `merged/` namespace — prefixed with the PR number that merged
it — and only the remote copy is deleted:

```sh
git branch -m feature/foo merged/pr12-feature/foo
git push origin --delete feature/foo   # or GitHub's delete-on-merge
```

The `merged/*` branches are cheap rollback handles and provenance
markers. They are pruned opportunistically, at the maintainer's
discretion — never as part of routine cleanup an agent performs or
recommends. Agent hand-off reports and cleanup checklists must say
"rename to `merged/…`", not "delete the local branch"; remote deletion
is unaffected.

## Long options in shell

Use long-form options for readability and grep-ability:
`--extended-regexp` not `-E`, `--max-count=1` not `-n 1`,
`--name-only` not whatever the short form was. Exception: when a
script is in a tight loop or `xargs` chain where short options are
idiomatic and the output is for human eyes (e.g., `xargs -J`).

## printf over echo; heredocs for multi-line

Prefer `printf` to `echo` in scripts and tool calls: `echo`'s handling
of flags and escapes varies across shells and modes, while `printf` is
POSIX-stable. `echo` remains fine for trivial static words. For
multi-line strings, use a heredoc — or write the content to a file with
a dedicated tool and pass the file (`--file`, `-F`, stdin) — rather
than chaining `-m` arguments or embedding `\n` escapes.

## Platform: macOS and the BSD userland

These repositories target macOS end-users, and macOS ships the BSD
userland, not GNU coreutils. Code — shell especially, but also anything
that shells out — must run on BSD tools:

- **No GNU-only flags.** `sed -E` with multi-line address ranges,
  `date -d`, `find -printf`, `grep -P`, `readlink -f`, `xargs -d` and the
  like are unavailable on stock macOS. Use a POSIX form that works on both
  userlands, or a Homebrew `g`-prefixed tool (`gsed`, `gdate`) when a GNU
  extension is genuinely required — and say which.
- **A concrete trap:** BSD `date -j -f` needs a clean field count, and
  OpenSSL's `enddate` prints a double space before a single-digit day
  (`Jun  5 …`), so pipe through `tr -s ' '` before parsing.
- **Portable shell.** A `#!/bin/sh` script must be POSIX `sh` (macOS `/bin/sh`
  is bash 3.2 in POSIX mode); no `mapfile`, process substitution, `[[ ]]`, or
  other bash-isms. A script that needs those declares `#!/usr/bin/env bash`
  (or `ksh`/`zsh`) explicitly. Do not depend on Linux-only paths (`/proc`,
  `/sys`) or package managers (`apt`, `dpkg`).
- **Shell is linted**, dialect-aware. `sh`/`bash` scripts pass `ksh -n`
  (syntax; stricter than `bash -n`/`sh -n`, stock on macOS), are `shfmt`-formatted
  (two-space, per `.editorconfig`), and are `shellcheck`-clean at
  `--severity=warning` (per `.shellcheckrc`). AT&T **ksh93** scripts (a `.ksh`
  extension or a ksh shebang) are checked with `ksh -n` and
  `shellcheck --shell=ksh` but **not** `shfmt` — shfmt has no ksh93 dialect and
  mangles or rejects it (mvdan/sh#614). The `pre-commit.d/05-shell` plugin
  enforces this on staged shell and a `shell-lint` CI job on the whole tree,
  both through `scripts/lint-shell.sh` (ADR 0017). **Homebrew-aligned repositories are the
  exception:** homebrew-cask-tools and babble defer to `brew style`, which runs
  `shfmt` + `shellcheck` (and RuboCop) with Homebrew/brew's own config —
  four-space and a few other differences — carried verbatim; they do not use
  the two-space toobuntu config or the `05-shell` plugin.

## Plain, literal prose

Write documentation, comments, ADRs, and commit messages in plain, literal
language. Name what is actually happening rather than reaching for in-group
jargon or metaphor: write "repo-foundation runs the files it ships," not
"repo-foundation dogfoods its config." Terms like `dogfood` or `north star`
assume a shared backstory the reader may not have and obscure the plain
meaning. A contributor who was not in the originating conversation should
understand the sentence on first read. This is the prose counterpart to
"comments minimum": fewer words, each one literal.

## Commit messages and PRs

- When a turn modifies tracked files, propose a commit decomposition
  for those changes before ending the turn — logical commits, each
  with its own ≤ 50-char subject — rather than letting uncommitted
  changes accumulate across turns. State it even when the work will
  be committed later; the decomposition is the proposal, the commit
  is the approval.
- Subject ≤ 50 chars; body wraps at 72; `Closes #N` in body.
- No verbose AI commentary in PR descriptions. Note AI assistance
  and what manual verification was performed.
- Merge commits, never squash or rebase, on PR merge (unless the
  project ADRs say otherwise).
- en_US spelling everywhere (`labeling` not `labelling`, `color`
  not `colour`).

## Agent commit + signing procedure under sandbox isolation

### Why

All repos in this project require signed commits (policy: `commit.gpgsign =
true`, `gpg.format = ssh`, key under `~/.ssh`). A sandboxed agent's shell
denies read access to `~/.ssh`, so any `git commit` that tries to sign
**hangs** on the key/askpass step (often a macOS passphrase dialog that never
returns) or fails outright. The agent therefore commits *unsigned*, and the
human re-signs the batch before pushing.

### Agent: commit unsigned

```sh
GIT_TERMINAL_PROMPT=0 git -c commit.gpgsign=false commit --no-gpg-sign \
    --file /tmp/claude/msg.txt < /dev/null
```

- `-c commit.gpgsign=false` and `--no-gpg-sign` both disable signing (belt and
  suspenders — the config override stops the hang even if some path re-reads
  `commit.gpgsign`).
- `< /dev/null` closes stdin so nothing can block on an interactive prompt (the
  signing askpass, a credential helper, an editor).
- `GIT_TERMINAL_PROMPT=0` stops git itself from prompting on a TTY.
- `--file` (with the message written to a sandbox-writable file first, e.g.
  `/tmp/claude/msg.txt`) instead of multi-line `-m` arguments: long multi-line
  `-m` commands are a known hang in the Claude Code harness — the call is
  auto-backgrounded and the commit never completes.
- Run `git commit` as its **own** standalone tool call. Chaining it in a
  compound command (`cmd && git commit …` or a `;`-sequence) auto-backgrounds
  and aborts it the same way — even `--amend --no-edit` — leaving HEAD unchanged
  and the file unstaged. Do any `git add` / validation in a separate call first.
  A single-line `-m` and `--amend --no-edit` are safe only when run standalone.
- Add `--no-verify` **only** if the pre-commit hook genuinely can't run in the
  sandbox (e.g. `reuse lint` without `--no-multiprocessing` aborts on the macOS
  Seatbelt `SC_SEM_NSEMS_MAX` syscall; `go vet ./...` / `staticcheck` can't write
  the module/build cache). A correctly written hook (`reuse --no-multiprocessing
  lint-file`, language checks gated on staged files) runs clean in-sandbox and
  should *not* be bypassed. The canonical `pre-commit.d` plugins are written this
  way — for instance the Swift plugin bypasses the on-disk cache
  (`swiftformat --cache ignore`, `swiftlint --no-cache`), since otherwise
  swiftlint exits non-zero when it cannot write `~/Library/Caches` under the
  sandbox. To run those tools ad hoc in a sandbox (outside the hook), pass the
  same flags.

### Human: re-sign the batch before pushing

```sh
git rebase --exec 'git commit --amend --no-edit --gpg-sign' origin/main
```

(`--gpg-sign` is the long form of `-S`.) What it does, and why the SHAs change:

- It walks every commit on the current branch that is **not** already in
  `origin/main` (the `origin/main..HEAD` range) and, for each, runs
  `git commit --amend --no-edit --gpg-sign` — re-committing the same tree and
  message, now SSH-signed. The rebase is without `--rebase-merges`, as the
  range is expected to be linear and preserving merge topology would add replay
  complexity without benefit to per-commit signing.
- The cryptographic signature is stored **inside the commit object** (alongside
  the tree, parents, author, and message), so signing changes the object's hash.
  **Every amended commit gets a new SHA**, and every descendant is rewritten too.
  The branch is content-equivalent but entirely new in identity.
- Safe only while the commits are unpushed (rewriting *published* history is
  not). The `pre-push` hook enforces the invariant from the other side — it
  rejects a push whose tip is unsigned (`N`) or invalidly signed — so an
  un-re-signed batch can't reach the remote by accident.

### Consequence: a re-signed branch diverges from a stale `main`

If you committed unsigned on `main` and then re-signed on a feature branch (or
ran the rebase with `origin/main` as the base while on the branch), the "same"
commits now exist at **two different SHAs**: the branch's signed ones and
`main`'s old unsigned ones. Treat the **re-signed branch as the source of
truth** and realign `main` to it after the branch lands
(`git switch main && git reset --hard origin/main`) rather than trying to push
both — `main`'s unsigned tip would be rejected anyway.

### Promoting follow-up batches from an isolated clone: cherry-pick, not merge

The same SHA-rewrite has a second consequence when the agent works in an
isolated (remoteless) clone across **multiple hand-offs**. After the first
promotion re-signs the batch, the clone and the live repo are
patch-equivalent but SHA-divergent: from git's perspective the lineages are
unrelated at every point past the first signing. A follow-up batch built in
the clone sits on the *unsigned* parents, so `git merge --ff-only FETCH_HEAD`
fails by construction, and a plain merge or rebase would duplicate the
already-promoted commits under third SHAs.

Promote with cherry-pick and patch-id filtering instead, via
`scripts/promote-from-isolated.sh [--yes] <clone-path> [<branch>]`.
`--cherry-pick` compares patch-ids, not SHAs: commits already promoted
(under different SHAs) are filtered out and only genuinely new work is
applied, so re-running when there is nothing new is a no-op.

**The picks land unsigned — deliberately.** Unsigned status *is* the
workflow state: the just-promoted batch is visually distinct
(`git log --format='%h %G? %s'` shows `N`), freely amendable, and testable;
`re-sign-unpushed.sh` remains the single blessing step before push, exactly
as for commits authored directly in the live repo, and the `pre-push` hook
still rejects unsigned tips. Promotion changes only the transport, never
the evaluate-then-sign workflow. The full sequence:

```sh
scripts/promote-from-isolated.sh <clone-path> <branch>  # gated, unsigned picks
# run the repo's checks; amend freely while unsigned
scripts/re-sign-unpushed.sh                             # bless the batch
git push origin <branch>
```

The script refuses to apply anything until its gates pass: clean tree and
correct branch; the clone side must be linear (a merge commit on the agent
branch is an error, not something to pick silently); a left/right **subject
collision** across the filtered delta is an error — that is the signature of
a promoted copy amended in the live repo, whose patch-id no longer matches,
and picking it again would conflict or duplicate; and after the `%m`-marked
preview it asks for confirmation (`--yes` skips; without it, a non-TTY
stdin aborts). If a pick still conflicts past the gates, the script prints
recovery guidance to stderr (`--continue` after resolving, or `--abort` to
return to the pre-promotion state).

Two design notes, so the boundaries are explicit rather than folklore:

- **The clone's role**: a mutable workspace **until** a commit is promoted,
  a frozen intent stream afterwards. Reword, split, and reorder freely
  before the first hand-off; once a commit's copy exists in the live repo,
  the live copy is the source of truth (same principle as the re-signed
  branch above) and fixups belong there — or in *new* clone commits.
  Promotion never replays clone history as such; it applies the derived
  patch view (`--cherry-pick` filtering is patch-id-based), which is why
  the clone never needs rebasing onto the signed lineage. Partial
  promotion, when ever needed, is a manual `git cherry-pick` of the
  chosen subset — the script deliberately handles only the
  whole-delta case.
- **The subject-collision gate is a guardrail, not an identity check.**
  Git cannot prove "this live commit is an amended copy of that clone
  commit"; matching subjects across the filtered delta is a proxy that
  catches the common accident. A false positive (two unrelated commits
  sharing a subject) blocks the script — promote that batch manually. A
  false negative (an amend that also reworded the subject) surfaces as a
  pick conflict, with recovery guidance on stderr.

Division of responsibility:

- **The human promotes.** Object-ID divergence between the clone and the
  live repo is expected and permanent; never "fix" it.
- **The agent keeps building on its own clone lineage** and does not chase
  the signed SHAs. Hand-off reports must say "promote with
  `scripts/promote-from-isolated.sh <clone-path> <branch>`" — never
  `merge --ff-only` instructions, which only hold for a first promotion.
  Rebasing the clone onto the signed lineage is allowed as an optional
  tidy-up (it empties the "<" side of the preview) but correctness never
  depends on it.
- **The agent must not amend clone commits that were already promoted**
  (that manufactures the subject-collision case); follow-ups go in new
  commits.

The script ships with a self-contained harness,
`scripts/promote-from-isolated-test.sh` (throwaway repos under mktemp;
simulates re-sign divergence, idempotence, the collision and merge gates,
and the prompt guards) — run it after any change to the promote script.

### Pre-commit hook network tools under the sandbox (zizmor)

When a commit stages a `.github/workflows/*.yml` file, the `pre-commit` hook
runs `zizmor --quiet .`. zizmor (1.25.x) builds an HTTP client at startup —
even for local audits — and on macOS reads the system proxy config via
`SCDynamicStoreCreate`. Under Seatbelt the `configd` mach service is
unreachable, so that returns NULL and zizmor **panics**
(`system-configuration … Attempted to create a NULL object`) — a crash, not a
lint finding. It is **not** fixable via `sandbox.network.allowedDomains`: the
panic precedes any URL contact (a bogus `ALL_PROXY` still crashes). Only
running zizmor **outside** Seatbelt fixes it.

- **Unsandboxed (online) — configured, not yet validated:**
  `git -c commit.gpgsign=false commit *` and `zizmor *` are now in
  `sandbox.excludedCommands`. But the agent's recipe is prefixed
  `GIT_TERMINAL_PROMPT=0 git …`, which may not match the pattern — so the commit
  (and its hook's zizmor) may still run sandboxed. **Unverified**: confirm by
  committing a workflow change and checking the hook's zizmor doesn't crash; if
  it does, add the prefixed form to `excludedCommands` or drop the env prefix.
- **Fallback (the live path until the above is validated):** prepend
  `ZIZMOR_OFFLINE=true` (value `true`/`false`, not `1`) to the commit — the
  hook's zizmor runs offline (only online audits are suppressed; they need
  network and a `--gh-token` anyway), so the **full** hook still runs, no
  `--no-verify` or sandbox widening. Don't set it globally in `env`.

## Avoiding interactive shell hooks in tool calls

`zsh` (the typical macOS interactive shell) has hooks like `chpwd`
that try to write `~/.lastpwd` on every directory change. Inside the
Claude Code sandbox, those hook writes fail with "Operation not
permitted" because `~/.lastpwd` is outside the writable area. This
shows up as `cd:3: operation not permitted: /Users/.../lastpwd` when
the agent runs `cd /path && cmd`.

The fix is NOT to widen the sandbox; it's to invoke commands without
loading interactive zsh state. Two reliable patterns:

```sh
# Pattern A: use sh -c with explicit cwd (recommended).
# Inherits no zshrc; doesn't trigger chpwd hooks.
sh -c 'cd /abs/path && cmd args'

# Pattern B: invoke the command with absolute paths and no `cd`.
# Useful for commands that take their own --cwd or operate on paths
# relative to git's working tree.
git -C /abs/path status
```

Pattern A is what test infrastructure expects. Pattern B is preferred
when the underlying tool supports it.

## Sandbox model

The Claude Code sandbox (Seatbelt-based on macOS) operates **below**
the permission system: a command can be in `permissions.allow` and
still be blocked by the sandbox if it tries to write outside the
writable area or contact a non-allowlisted host.

**Default writable area**: the project directory and its
subdirectories. Sibling directories are NOT writable. This includes
`../<sibling>` paths.

**Common project-local additions** (in `~/.claude/settings.json` or
`<repo>/.claude/settings.json`, under `sandbox.filesystem.allowWrite`):

- `/private/tmp` (canonical path of `/tmp`) — needed by shells'
  heredoc temp files, `mktemp`, etc.
- `/private/var/folders` and `/var/folders` — macOS's per-user
  `$TMPDIR` lives here. Allows `mktemp(1)`, `mkstemp(3)`, gem caches,
  Bundler temps.

These are standard temp-dir locations. They don't widen reach into
anything sensitive — `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config/gh`,
`~/Library/Keychains`, `~/.claude.json`, `~/.claude/` remain in
`denyRead`.

**`make` and `launchctl`**: any `make` target that writes outside
the project tree (e.g., `make install` writing to `/usr/local`,
`make dev` writing to `~/Library/LaunchAgents/`) goes in
`sandbox.excludedCommands` so the project tree restriction is
lifted for that one operation. The permission system still applies
(these are usually in `permissions.ask`).

## Bundler hygiene (Ruby projects)

A project that uses Bundler should ship `.bundle/config` with
`BUNDLE_PATH: vendor/bundle` and `BUNDLE_DISABLE_SHARED_GEMS: true`
so `bundle install` writes to `./vendor/bundle/` instead of the
system Ruby. Without this, Bundler falls back to the active Ruby's
gem dir, which on macOS is `/Library/Ruby/Gems/` — a system path the
agent should never write to.

If the agent finds gems already installed system-wide before this
config landed, the manual recovery is:

```sh
gem list --local | grep --extended-regexp 'rspec|<other gems>'
sudo gem uninstall <gem-list>
bundle install
```

The agent should NOT propose `sudo gem install` or any plain
`gem install` on system Ruby. CI's `ruby/setup-ruby` with
`bundler-cache: true` writes the same project-local layout.

## SPDX / REUSE headers

Do not hand-write SPDX headers. Run `scripts/annotate.sh`, which wraps
`reuse annotate` with the project's per-filetype rules: it picks the
comment style by extension, forces `.license` sidecars for generated or
comment-hostile files (completions, man pages, plists, checksums), and —
for Markdown with YAML frontmatter — places the SPDX block as `#` comments
*inside* the frontmatter, so the frontmatter stays at file position 1 and
tools that parse it (`adrs doctor`, Claude Code skill loaders) keep
working. A hand-placed header drifts from that output and often lands in
the wrong position. The pre-commit hook and CI's `lint-reuse` job reject
files missing SPDX, so run `annotate.sh` after creating any file; it only
touches files `reuse lint` reports as non-compliant.

This **includes Architectural Decision Records** (the MADR-format files
under `docs/decisions/`). They are exactly the YAML-frontmatter case above:
`reuse annotate --style=html` (what `annotate.sh` runs for `.md`) inserts
the SPDX block as `#` comment lines at the top *inside* the `---` fence,
above `number:`/`title:` — the same form every existing ADR carries, and
the form `adrs doctor` requires. So write an ADR body with no SPDX and let
`annotate.sh` add it; never hand-write or hand-place the SPDX block in an
ADR (or paste it above the frontmatter, which breaks `adrs doctor`).

## Universal tools available without prompt

These macOS dev tools are commonly allowlisted in Claude Code
settings. The agent does not need to ask before running them:

- File and binary inspection: `file`, `otool`, `nm`, `dyld_info`,
  `codesign --verify/--display`, `plutil -lint/-p`,
  `lipo -info/-archs`
- Process and memory: `vmmap`, `sample`, `spindump`
- System information: `sw_vers`, `uname`, `sysctl -n`,
  `defaults read`, `defaults domains`
- Logging: `log show`, `log stream`
- Power: `pmset -g` (READ ONLY — never the mutating forms)
- IORegistry: `ioreg`, `system_profiler`
- launchd: `launchctl list`, `launchctl print`
- Apple SDK paths: `xcrun --find`, `xcrun --show-sdk-path`,
  `xcrun --show-sdk-version`
- Lint: `actionlint`, `zizmor`, `shellcheck`, `shfmt --diff`,
  `clang-format --style=file --dry-run`, `clang-tidy`,
  `reuse lint`, `reuse lint-file` (read-only forms),
  `pinact run --check`, `pinact run --verify`
- git: `status`, `log`, `diff`, `show`, `rev-parse`, `ls-files`,
  `ls-tree`, `config --get`, `remote -v/get-url`, `branch` /
  `--show-current`/`--list`/`-a`, `tag`/`--list`, `fetch`,
  `worktree list`
- gh (read-only): `pr view/list/checks/diff`, `issue view/list`,
  `repo view`, `run view/list`, `release list/view`,
  `api -X GET ...`, `auth status`
- Web: `WebSearch`, `WebFetch` (these are first-class Claude Code
  tools, separate from Bash; the network sandbox allowlist is the
  actual gate).

## Tools that require approval

These mutate state. The agent should propose the exact command and
wait for approval:

- git (mutating): `add`, `commit`, `tag -a`/`-d`,
  `switch`/`checkout`, `stash`, `restore`,
  `reset --soft`/`--mixed`/`HEAD`, `rm`, `mv`, `rebase`,
  `cherry-pick`, `revert`, `merge`, `pull`, `branch -d`/`-m`,
  `worktree add`/`remove`/`prune`
- launchctl: `bootstrap`, `bootout`, `kickstart`, `enable`,
  `disable`
- gh (mutating, careful): `pr comment`/`edit`/`create`/`review`/
  `ready`, `issue comment`/`create`/`edit`, `release create`
- Code mutation: `clang-format -i`, `reuse annotate`, `pinact run`
  (without `--check`/`--verify`)
- Network: `curl` (any method other than GET semantics)
- Tooling: `bundle install` (asks even with project `.bundle/config`,
  defense in depth)

## Universally denied operations

These are blanket-denied. Don't propose workarounds:

- Force operations: `git push --force`, `git push --force-with-lease`,
  `git reset --hard`, `git branch -D`, `git clean`,
  `git filter-branch`, `git filter-repo`, `git update-ref`,
  `git replace`, `git reflog expire/delete`, `git gc --prune`,
  `git tag -f`/`--force`
- Pushes: `git push` (any form). The maintainer pushes manually
  after reviewing local commits.
- Remote mutations: `git remote add/remove/rm/rename/set-url`,
  `git config --global`, `git config --unset/--unset-all/--remove-section`
- gh destructive: `pr merge/close/delete`, `repo delete/archive/edit`,
  `release delete/upload`, `secret set/delete`, `ruleset delete`,
  `api -X DELETE/PUT/POST/PATCH`, `auth login/logout/refresh`
- Filesystem destructive: `rm -rf` (any form),
  `rm -rf .` / `/` / `~` / `$HOME`,
  `rm -rf ..` / `../` / `../<anything>` (path traversal)
- Privilege escalation: `sudo` (any form)
- System mutation: `nvram`, `csrutil`, `kmutil`,
  `kextload`/`kextunload`, `dscl . -create/-delete/-change/-append`,
  `dseditgroup`, `pwpolicy`, `spctl --master-disable`,
  `xattr -d/-dr com.apple.quarantine`
- launchd destructive: `launchctl reboot`, `launchctl unload`,
  `launchctl bootstrap system/`, `launchctl bootout system/`
- Power state: `pmset -a/-b/-c/-u`, `pmset schedule/repeat`,
  `pmset sleepnow`, `pmset displaysleepnow`
- Defaults mutation: `defaults write`, `defaults delete`
- Logs erase: `log erase`
- Disk mutation: `diskutil eraseDisk/eraseVolume/reformat/unmount/unmountDisk`,
  `asr`
- System control: `shutdown`, `reboot`, `halt`
- Kill: `killall -9` (use `kill -TERM` if a process needs stopping
  and surface to the maintainer first)
- System package managers: `brew install/uninstall/upgrade/cleanup/autoremove`,
  `npm install/uninstall/exec`, `npx`,
  `pip install/uninstall`, `pip3 install/uninstall`,
  `gem install/uninstall`, `cargo install`, `go install`
- Curl-pipe-shell variants: `curl ... | sh|bash|zsh|...`,
  `curl -X DELETE/PUT/POST/PATCH`
- Network egress that bypasses the allowlist: `wget`, `ssh`, `scp`,
  `rsync`
- Reading secrets: `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config/gh`,
  `~/Library/Keychains`, `~/.claude.json`, `~/.claude/`, `~/.netrc`,
  `~/.pgpass`, `./.env*`

## Confirm policy intent before coding

When a change touches a policy or a design decision — a hook's gating
rule, a CI check, ADR-governed behavior — state the *intended policy*
in plain terms and confirm it before writing code. Review-bot comments
(CodeRabbit, Copilot, and the like) and an agent's own "this looks more
correct / stricter" instinct are **inputs to weigh, not directives to
apply**: bots optimize for plausible-looking gating, not for what the
maintainer is actually trying to enforce, so applying them uncritically
produces a technically-defensible but wrong policy that costs more to
unwind than it would have to prevent. Read the canonical source first
(often the most complete sibling repo plus its CONTRIBUTING and ADRs),
restate the policy, and get agreement before implementing. This is a
specific case of "one change at a time" and "errors are evidence": a
surprising review suggestion is something to understand, not a task to
execute.

This extends to **design decisions**, not only policy gates. When a choice
is contested, recurring, or genuinely the maintainer's to make (it affects
their workflow, tooling, or cost), state a clear recommendation with
reasoning and confirm the intended approach before a large refactor — do not
implement, revert, and re-implement through several variants. A reference
implementation (a sibling repo, an upstream project) is an input to analyze
and learn from, not a canonical to copy verbatim; say which approach you
chose and why. And when the maintainer asks for an honest assessment, give it
plainly even when it pushes back on their stated directive — a reasoned
dissent, recorded in an ADR when the decision warrants, is more useful than
silent compliance.

## Preserve the user's work-in-progress before agent edits

When agent edits would mix with the user's uncommitted working-tree
changes, commit or otherwise preserve the user's WIP **first** —
decomposed into logical, per-concern commits — then commit the agent's
edits separately. Re-survey `git status` and attribute each changed
file to WIP vs. agent edit (diff to confirm) before committing. Prefer
decomposing in place over worktree-and-revert gymnastics, which are
brittle and easy to get wrong. For a file that mixes both concerns,
split the hunks non-interactively — `git apply --cached` on a sliced
patch (`git add -p` is unavailable in the sandbox). Add the
`Co-Authored-By` trailer only to commits that are genuinely the agent's
authored change, never to the user's WIP commits.

## Cross-repo references in committed docs

When a committed, contributor-visible doc references a **different**
repo (a sibling, or any repo other than the one the doc lives in), use
the GitHub `<org>/<repo>` slug — e.g. `toobuntu/babble` — not a bare
repo name (ambiguous) and not an absolute path like
`~/devel/claude/desktop/babble` (which leaks the maintainer's machine
layout and breaks when directories move). A doc's reference to its
**own** repo root uses the `<repo-root>` placeholder instead. Make
every reference to the same repo uniform, including pre-existing prose
mentions.

## Session economy

Every prompt sent to Claude Code consumes tokens. The biggest token
multipliers are:

- AGENTS.md size (read on every session start) — keep terse; move
  long reference material to `docs/<topic>.md` files that AGENTS.md
  only links to.
- Long conversations (history accumulates) — use `/clear` between
  unrelated tasks.
- File reads (each adds to context) — read targeted ranges with
  `view_range` when only part of a file is needed.

`permissions.allow`/`ask`/`deny` entries do NOT consume tokens
beyond the user's click on a permission prompt. The number of
entries doesn't scale token consumption. Optimize AGENTS.md size,
not permission entry count.
