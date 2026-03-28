# Agent Instructions for toobuntu/homebrew-cask-tools

This repository provides Homebrew external tap commands, currently `brew purge-quarantine`.
Code quality and style should be at a level suitable for potential inclusion in Homebrew.

Run `brew style --fix --changed && brew typecheck` to verify any file edits before committing.

## Homebrew in the Copilot Coding Agent Sandbox

`brew` is installed at `/home/linuxbrew/.linuxbrew/bin/brew` (via `.github/copilot-setup-steps.yml`)
but is **not on `PATH`** by default. Either:

- run `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` once per shell session, or
- use the full path `/home/linuxbrew/.linuxbrew/bin/brew` directly.

The cellar is empty (`core: false, cask: false`), but `brew style`, `brew typecheck`,
`brew tests`, and `brew mcp-server` all work because they only need the Homebrew runtime
and bundler gems (cached by `copilot-setup-steps.yml`).

## Code Standards

### Required Before Each Commit

- Run `brew typecheck` to verify types are declared correctly using Sorbet.
- Run `brew style --fix --changed` to lint code formatting using RuboCop.
  Individual files can be checked with `brew style --fix path/to/file.rb`.
- Run `brew tests --only=cmd/purge-quarantine` to ensure RSpec unit tests pass.
  Requires the cmd and spec to be hardlinked into `$(brew --repo)/Library/Homebrew/` first — use `scripts/run-tests.sh`.
- All of the above can be run via the Homebrew MCP Server (launch with `brew mcp-server`).

### Development Flow

- Write new code (using Sorbet `sig` type signatures and `typed: strict` for new files, but never for RSpec/test/`*_spec.rb` files)
- Write new tests (avoid more than one `:integration_test` per file for speed).
  Write fast tests by preferring a single `expect` per unit test and combine expectations in a single test when it is an integration test or has non-trivial `before` for test setup.
- When adding or tightening tests, verify them with a red/green cycle using the exact `--only=file:line` target for the example you changed.
- Formula classes created in specs may be frozen; avoid stubbing class methods on them with RSpec mocks and prefer instance-level stubs or test setup that does not require class-method stubbing.
- Keep comments minimal; prefer self-documenting code through strings, variable names, etc. over more comments.

## Repository Structure

- `cmd/purge-quarantine.rb`: External tap command implementing `brew purge-quarantine`.
  File name has no `brew-` prefix — Homebrew tap commands use this convention.
- `test/cmd/purge-quarantine_spec.rb`: RSpec spec for the command.
- `scripts/run-tests.sh`: Helper script to hardlink tap files into `$(brew --repo)` and run `brew tests`.
- `.github/workflows/ci.yml`: CI — runs `brew style` and `brew tests`.
- `.github/workflows/actionlint.yml`: CI — runs `actionlint` and `zizmor` code scanning.
- `.mcp.json`: Claude Code project-level MCP server config (used when running `claude` locally).
- `.vscode/mcp.json`: VS Code MCP server config (used in VS Code with Copilot locally).
- `.github/copilot-setup-steps.yml`: Setup steps for GitHub Copilot coding agent — installs Homebrew and caches bundler gems.

## MCP Server Configuration

The Homebrew MCP Server (`brew mcp-server`) provides Homebrew tools to AI coding agents.
It is configured differently per client:

| Client | Config location |
|--------|-----------------|
| Claude Code | `.mcp.json` (in this repo) |
| VS Code | `.vscode/mcp.json` (in this repo) |
| GitHub Copilot coding agent | Repository Settings → Copilot → Coding agent → MCP configuration |

For GitHub Copilot coding agent, add the following JSON in the repository's Copilot settings.
`brew` is available (but not on `PATH`) because `.github/copilot-setup-steps.yml` runs `Homebrew/actions/setup-homebrew`.

```json
{
  "mcpServers": {
    "Homebrew": {
      "type": "local",
      "command": "/home/linuxbrew/.linuxbrew/bin/brew",
      "args": ["mcp-server"],
      "tools": ["*"]
    }
  }
}
```

## Key Guidelines

1. Follow Ruby and Bash best practices and idiomatic patterns.
2. Maintain existing code structure and organisation.
3. Write unit tests for new functionality.
4. Document public APIs and complex logic.
5. Suggest changes to the `docs/` folder when appropriate (create it if needed).
6. Follow software principles such as DRY and YAGNI.
7. Keep diffs as minimal as possible.
8. Prefer shelling out via `HOMEBREW_BREW_FILE` instead of requiring `cmd/` or `dev-cmd` when composing brew commands.
9. Inline new or existing methods as methods or local variables unless they are reused 2+ times or needed for unit tests.
10. Use Sorbet `sig` type signatures and `# typed: strict` for all non-spec Ruby files.
11. Never use `# typed: strict` in RSpec `*_spec.rb` files.
12. Named arguments in `AbstractCommand` subclasses: use `named_args min: 1` (not `:cask` — crashes for deprecated casks).
13. `include SystemCommand::Mixin` (top-level constant, not `Homebrew::SystemCommand::Mixin`).
