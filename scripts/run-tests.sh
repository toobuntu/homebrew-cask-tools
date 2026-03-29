#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# Run brew tests for the purge-quarantine command.
#
# brew tests only finds specs inside $(brew --repo)/Library/Homebrew/test/.
# This script creates temporary hardlinks (not symlinks — parallel_rspec uses
# File.stat which follows symlinks but requires the link target to be resolved
# relative to the Homebrew working directory) then unlinks them on exit.
#
# Usage:
#   chmod +x scripts/run-tests.sh
#   scripts/run-tests.sh
#
# Do NOT run other brew commands while this script is active. In particular:
#   - brew update / brew upgrade   — may run `git fetch` inside $(brew --repo)
#   - brew update-reset            — runs `git reset --hard && git clean -fd`,
#                                    which removes untracked files including the
#                                    hardlinked copies of our files
#   - brew cleanup / brew autoremove
#
# If any of those commands are run concurrently, brew tests may fail or produce
# incorrect results. The EXIT trap below removes the hardlinks when this script
# finishes (or is interrupted), but cannot protect against concurrent git clean.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BREW_REPO="$(brew --repo)"
HOMEBREW_LIB="${BREW_REPO}/Library/Homebrew"

CMD_SRC="${TAP_DIR}/cmd/purge-quarantine.rb"
SPEC_SRC="${TAP_DIR}/test/cmd/purge-quarantine_spec.rb"
CMD_DST="${HOMEBREW_LIB}/cmd/purge-quarantine.rb"
SPEC_DST="${HOMEBREW_LIB}/test/cmd/purge-quarantine_spec.rb"

cleanup() {
  local exit_code=$?
  echo "" >&2
  echo "==> Removing hardlinks from Homebrew repository..." >&2
  rm -f "${CMD_DST}" "${SPEC_DST}"
  exit "${exit_code}"
}
trap cleanup EXIT INT TERM

cat >&2 <<'WARNING'
╔══════════════════════════════════════════════════════════════════════╗
║  WARNING: brew purge-quarantine tests are about to run.              ║
║                                                                      ║
║  The command and spec will be temporarily hardlinked into:           ║
║    $(brew --repo)/Library/Homebrew/cmd/                              ║
║    $(brew --repo)/Library/Homebrew/test/cmd/                         ║
║                                                                      ║
║  Do NOT run brew update, brew upgrade, brew update-reset, or any     ║
║  git operations inside the Homebrew repository until tests finish.   ║
║  Doing so may remove the hardlinks and cause tests to fail.          ║
╚══════════════════════════════════════════════════════════════════════╝
WARNING

# Check that source files exist.
for src in "${CMD_SRC}" "${SPEC_SRC}"; do
  if [[ ! -f "${src}" ]]; then
    echo "Error: source file not found: ${src}" >&2
    exit 1
  fi
done

# Hardlink files into the Homebrew repository, clobbering any existing copies
# from a previous run. Hardlinks are required because parallel_rspec calls
# File.stat on the spec path relative to HOMEBREW_LIBRARY_PATH; symlinks that
# point outside that tree fail with ENOENT.
echo "==> Hardlinking files into Homebrew repository..." >&2
for pair in "${CMD_SRC}:${CMD_DST}" "${SPEC_SRC}:${SPEC_DST}"; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  [[ -e "${dst}" ]] && echo "==> (replacing existing ${dst##*/})" >&2
  ln -f "${src}" "${dst}"
done

echo "==> Running: brew tests --only=cmd/purge-quarantine" >&2
brew tests --only=cmd/purge-quarantine
