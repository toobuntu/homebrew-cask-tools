#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# Run brew generate-tap-man-completions for this tap.
#
# This script is designed to be run from the **development clone** of the tap
# repository (e.g. ~/devel/github/homebrew-cask-tools). It:
#
# 1. Hardlinks dev-cmd/generate-tap-man-completions.rb into Homebrew's core
#    cmd/ directory so `brew` can discover it (Homebrew does not support
#    external dev-cmd/ in third-party taps).
# 2. Runs the command with --tap= pointed at the Homebrew-managed tap directory
#    (the one under $(brew --repo)), which is where the generated files live.
# 3. Cleans up the hardlink on exit.
#
# Pass --commit to also commit the changes to the tap repo on a new branch
# and optionally open a PR via `gh`.
#
# Usage:
#   scripts/run-generate-tap-man-completions.sh [--commit] [--debug] [--no-exit-code]
#
# All arguments except --commit are forwarded to the command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEV_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BREW_REPO="$(brew --repo)"
HOMEBREW_LIB="${BREW_REPO}/Library/Homebrew"

CMD_SRC="${DEV_DIR}/dev-cmd/generate-tap-man-completions.rb"
CMD_DST="${HOMEBREW_LIB}/cmd/generate-tap-man-completions.rb"

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

if [[ -z ${TAP_DIR} || ! -d ${TAP_DIR} ]]; then
  echo "Error: tap '${TAP_NAME}' is not installed. Run: brew tap ${TAP_NAME}" >&2
  exit 1
fi

if [[ ! -f ${CMD_SRC} ]]; then
  echo "Error: source file not found: ${CMD_SRC}" >&2
  exit 1
fi

# Parse --commit from our arguments; forward the rest to the command.
COMMIT=false
BREW_ARGS=()
for arg in "$@"; do
  if [[ ${arg} == "--commit" ]]; then
    COMMIT=true
  else
    BREW_ARGS+=("${arg}")
  fi
done

cleanup() {
  echo "" >&2
  echo "==> Removing hardlink from Homebrew repository..." >&2
  rm -f "${CMD_DST}"
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
║  Do NOT run brew update, brew upgrade, brew update-reset, or any     ║
║  git operations inside the Homebrew repository until this finishes.  ║
╚══════════════════════════════════════════════════════════════════════╝
WARNING

echo "==> Hardlinking dev-cmd into Homebrew repository..." >&2
[[ -e ${CMD_DST} ]] && echo "==> (replacing existing ${CMD_DST##*/})" >&2
ln -f "${CMD_SRC}" "${CMD_DST}"

echo "==> Running: HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions --tap=${TAP_NAME} ${BREW_ARGS[*]:-}" >&2
HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions --tap="${TAP_NAME}" "${BREW_ARGS[@]+"${BREW_ARGS[@]}"}" || true

# If --commit, commit changes in the tap repo on a new branch and suggest a PR.
if [[ ${COMMIT} == true ]]; then
  echo "" >&2
  if git -C "${TAP_DIR}" diff --quiet completions/ manpages/; then
    echo "==> No changes to commit." >&2
    exit 0
  fi

  BRANCH="bot/update-completions-man-pages"
  echo "==> Creating branch '${BRANCH}' in ${TAP_DIR}..." >&2
  git -C "${TAP_DIR}" switch --create "${BRANCH}" 2>/dev/null ||
    git -C "${TAP_DIR}" switch "${BRANCH}" 2>/dev/null ||
    {
      echo "Error: could not create or switch to branch ${BRANCH}" >&2
      exit 1
    }

  echo "==> Committing changes..." >&2
  git -C "${TAP_DIR}" add completions/ manpages/
  git -C "${TAP_DIR}" commit -m "Update completions and man pages [bot]"

  echo "==> Pushing branch..." >&2
  if git -C "${TAP_DIR}" push --set-upstream origin "${BRANCH}" 2>/dev/null; then
    if command -v gh >/dev/null 2>&1; then
      # TAP_NAME is user/repo (e.g. toobuntu/cask-tools); gh needs full GitHub
      # owner/repo (toobuntu/homebrew-cask-tools). Insert "homebrew-" after "/".
      GH_REPO="${TAP_NAME/\//\/homebrew-}"
      echo "==> Opening PR via gh..." >&2
      # shellcheck disable=SC2016
      gh pr create \
        --repo "${GH_REPO}" \
        --head "${BRANCH}" \
        --title "Update completions and man pages" \
        --body 'Auto-generated by `scripts/run-generate-tap-man-completions.sh --commit`.' \
        2>/dev/null || echo "==> PR may already exist or gh failed — check manually." >&2
    else
      echo "==> gh not available. Push succeeded; open a PR manually for branch '${BRANCH}'." >&2
    fi
  else
    echo "==> Push failed (you may need to push manually from ${TAP_DIR})." >&2
  fi

  echo "==> Switching tap repo back to main..." >&2
  git -C "${TAP_DIR}" switch main 2>/dev/null || git -C "${TAP_DIR}" switch - 2>/dev/null || true
fi
