#!/bin/sh
# Annotates non-REUSE-compliant files with SPDX copyright and license headers.
# Requires: reuse (pip install reuse), jq
#
# SPDX-FileCopyrightText: Copyright 2026 toobuntu
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

set -e

files=$(reuse lint --json \
  | jq -r '.non_compliant | (.missing_copyright_info + .missing_licensing_info) | unique[]') || true

[ -z "$files" ] && exit 0

annotate() {
  xargs reuse annotate \
    --copyright="Todd Schulman" \
    --merge-copyrights \
    --license="GPL-3.0-or-later OR BSD-2-Clause" \
    --copyright-prefix=spdx-string \
    "$@"
}

printf '%s\n' "$files" | annotate --fallback-dot-license
