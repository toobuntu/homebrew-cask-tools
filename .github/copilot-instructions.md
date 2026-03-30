<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause
-->

# Copilot Instructions for toobuntu/homebrew-cask-tools

Full instructions are in [AGENTS.md](../AGENTS.md) and [CLAUDE.md](../CLAUDE.md). This file
is a brief orientation; defer to those files for authoritative detail.

## Sandbox setup

`brew` is installed at `/home/linuxbrew/.linuxbrew/bin/brew` but is **not on `PATH`** by
default. Run `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` once per shell session,
or use the full path.

If `brew install-bundler-gems` fails with an SSL certificate error (and
`.github/workflows/copilot-setup-steps.yml` has not yet been merged to `main`), run:

```sh
/home/linuxbrew/.linuxbrew/bin/brew install openssl
/home/linuxbrew/.linuxbrew/bin/brew link openssl --force
/home/linuxbrew/.linuxbrew/bin/brew install curl-ca-bundle
```

## Before committing

Use the **Homebrew MCP Server tools** (preferred over `brew` via bash — no outbound network
needed because bundler gems are pre-cached):

- `Homebrew/style` — equivalent to `brew style --fix --changed`
- `Homebrew/typecheck` — equivalent to `brew typecheck`
- `Homebrew/tests --only=cmd/<name>` — run tests (use `scripts/run-tests.sh` which handles the
  required hardlinks automatically)

Do **not** hand-write SPDX headers; run `scripts/annotate.sh` instead.

## Path-specific instructions

[LICENSES/**](LICENSES/**):
Do not review, comment on, or suggest changes to files in this directory. These are
REUSE-standard license texts managed by `reuse download --all` and must not be modified.
