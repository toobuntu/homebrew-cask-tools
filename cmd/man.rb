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

          With an explicit <formula> and optional <manpage> (defaulting to the
          formula name), always opens that formula's copy using the system `man`
          viewer. With `--html`, renders the man page via `mandoc -T html` and
          opens it in a browser (respecting `HOMEBREW_BROWSER` or `BROWSER`).

          With a single <manpage> argument (no explicit formula), searches all
          installed formula kegs and system paths. If exactly one copy is found,
          opens it. If multiple copies are found, exits with an actionable error
          listing all matches and suggesting next steps.

          With `--list`, shows all locations where a given man page is found
          (both system paths and Homebrew formula kegs).

          With `--interactive`, presents a numbered list to interactively resolve
          ambiguity when multiple copies of a man page are found.
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

        named_args min: 1
      end

      sig { override.void }
      def run
        if args.list?
          list_manpages(T.must(args.named.first))
        elsif args.named.length >= 2
          formula_name = T.must(args.named.first)
          page = T.must(args.named.second)
          file = find_formula_manpage(formula_name, page)
          render(file)
        elsif args.interactive?
          file = interactive_manpage(T.must(args.named.first))
          render(file)
        else
          file = resolve_manpage(T.must(args.named.first))
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

        man_cmd = which("man")
        odie "`man` is required but not found on PATH." if man_cmd.nil?

        manpath = prefix/"share/man"
        result = Utils.popen_read({ "MANPATH" => manpath.to_s }, man_cmd.to_s, "-w", page).strip
        odie "Man page not found: #{page} in #{formula_name}" if result.empty?

        Pathname(result)
      end

      # Lists all locations where a man(1) page is found.
      sig { params(name: String).void }
      def list_manpages(name)
        ohai "#{name}(1) found in:"

        system_manpath.each do |dir|
          file = dir/"man1/#{name}.1"
          puts "  system: #{file}" if file.exist?
        end

        formula_man_dirs.each do |formula, dir|
          file = dir/"#{name}.1"
          puts "  #{formula}: #{file}" if file.exist?
        end
      end

      # Resolves a man page by searching all locations; opens it when unambiguous,
      # or exits with an actionable error when multiple copies are found.
      sig { params(name: String).returns(Pathname) }
      def resolve_manpage(name)
        choices = collect_manpages(name)
        odie "No man pages found for: #{name}" if choices.empty?
        return T.must(choices.first).last if choices.length == 1

        lines = choices.map { |(label, file)| "  #{label}: #{file}" }.join("\n")
        odie <<~EOS
          multiple matches found for '#{name}':

          #{lines}

          Use one of:
            brew man <formula> #{name}
            brew man --interactive #{name}
            brew man --list #{name}
        EOS
      end

      # Interactively selects a man page from a numbered list.
      sig { params(name: String).returns(Pathname) }
      def interactive_manpage(name)
        choices = collect_manpages(name)
        odie "No man pages found for: #{name}" if choices.empty?
        return T.must(choices.first).last if choices.length == 1

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

      # Returns all locations where a man(1) page is found, as [label, Pathname] pairs.
      sig { params(name: String).returns(T::Array[[String, Pathname]]) }
      def collect_manpages(name)
        choices = T.let([], T::Array[[String, Pathname]])

        system_manpath.each do |dir|
          file = dir/"man1/#{name}.1"
          choices << ["system", file] if file.exist?
        end

        formula_man_dirs.each do |formula, dir|
          file = dir/"#{name}.1"
          choices << [formula, file] if file.exist?
        end

        choices
      end

      # Renders a man page file, either via man(1) or as HTML in a browser.
      sig { params(file: Pathname).void }
      def render(file)
        if args.html?
          render_html(file)
        else
          man_cmd = which("man")
          odie "`man` is required but not found on PATH." if man_cmd.nil?
          safe_system man_cmd.to_s, file.to_s
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

      # Returns pairs of [formula_name, man1_dir] for all installed formulae
      # that have a man1 directory.
      sig { returns(T::Array[[String, Pathname]]) }
      def formula_man_dirs
        man1_glob = HOMEBREW_PREFIX/"opt/*/share/man/man1"
        Pathname.glob(man1_glob).filter_map do |dir|
          formula_name = dir.parent.parent.parent.basename.to_s
          [formula_name, dir]
        end
      end
    end
  end
end
