#!/bin/sh
# Generates man pages for tap commands.
# First, run `brew generate-tap-completions` to update the Ronn markdown sources
# in `manpages/`, then run this script to compile them to roff.
# Requires: brew (Homebrew) with the man bundler gems available.
#
# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

brew ruby - "${REPO_ROOT}" <<'RUBY'
require "pathname"

Homebrew.install_bundler_gems!(groups: ["man"])
require "manpages/parser/ronn"
require "manpages/converter/roff"

repo_root = Pathname(ARGV[0])
man_dir = repo_root / "manpages"

Pathname.glob(man_dir / "*.1.md").sort.each do |md_path|
  markdown = md_path.read
  root, warnings = Homebrew::Manpages::Parser::Ronn.parse(markdown)
  $stderr.puts(warnings) unless warnings.empty?
  roff, warnings = Homebrew::Manpages::Converter::Roff.convert(root)
  $stderr.puts(warnings) unless warnings.empty?
  roff_path = md_path.sub_ext("")
  roff_path.write(roff)
  puts "Generated #{roff_path.relative_path_from(repo_root)}"
end
RUBY
