#!/bin/sh
# This file is synced from toobuntu/repo-foundation
# (scripts/foundation-doctor.sh) by sync-to-consumers.yml; do not modify it
# directly.


# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# foundation-doctor.sh — flag per-repo scaffold workflows that have gone stale.
#
# The ci / codeql / copilot-setup-steps workflows are copy-once scaffolds owned
# per repo (ADR 0015), so the sync cannot realign them and there is no clean
# canonical to diff them against. This is an age-based nudge instead: a scaffold
# untouched for longer than the threshold is reported for manual reconciliation
# against current upstream guidance. The scheduled scaffold-drift.yml workflow
# runs the same check and opens an issue — one implementation, two triggers.
#
# A scaffold that carries the "do not modify it directly" sync header is skipped:
# it is a synced canonical file (a Homebrew tap's copilot-setup-steps), not a
# per-repo scaffold, and it self-heals through the sync.
#
# Usage: scripts/foundation-doctor.sh [--max-age-days N] [repo-root]
#   FOUNDATION_DOCTOR_MAX_AGE_DAYS overrides the default (365). Exits non-zero
#   if any scaffold is stale, so a caller (CI) can act on it.

set -eu

max_age_days="${FOUNDATION_DOCTOR_MAX_AGE_DAYS:-365}"
while [ $# -gt 0 ]; do
  case "$1" in
  --max-age-days)
    max_age_days="${2:?--max-age-days needs an argument}"
    shift 2
    ;;
  --max-age-days=*)
    max_age_days="${1#--max-age-days=}"
    shift
    ;;
  -h | --help)
    printf 'Usage: %s [--max-age-days N] [repo-root]\n' "${0##*/}"
    exit 0
    ;;
  --)
    shift
    break
    ;;
  -*)
    printf 'error: unknown option: %s\n' "$1" >&2
    exit 2
    ;;
  *) break ;;
  esac
done
root="${1:-.}"

now=$(date +%s)
stale=0
found=0
for name in ci.yml codeql.yml copilot-setup-steps.yml; do
  rel=".github/workflows/$name"
  f="$root/$rel"
  [ -f "$f" ] || continue
  # Synced canonical files self-heal; only per-repo scaffolds are nudged.
  grep -qF "do not modify it directly" "$f" && continue
  found=1
  # Last-commit time of the file. Untracked / no history → treat as fresh.
  ct=$(git -C "$root" log -1 --format=%ct -- "$rel" 2> /dev/null || true)
  [ -n "$ct" ] || {
    printf 'ok (untracked): %s\n' "$rel"
    continue
  }
  age_days=$(((now - ct) / 86400))
  if [ "$age_days" -gt "$max_age_days" ]; then
    printf 'STALE: %s — last changed %d days ago (> %d). Reconcile against current upstream guidance.\n' \
      "$rel" "$age_days" "$max_age_days" >&2
    stale=1
  else
    printf 'ok: %s — %d days\n' "$rel" "$age_days"
  fi
done

[ "$found" -eq 1 ] || printf 'no per-repo scaffold workflows present; nothing to check\n'
[ "$stale" -eq 0 ] || exit 1
