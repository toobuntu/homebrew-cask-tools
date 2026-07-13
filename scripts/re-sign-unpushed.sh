#!/bin/sh
# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# re-sign-unpushed.sh -- re-sign the unpushed, unsigned commits a sandboxed
# agent left behind, then push. For each repo argument (default: the current
# repo):
#
#   1. find the oldest UNSIGNED commit not yet on any remote -- so published
#      history is never rewritten, and a remoteless repo re-signs only its
#      unsigned tip rather than its already-signed base;
#   2. rebase from just before it, re-signing each replayed commit;
#   3. push: a fast-forward when origin still descends the branch, a
#      lease-pinned force when an --amend/rebase after review diverged from
#      origin, and skipped when the branch has no remote-tracking ref (e.g. a
#      local-only repo).
#
# The .githooks/pre-push gate is the backstop -- it rejects any commit this
# misses. POSIX sh; no bashisms.

# This file is synced from toobuntu/repo-foundation
# (scripts/re-sign-unpushed.sh) by sync-to-consumers.yml; do not modify it
# directly.

set -eu

resign_one() {
  repo_dir=$1
  branch=$(git -C "$repo_dir" branch --show-current)

  if ! git -C "$repo_dir" rev-parse --quiet --verify HEAD > /dev/null 2>&1; then
    printf '%s (%s): no commits yet; skipping\n' "$repo_dir" "$branch"
    return 0
  fi

  # Oldest unsigned commit among those not on any remote. The pipeline prints
  # the first match and breaks; the command substitution captures it.
  oldest_unsigned=$(
    git -C "$repo_dir" rev-list --reverse HEAD --not --remotes |
      while IFS= read -r oid; do
        if [ "$(git -C "$repo_dir" log -1 --format='%G?' "$oid")" = N ]; then
          printf '%s\n' "$oid"
          break
        fi
      done
  )

  if [ -z "$oldest_unsigned" ]; then
    printf '%s (%s): already fully signed\n' "$repo_dir" "$branch"
    return 0
  fi

  if git -C "$repo_dir" rev-parse --quiet --verify "${oldest_unsigned}^" > /dev/null 2>&1; then
    git -C "$repo_dir" rebase --exec 'git commit --amend --no-edit --gpg-sign' "${oldest_unsigned}^"
  else
    git -C "$repo_dir" rebase --root --exec 'git commit --amend --no-edit --gpg-sign'
  fi

  remote_ref="refs/remotes/origin/${branch}"
  if ! git -C "$repo_dir" rev-parse --quiet --verify "$remote_ref" > /dev/null 2>&1; then
    printf '%s (%s): re-signed; no remote-tracking ref, not pushing\n' "$repo_dir" "$branch"
  elif git -C "$repo_dir" merge-base --is-ancestor "$remote_ref" HEAD; then
    git -C "$repo_dir" push origin "HEAD:${branch}"
  else
    git -C "$repo_dir" push \
      --force-with-lease="refs/heads/${branch}:$(git -C "$repo_dir" rev-parse "$remote_ref")" \
      origin "HEAD:${branch}"
  fi
}

if [ "$#" -eq 0 ]; then
  set -- "$PWD"
fi

for repo in "$@"; do
  resign_one "$repo"
done
