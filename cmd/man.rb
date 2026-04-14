# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "system_command"
require "tempfile"

module Homebrew
  module Cmd
    # Opens man pages for Homebrew-installed formulae.
    class Man < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        usage_banner "`man` [<options>] <formula> [<manpage>]\n" \
                     "`man` (`--list`|`--interactive`) <manpage>"
        description <<~EOS
          Display a man page bundled with an installed formula.

          Homebrew kegs (especially keg-only formulae) are not on the default
          `MANPATH`, so `man` does not reliably find their pages. When multiple
          providers ship the same page name, `man` silently returns the first
          match. This command resolves man pages **by formula** and makes
          ambiguity explicit.

          By default, `brew man <formula>` resolves man pages within the
          specified formula only. The optional <manpage> argument defaults to
          the formula name. With `--html`, renders the man page via
          `mandoc -T html` and opens it in a browser (respecting
          `HOMEBREW_BROWSER` or `BROWSER`).

          Use `--list` or `--interactive` to search across system and other
          Homebrew formulae. With `--list`, shows all locations where a given
          man page is found (both system paths and Homebrew formula kegs).

          With `--interactive`, presents a numbered list with origin labels
          to interactively select which copy of a man page to view.
        EOS

        switch "--html", "-H",
               description: "Render the man page as HTML and open it in a browser " \
                            "(respects `HOMEBREW_BROWSER` or `BROWSER`)."
        switch "--list", "-l",
               description: "List all locations where the named man page is found."
        switch "--interactive", "-i",
               description: "Interactively resolve ambiguity when multiple copies " \
                            "of a man page are found."

        conflicts "--html", "--list"
        conflicts "--html", "--interactive"
        conflicts "--list", "--interactive"

        named_args :installed_formula, min: 1
      end

      sig { override.void }
      def run
        if args.list?
          list_manpages(T.must(args.named.first))
        elsif args.interactive?
          file = interactive_manpage(T.must(args.named.first))
          render(file)
        else
          formula_name = T.must(args.named.first)
          page = args.named.second || formula_name
          file = find_formula_manpage(formula_name, page)
          render(file)
        end
      end

      private

      # Finds the man page file inside a formula's installed keg.
      sig { params(formula_name: String, page: String).returns(Pathname) }
      def find_formula_manpage(formula_name, page)
        formula = Formula[formula_name]
        prefix = formula.opt_prefix
        odie "Formula not installed: #{formula_name}" unless prefix.exist?

        manpath = prefix/"share/man"
        result = Utils.popen_read({ "MANPATH" => manpath.to_s }, require_man_cmd.to_s, "-w", page).strip
        odie "Man page not found: #{page} in #{formula_name}" if result.empty?

        Pathname(result)
      end

      # Lists all locations where a man page is found.
      sig { params(name: String).void }
      def list_manpages(name)
        results = collect_manpages(name)

        ohai "#{name} found in:"
        results.each do |label, file|
          puts "  #{label}: #{file}"
        end
      end

      # Interactively selects a man page from a numbered list with origin labels.
      sig { params(name: String).returns(Pathname) }
      def interactive_manpage(name)
        choices = collect_manpages(name)
        odie "No man pages found for: #{name}" if choices.empty?

        choices.each_with_index do |(label, file), i|
          puts "  #{i + 1}) #{label}: #{file}"
        end

        $stdout.write "Choose [1-#{choices.length}]: "
        $stdout.flush
        input = $stdin.gets
        odie "No selection made." if input.nil?

        index = input.strip.to_i - 1
        odie "Invalid selection." if index.negative? || index >= choices.length

        T.must(choices[index]).last
      end

      # Returns all locations where a man page is found, as [label, Pathname] pairs.
      # Uses `man -w` per MANPATH entry for robust page resolution (handles
      # compressed pages, symlinks, and platform-specific man page locations).
      sig { params(name: String).returns(T::Array[[String, Pathname]]) }
      def collect_manpages(name)
        man_cmd = require_man_cmd

        choices = T.let([], T::Array[[String, Pathname]])
        seen = T.let(Set.new, T::Set[String])

        system_manpath.each do |dir|
          path = resolve_manpage(man_cmd, dir, name, seen)
          choices << ["system", path] if path
        end

        formula_man_dirs.each do |formula, man_dir|
          path = resolve_manpage(man_cmd, man_dir, name, seen)
          choices << [formula, path] if path
        end

        choices
      end

      # Resolves a man page within a single MANPATH directory using `man -w`,
      # deduplicating by realpath. Returns nil if not found or already seen.
      sig {
        params(man_cmd: Pathname, manpath_dir: Pathname, name: String,
               seen: T::Set[String]).returns(T.nilable(Pathname))
      }
      def resolve_manpage(man_cmd, manpath_dir, name, seen)
        result = Utils.popen_read({ "MANPATH" => manpath_dir.to_s }, man_cmd.to_s, "-w", name).strip
        return if result.empty?

        path = Pathname(result)
        return unless path.exist?

        real = path.realpath.to_s
        return if seen.include?(real)

        seen.add(real)
        path
      end

      # Renders a man page file, either via man(1) or as HTML in a browser.
      sig { params(file: Pathname).void }
      def render(file)
        if args.html?
          render_html(file)
        else
          safe_system require_man_cmd.to_s, file.to_s
        end
      end

      # Renders the man page as HTML and opens it in a browser.
      sig { params(file: Pathname).void }
      def render_html(file)
        mandoc_cmd = which("mandoc")
        odie "`mandoc` is required for --html but not found on PATH." if mandoc_cmd.nil?

        tmpfile = Tempfile.new(["brew-man-", ".html"])
        begin
          html = Utils.popen_read(mandoc_cmd.to_s, "-T", "html", file.to_s)
          odie "mandoc failed to render #{file}" if html.empty?

          tmpfile.write(html)
          tmpfile.close

          exec_browser tmpfile.path
        ensure
          tmpfile.close!
        end
      end

      # Returns the list of system man directories from manpath(1).
      sig { returns(T::Array[Pathname]) }
      def system_manpath
        manpath_cmd = which("manpath")
        odie "`manpath` is required but not found on PATH." if manpath_cmd.nil?
        Utils.popen_read(manpath_cmd.to_s).strip.split(":").map { |d| Pathname(d) }
      end

      # Returns pairs of [formula_name, man_dir] for all installed formulae
      # that have any man section directory under share/man/.
      sig { returns(T::Array[[String, Pathname]]) }
      def formula_man_dirs
        man_section_glob = HOMEBREW_PREFIX/"opt/*/share/man/man*"
        seen = T.let(Set.new, T::Set[String])
        Pathname.glob(man_section_glob).filter_map do |section_dir|
          man_dir = section_dir.parent
          formula_name = man_dir.parent.parent.basename.to_s
          next if seen.include?(formula_name)

          seen.add(formula_name)
          [formula_name, man_dir]
        end
      end

      # Cached lookup for `man(1)`. Dies if not found.
      sig { returns(Pathname) }
      def require_man_cmd
        @require_man_cmd ||= T.let(which("man"), T.nilable(Pathname))
        odie "`man` is required but not found on PATH." if @require_man_cmd.nil?
        T.must(@require_man_cmd)
      end
    end
  end
end
