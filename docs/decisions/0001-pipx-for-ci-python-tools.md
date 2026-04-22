---
number: 1
title: Use pipx to install Python CLI tools in CI
status: accepted
date: 2026-04-21
---

<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# Use pipx to install Python CLI tools in CI

## Context and Problem Statement

GitHub Actions workflows occasionally need Python CLI tools (e.g., `reuse`).
Three installation mechanisms are available on `ubuntu-latest` runners: apt-get,
Homebrew, and pipx.

**apt-get** packages for Python tools lag significantly behind PyPI releases.

**Homebrew** requires PATH initialization
(`eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"`) and, for anything
beyond a single tool, the `Homebrew/actions/setup-homebrew` and
`Homebrew/actions/cache-homebrew-prefix` reusable actions. This overhead is
appropriate when multiple non-Python tools are being installed together (as in
`copilot-setup-steps.yml`), but is disproportionate for a single Python CLI.

**pip** direct installs are inadvisable for two reasons. First, Python 3.12 on
ubuntu-24.04 is installed via apt and is therefore marked externally managed per
[PEP 668]; pip 23+ refuses installs into such environments unless
`--break-system-packages` is passed. The runner image currently papers over this
with a `break-system-packages = true` entry in `/etc/pip.conf`, but the image
source explicitly labels this a `temporary workaround` ([`install-python.sh`
L15–21][install-python]), so its longevity cannot be relied upon. Second, pip
provides no environment isolation — packages install into the system Python
environment, which can cause conflicts.

**pipx** is the correct tool for this use case. The runner image pre-installs it
with a non-default configuration, established in [`install-python.sh`][install-python]:

```shell
export PIPX_BIN_DIR=/opt/pipx_bin
export PIPX_HOME=/opt/pipx
python3 -m pip install pipx
python3 -m pipx ensurepath
```

These values are then written persistently to `/etc/environment` via
`set_etc_environment_variable`, and `/opt/pipx_bin` is prepended to `PATH` via
`prepend_etc_environment_path` (see [`etc-environment.sh` L44–66][etc-environment]).
The image also prepends `$HOME/.local/bin` to `PATH` in the same script, but that
entry is a fallback for pip-installed scripts; pipx resolves binary destinations
exclusively from `$PIPX_BIN_DIR`.

When a workflow step runs `pipx install <package>`, pipx creates an isolated
virtualenv under `$PIPX_HOME` and places the binary in `$PIPX_BIN_DIR`
(`/opt/pipx_bin`), which is already on `PATH`. The binary is therefore available
in all subsequent steps with no additional configuration — no PATH manipulation,
no `pipx ensurepath`, no `actions/setup-python`.

[PEP 668]: https://peps.python.org/pep-0668/
[issue-10781]: https://github.com/actions/runner-images/issues/10781
[install-python]: https://github.com/actions/runner-images/blob/1df4f9740058bffbf8e0ac75516ebf8423b93365/images/ubuntu/scripts/build/install-python.sh
[etc-environment]: https://github.com/actions/runner-images/blob/1df4f9740058bffbf8e0ac75516ebf8423b93365/images/ubuntu/scripts/helpers/etc-environment.sh#L44-L66

## Decision Outcome

Install Python CLI tools in CI using `pipx install <package>`.

Do not cache single small packages: the install time does not justify the added
workflow complexity.

### Consequences

* Good, because workflow steps are a single line: `run: pipx install <package>`.
* Good, because PyPI versions are used directly, avoiding apt-get staleness.
* Neutral, because this pattern does not extend to non-Python tools, which
  continue to use Homebrew where appropriate.
