#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# Run brew generate-tap-man-completions for this tap.
#
# Homebrew does not support external dev-cmd/ in third-party taps.
# This script creates a temporary hardlink from dev-cmd/ into Homebrew's
# cmd/ directory so `brew generate-tap-man-completions` is available,
# then runs the command and cleans up the hardlink on exit.
#
# Usage:
#   scripts/run-generate-tap-man-completions.sh [--debug] [--no-exit-code]
#
# All arguments are forwarded to the command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BREW_REPO="$(brew --repo)"
HOMEBREW_LIB="${BREW_REPO}/Library/Homebrew"

CMD_SRC="${TAP_DIR}/dev-cmd/generate-tap-man-completions.rb"
CMD_DST="${HOMEBREW_LIB}/cmd/generate-tap-man-completions.rb"

if [[ ! -f "${CMD_SRC}" ]]
then
  echo "Error: source file not found: ${CMD_SRC}" >&2
  exit 1
fi

cleanup() {
  echo "" >&2
  echo "==> Removing hardlink from Homebrew repository..." >&2
  rm -f "${CMD_DST}"
}
trap cleanup EXIT INT TERM

cat >&2 <<'WARNING'
╔══════════════════════════════════════════════════════════════════════╗
║  generate-tap-man-completions is about to run.                       ║
║                                                                      ║
║  The dev-cmd file will be temporarily hardlinked into:               ║
║    $(brew --repo)/Library/Homebrew/cmd/                              ║
║                                                                      ║
║  Do NOT run brew update, brew upgrade, brew update-reset, or any     ║
║  git operations inside the Homebrew repository until this finishes.  ║
╚══════════════════════════════════════════════════════════════════════╝
WARNING

echo "==> Hardlinking dev-cmd into Homebrew repository..." >&2
[[ -e "${CMD_DST}" ]] && echo "==> (replacing existing ${CMD_DST##*/})" >&2
ln -f "${CMD_SRC}" "${CMD_DST}"

echo "==> Running: HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions $*" >&2
HOMEBREW_DEVELOPER=1 brew generate-tap-man-completions "$@"
