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
        usage_banner "`man` [<options>] <formula> [<manpage>]\n            " \
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
        return Pathname(result) unless result.empty?

        # man(1) cannot resolve filenames that include a section suffix
        # (e.g. openssl.1ssl). Fall back to a direct filesystem search
        # that also handles compressed pages (.gz, .bz2, .xz, .zst, …).
        escaped = page.gsub(/[*?\[\]{}\\]/) { |c| "\\#{c}" }
        match = Pathname.glob(manpath/"man*/#{escaped}").select(&:file?).min ||
                Pathname.glob(manpath/"man*/#{escaped}.*").select(&:file?).min ||
                Pathname.glob(manpath/"man*/#{escaped}*").select(&:file?).min
        odie "Man page not found: #{page} in #{formula_name}" if match.nil?

        match
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
      # Processes formula kegs first (via filesystem glob for speed) so that
      # realpath deduplication attributes Homebrew-linked pages to their
      # providing formula rather than labeling them "system".
      sig { params(name: String).returns(T::Array[[String, Pathname]]) }
      def collect_manpages(name)
        man_cmd = require_man_cmd
        choices = T.let([], T::Array[[String, Pathname]])
        seen = T.let(Set.new, T::Set[String])

        # Homebrew formula kegs: direct filesystem glob — equivalent to what
        # man(1) does internally since kegs have no mandoc.db. The glob
        # pattern `.[0-9]*` matches compressed pages and non-standard
        # suffixes (.1ssl, .3pm, etc.).
        escaped = name.gsub(/[*?\[\]{}\\]/) { |c| "\\#{c}" }
        formula_man_dirs.each do |formula, man_dir|
          path = Pathname.glob(man_dir/"man*/#{escaped}.[0-9]*").min
          # Name may already include a section suffix (e.g. openssl.1ssl);
          # try exact match and compressed variants as fallback.
          if path.nil?
            path = Pathname.glob(man_dir/"man*/#{escaped}").min ||
                   Pathname.glob(man_dir/"man*/#{escaped}.*").min
          end
          next if path.nil?
          next unless path.exist?

          real = path.realpath.to_s
          next if seen.include?(real)

          seen.add(real)
          choices << [formula, path]
        end

        # System pages: single `man -wa` for platform-specific locations
        # (e.g. Xcode SDK paths configured via /etc/man.conf on macOS)
        # and mandoc database lookup.
        Utils.popen_read(man_cmd.to_s, "-w", "-a", name).strip.each_line do |line|
          path = Pathname(line.strip)
          next unless path.exist?

          real = path.realpath.to_s
          next if seen.include?(real)

          seen.add(real)
          choices << ["system", path]
        end

        choices
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

      # Returns pairs of [formula_name, man_dir] for all installed formulae
      # that have any man section directory under share/man/.
      sig { returns(T::Array[[String, Pathname]]) }
      def formula_man_dirs
        man_section_glob = HOMEBREW_PREFIX/"opt/*/share/man/man*"
        seen = T.let(Set.new, T::Set[String])
        Pathname.glob(man_section_glob).sort.filter_map do |section_dir|
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
