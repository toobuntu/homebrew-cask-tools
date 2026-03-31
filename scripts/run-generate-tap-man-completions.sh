#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# Run brew generate-tap-man-completions for this tap.
#
# This script is designed to be run from the **development clone** of the tap
# repository (e.g. ~/devel/github/homebrew-cask-tools). It:
#
# 1. Hardlinks dev-cmd/generate-tap-man-completions.rb into the installed tap's
#    cmd/ directory so `brew` can discover it (Homebrew does not support
#    external dev-cmd/ in third-party taps).
# 2. Runs the command with --tap= pointed at the installed tap so it writes
#    into the Homebrew-managed tap directory.
# 3. Syncs the generated completions/ and manpages/ back to the dev clone.
# 4. Cleans up the hardlink on exit.
#
# Generated files end up in the dev clone's completions/ and manpages/
# directories, ready for committing and pushing to the remote.
#
# All arguments are forwarded to the brew command. --open-pr is also detected
# by the script to trigger a git workflow (branch, commit, push, PR) after
# syncing. --no-pull-requests, --no-fork, --open-pr, --verbose, --debug, and
# --no-exit-code are all handled by the brew command's cmd_args.
#
# Usage:
#   scripts/run-generate-tap-man-completions.sh [--open-pr] [--no-pull-requests] [--no-fork] [--verbose] [--debug] [--no-exit-code]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEV_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Detect the tap name from the dev repo's git remote. Falls back to the
# directory name convention (homebrew-<name> → <user>/<name>).
detect_tap_name() {
  local remote_url tap_user tap_repo
  remote_url="$(git -C "${DEV_DIR}" remote get-url origin 2>/dev/null || true)"
  if [[ -n ${remote_url} ]]; then
    # Extract user/repo from SSH or HTTPS URLs
    tap_repo="$(basename "${remote_url}" .git)"
    tap_user="$(basename "$(dirname "${remote_url}")")"
    # Strip the homebrew- prefix from the repo name
    echo "${tap_user}/${tap_repo#homebrew-}"
    return
  fi
  # Fallback: directory name convention
  local dirname
  dirname="$(basename "${DEV_DIR}")"
  echo "unknown/${dirname#homebrew-}"
}

TAP_NAME="$(detect_tap_name)"
TAP_DIR="$(brew --repo "${TAP_NAME}" 2>/dev/null || true)"
# Convert tap name (toobuntu/cask-tools) to GitHub repo (toobuntu/homebrew-cask-tools).
# Use ${var/pattern/replacement} syntax compatible with bash, ksh, and zsh.
GH_REPO="${TAP_NAME/\///homebrew-}"
BRANCH="bot/update-completions-man-pages"

if [[ -z ${TAP_DIR} || ! -d ${TAP_DIR} ]]; then
  echo "Error: tap '${TAP_NAME}' is not installed. Run: brew tap ${TAP_NAME}" >&2
  exit 1
fi

CMD_SRC="${DEV_DIR}/dev-cmd/generate-tap-man-completions.rb"
CMD_DST="${TAP_DIR}/cmd/generate-tap-man-completions.rb"

if [[ ! -f ${CMD_SRC} ]]; then
  echo "Error: source file not found: ${CMD_SRC}" >&2
  exit 1
fi

# Detect --open-pr for the git workflow after syncing. All arguments
# (including --open-pr) are forwarded to the brew command.
OPEN_PR=false
for arg in "$@"; do
  [[ ${arg} == "--open-pr" ]] && OPEN_PR=true
done

cleanup() {
  echo "" >&2
  echo "==> Removing hardlink from tap repository..." >&2
  rm -f "${CMD_DST}"
  # Discard generated file changes (tracked) and remove new files (untracked)
  git -C "${TAP_DIR}" restore completions/ manpages/ 2>/dev/null || true
  git -C "${TAP_DIR}" clean -fd completions/ manpages/ 2>/dev/null || true
}
trap cleanup EXIT INT TERM

cat >&2 <<WARNING
╔══════════════════════════════════════════════════════════════════════╗
║  generate-tap-man-completions is about to run.                       ║
║                                                                      ║
║  Dev repo:  ${DEV_DIR}
║  Tap repo:  ${TAP_DIR}
║  Tap name:  ${TAP_NAME}
║                                                                      ║
║  The dev-cmd file will be temporarily hardlinked into:               ║
║    ${CMD_DST}
║                                                                      ║
║  Do NOT run brew update, brew upgrade, or brew update-reset until    ║
║  this finishes.                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
WARNING

echo "==> Hardlinking dev-cmd into tap repository..." >&2
[[ -e ${CMD_DST} ]] && echo "==> (replacing existing ${CMD_DST##*/})" >&2
ln -f "${CMD_SRC}" "${CMD_DST}"

echo "==> Running: HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions --tap=${TAP_NAME} $*" >&2
# Capture the exit code: 0 = no changes, 1 = changes made (both expected).
# Only mask the "no changes" non-zero exit (ofail); propagate real failures.
set +e
HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions --tap="${TAP_NAME}" "$@"
gen_exit=$?
set -e
if [[ ${gen_exit} -ne 0 && ${gen_exit} -ne 1 ]]; then
  echo "Error: brew generate-tap-man-completions exited with code ${gen_exit}" >&2
  exit "${gen_exit}"
fi

# Sync generated files back to the dev clone
echo "==> Syncing completions/ and manpages/ to dev clone..." >&2
for subdir in completions/bash completions/zsh completions/fish manpages; do
  src="${TAP_DIR}/${subdir}"
  dst="${DEV_DIR}/${subdir}"
  [[ -d ${src} ]] || continue
  mkdir -p "${dst}"
  # Copy all generated files, not .license sidecars (those are managed by annotate.sh)
  for f in "${src}"/*; do
    [[ -f ${f} ]] || continue
    base="$(basename "${f}")"
    [[ ${base} == *.license ]] && continue
    cp "${f}" "${dst}/"
  done
done

# Check for stale files in dev clone that were removed from tap
for subdir in completions/bash completions/zsh completions/fish manpages; do
  dst="${DEV_DIR}/${subdir}"
  src="${TAP_DIR}/${subdir}"
  [[ -d ${dst} ]] || continue
  for f in "${dst}"/*; do
    [[ -f ${f} ]] || continue
    base="$(basename "${f}")"
    [[ ${base} == *.license ]] && continue
    if [[ ! -f "${src}/${base}" ]]; then
      echo "==> Removing stale: ${subdir}/${base}" >&2
      rm -f "${f}"
      # Also remove the .license sidecar if present
      rm -f "${f}.license"
    fi
  done
done

# Show what changed in the dev clone
if ! git -C "${DEV_DIR}" diff --quiet completions/ manpages/ 2>/dev/null; then
  echo "==> Changes in dev clone:" >&2
  git -C "${DEV_DIR}" diff --stat completions/ manpages/
fi

# Restore the tap repo to its clean state now that files have been copied.
# The generator wrote into the tap repo; discard those changes so
# brew update doesn't see a dirty tree.
echo "==> Restoring tap repository to clean state..." >&2
git -C "${TAP_DIR}" restore completions/ manpages/ 2>/dev/null || true
git -C "${TAP_DIR}" clean -fd completions/ manpages/ 2>/dev/null || true

# If --open-pr, commit changes in the dev clone on a new branch and open a PR.
if [[ ${OPEN_PR} == true ]]; then
  echo "" >&2
  if git -C "${DEV_DIR}" diff --quiet completions/ manpages/ &&
    git -C "${DEV_DIR}" diff --cached --quiet completions/ manpages/ 2>/dev/null; then
    echo "==> No changes to commit." >&2
    exit 0
  fi

  echo "==> Creating branch '${BRANCH}' in dev clone..." >&2
  git -C "${DEV_DIR}" switch --create "${BRANCH}" 2>/dev/null ||
    git -C "${DEV_DIR}" switch "${BRANCH}" 2>/dev/null ||
    {
      echo "Error: could not create or switch to branch ${BRANCH}" >&2
      exit 1
    }

  echo "==> Committing changes..." >&2
  git -C "${DEV_DIR}" add completions/ manpages/
  git -C "${DEV_DIR}" commit -m "Update completions and man pages [bot]"

  echo "==> Pushing branch..." >&2
  if git -C "${DEV_DIR}" push --set-upstream origin "${BRANCH}" 2>/dev/null; then
    # Check if a PR already exists before creating one
    existing_url="$(gh pr list --repo "${GH_REPO}" --head "${BRANCH}" --state open --json url --jq '.[0].url' 2>/dev/null || true)"
    if [[ -n ${existing_url} ]]; then
      echo "==> PR already open: ${existing_url}" >&2
    elif command -v gh >/dev/null 2>&1; then
      echo "==> Opening PR via gh..." >&2
      # Backticks in --body are literal markdown, not command substitution
      # shellcheck disable=SC2016
      gh pr create \
        --repo "${GH_REPO}" \
        --head "${BRANCH}" \
        --title "Update completions and man pages" \
        --body 'Auto-generated by `scripts/run-generate-tap-man-completions.sh --open-pr`.' \
        2>/dev/null || echo "==> gh pr create failed — check manually." >&2
    else
      echo "==> gh not available. Push succeeded; open a PR manually for branch '${BRANCH}'." >&2
    fi
  else
    echo "==> Push failed (you may need to push manually)." >&2
  fi

  echo "==> Switching dev repo back to previous branch..." >&2
  git -C "${DEV_DIR}" switch - 2>/dev/null || true

  echo "==> After the PR is merged, run 'brew update' to sync the tap repo." >&2
fi
