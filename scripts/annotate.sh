#!/bin/sh
# Annotates non-REUSE-compliant files with SPDX copyright and license headers.
# Requires: reuse (pip install reuse), jq
#
# SPDX-FileCopyrightText: Copyright 2026 toobuntu
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

set -eu

files=$(reuse lint --json |
  jq -r '.non_compliant | (.missing_copyright_info + .missing_licensing_info) | unique[]') || true

[[ -z "${files}" ]] && exit 0

annotate() {
  xargs reuse annotate \
    --copyright="Todd Schulman" \
    --merge-copyrights \
    --license="GPL-3.0-or-later OR BSD-2-Clause" \
    --copyright-prefix=spdx-string \
    "$@"
}

# Generated completion and man page files must keep their content intact, so annotate
# them with a .license sidecar instead of inline SPDX comment headers.
# This covers: fish completions, bash completions (no extension), zsh completions
# (prefixed with _), man pages (.1, .1.md).
compl_files=$(printf '%s\n' "${files}" | grep -E '(^|/)completions/' || true)
man_files=$(printf '%s\n' "${files}" | grep -E '\.(1|1\.md)$' || true)
# Shell scripts with no file extension need --style=python for reuse to infer the # comment style.
# The pattern (^|/)[^./]+$ matches basenames with no dot (no extension).
remaining=$(printf '%s\n' "${files}" | grep -vE '(^|/)completions/' | grep -vE '\.(1|1\.md)$' || true)
no_ext_files=$(printf '%s\n' "${remaining}" | grep -E '(^|/)[^./]+$' || true)
other_files=$(printf '%s\n' "${remaining}" | grep -vE '(^|/)[^./]+$' || true)

[[ -n "${compl_files}" ]] && printf '%s\n' "${compl_files}" | annotate --force-dot-license
[[ -n "${man_files}" ]] && printf '%s\n' "${man_files}" | annotate --force-dot-license
[[ -n "${no_ext_files}" ]] && printf '%s\n' "${no_ext_files}" | annotate --style=python --fallback-dot-license
[[ -n "${other_files}" ]] && printf '%s\n' "${other_files}" | annotate --fallback-dot-license
