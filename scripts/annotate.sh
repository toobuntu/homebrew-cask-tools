#!/bin/sh
# Annotates non-REUSE-compliant files with SPDX copyright and license headers.
# Requires: reuse (pip install reuse), jq
#
# SPDX-FileCopyrightText: Copyright 2026 toobuntu
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

set -e

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

# Fish completion and man page files must keep their generated content intact, so annotate
# them with a .license sidecar instead of inline SPDX comment headers.
fish_files=$(printf '%s\n' "${files}" | grep '\.fish$' || true)
man_files=$(printf '%s\n' "${files}" | grep '\.\(1\|1\.md\)$' || true)
other_files=$(printf '%s\n' "${files}" | grep -v '\.\(fish\|1\|1\.md\)$' || true)

[[ -n "${fish_files}" ]] && printf '%s\n' "${fish_files}" | annotate --force-dot-license
[[ -n "${man_files}" ]] && printf '%s\n' "${man_files}" | annotate --force-dot-license
[[ -n "${other_files}" ]] && printf '%s\n' "${other_files}" | annotate --fallback-dot-license
