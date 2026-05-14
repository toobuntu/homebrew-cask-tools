---
# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

number: 1
title: Use pipx to install Python CLI tools in CI
status: accepted
date: 2026-05-13
decision-makers:
  - toobuntu
---

# Use pipx to install Python CLI tools in CI

## Context and Problem Statement

GitHub Actions workflows occasionally need Python CLI tools (e.g., `reuse`).
Three installation mechanisms are available on `ubuntu-latest` runners:
apt-get, Homebrew, and pipx. Plus `pip` itself, which is a fourth option
with its own issues. Each has tradeoffs; the cheapest tool that satisfies
the requirements should win.

## Decision Drivers

* PyPI freshness — apt-get packages for Python tools lag significantly
  behind PyPI releases.
* Overhead proportional to scope — installing one Python CLI shouldn't
  require Homebrew tap setup, PATH initialization, and reusable-action
  caching.
* PEP 668 compliance — Python 3.12 on ubuntu-24.04 is externally managed;
  pip 23+ refuses installs without `--break-system-packages`. The runner
  image papers over this with a `break-system-packages = true` entry in
  `/etc/pip.conf`, but the image source labels this a "temporary workaround"
  ([`install-python.sh` L15-21][install-python]) whose longevity cannot
  be relied upon.
* Environment isolation — system-wide pip installs can cause conflicts
  between concurrently-installed Python packages.

## Considered Options

* **apt-get** — system package manager. Stale PyPI versions.
* **Homebrew via `Homebrew/actions/setup-homebrew`** — requires
  PATH initialization via the reusable action plus, for repeat
  workflow runs, `Homebrew/actions/cache-homebrew-prefix` for
  binary caching. Appropriate when multiple non-Python tools are
  being installed together (as in `copilot-setup-steps.yml`), but
  disproportionate for a single Python CLI.
* **Homebrew via absolute path** — pre-installed Linuxbrew lives
  at `/home/linuxbrew/.linuxbrew/` on `ubuntu-latest` runners, but
  its `bin/` is not on PATH by default. The lightweight pattern
  (used in `~/devel/claude/desktop/babble/.github/workflows/tests.yml`):
  one `run:` step appending `/home/linuxbrew/.linuxbrew/bin` to
  `$GITHUB_ENV`, followed by one or more `run:` steps invoking
  `/home/linuxbrew/.linuxbrew/bin/brew install <pkg>` directly.
  No setup action, no cache action, no full `brew shellenv` eval.
  Adds two steps minimum (PATH echo plus install), but the PATH
  echo is one-time-per-job and amortizes across any number of
  brew-installed tools.
* **pip direct install** — blocked by PEP 668; bypass via
  `--break-system-packages` works today but the runner image's
  papering-over of this is explicitly labeled a temporary workaround.
  Also no environment isolation.
* **pipx** — pre-installed on `ubuntu-latest` with
  `PIPX_BIN_DIR=/opt/pipx_bin` and `PIPX_HOME=/opt/pipx`, both
  persistently set via `set_etc_environment_variable` in
  [`etc-environment.sh` L44-66][etc-environment]. `/opt/pipx_bin` is
  prepended to PATH in the same script. Each `pipx install` gets its
  own isolated virtualenv; the binary lands on PATH without any manual
  configuration — no `pipx ensurepath`, no `actions/setup-python`,
  no `Homebrew/actions/setup-homebrew`.

## Decision Outcome

The choice is contextual; both pipx and Homebrew-via-absolute-path
are acceptable, and the right one depends on what else the workflow
is doing:

* **pipx** when the workflow installs only Python CLI tool(s) and
  does not otherwise use Homebrew. One step (`pipx install <pkg>`)
  with the binary immediately on PATH. Zero setup overhead.
* **Homebrew via absolute path** when the workflow already installs
  non-Python tools via Homebrew (shellcheck, shfmt, ksh93, etc., as
  in babble's `tests.yml`). The PATH-append step is already there,
  and adding `reuse` to the existing `brew install` line is
  essentially free.
* **`Homebrew/actions/setup-homebrew`** (the full reusable-action
  setup) is appropriate only when the workflow needs Homebrew-specific
  behavior the absolute-path pattern doesn't provide: tap installation,
  developer-mode env vars, prefix caching across runs, or interaction
  with the `Homebrew/actions/cache-homebrew-prefix` action.

Do not cache single small packages in pipx: the install time does
not justify the added workflow complexity.

### Consequences

* Good, because the rule is workflow-shape-driven, not
  package-source-driven. Workflows that need only Python tools stay
  minimal; workflows that already use Homebrew consolidate cleanly.
* Good, because PyPI versions are used directly (via pipx) or current
  Homebrew bottles (via absolute-path brew), both avoiding apt-get
  staleness.
* Good, because both options install isolated, no-cross-tool-conflict
  package surfaces.
* Neutral, because the workflow author has to pick between two valid
  patterns. The decision tree is simple ("does the workflow already
  use brew?") but it is a decision.
* Neutral, because the `Homebrew/actions/setup-homebrew` action remains
  the right choice for the cases it's actually built for (taps,
  caching, developer-mode env). Not deprecated by this ADR; just
  scoped narrowly.
* Bad, because the absolute-path pattern hardcodes the Linuxbrew prefix
  `/home/linuxbrew/.linuxbrew/`. If a future runner image moves the
  install, every workflow using this pattern breaks. Mitigation: the
  prefix is documented in the runner-image source and changes are
  announced; risk is low but non-zero.

## More Information

* [PEP 668](https://peps.python.org/pep-0668/) — externally-managed
  Python environments
* [actions/runner-images install-python.sh][install-python] — runner
  image's pipx configuration; L15-21 documents the
  `--break-system-packages` workaround as temporary
* [actions/runner-images etc-environment.sh L44-66][etc-environment] —
  persistent PATH/env wiring for pipx
* [actions/runner-images issue 10781][issue-10781] — related upstream
  discussion
* `~/devel/claude/desktop/babble/.github/workflows/tests.yml` — the
  Homebrew-via-absolute-path pattern in production use. Installs
  shellcheck, shfmt, ksh93 across two jobs.

[install-python]: https://github.com/actions/runner-images/blob/1df4f9740058bffbf8e0ac75516ebf8423b93365/images/ubuntu/scripts/build/install-python.sh
[etc-environment]: https://github.com/actions/runner-images/blob/1df4f9740058bffbf8e0ac75516ebf8423b93365/images/ubuntu/scripts/helpers/etc-environment.sh#L44-L66
[issue-10781]: https://github.com/actions/runner-images/issues/10781
