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
        usage_banner "`man` [<options>] [<section>] <formula> [<manpage>]\n            " \
                     "`man` `--find` [`--interactive`] [<options>] <manpage>\n            " \
                     "`man` `--list` [`--interactive`] [<options>] <formula>"
        description <<~EOS
          Display a man page bundled with an installed formula.

          Homebrew kegs (especially keg-only formulae) are not on the default
          `MANPATH`, so `man` does not reliably find their pages. When multiple
          providers ship the same page name, `man` silently returns the first
          match. This command resolves man pages **by formula** and makes
          ambiguity explicit.

          By default, `brew man <formula>` resolves man pages within the
          specified formula only. The optional <manpage> argument defaults to
          the formula name; when the formula name has no man page, the
          formula's executables are tried as fallback (e.g. `brew man libressl`
          finds `openssl(1)`). An optional <section> number (e.g. `1`, `3`)
          before the formula name restricts the search to that man section.
          With `--html`, renders the man page via `mandoc -T html` and opens it
          in a browser (respecting `HOMEBREW_BROWSER` or `BROWSER`).

          Use `--find` to search across all installed formulae and the system
          for a man page by name. Shows all locations where a man page name is
          found. Formulae that provide a binary matching the page name are
          also included.

          Use `--list` to list every man page an installed formula provides.

          Add `--interactive` to either `--find` or `--list` to present a
          numbered list for selecting which page to view.
        EOS

        switch "--html", "-H",
               description: "Render the man page as HTML and open it in a browser " \
                            "(respects `HOMEBREW_BROWSER` or `BROWSER`)."
        switch "--find", "-f",
               description: "Find all installed formulae that provide the named man page."
        switch "--list", "-l",
               description: "List every man page provided by the named formula."
        switch "--interactive", "-i",
               description: "Present a numbered list for interactive selection. " \
                            "Requires `--find` or `--list`."

        conflicts "--html", "--find"
        conflicts "--html", "--list"
        conflicts "--html", "--interactive"
        conflicts "--find", "--list"

        named_args :installed_formula, min: 1
      end

      sig { override.void }
      def run
        if args.interactive? && !args.find? && !args.list?
          raise UsageError, "`--interactive` requires `--find` or `--list`."
        end

        name = T.must(args.named.first)

        if args.find?
          if args.interactive?
            file = interactive_manpage(name)
            render(file)
          else
            list_manpages(name)
          end
        elsif args.list?
          if args.interactive?
            file = interactive_all_formula_manpages(name)
            render(file)
          else
            list_all_formula_manpages(name)
          end
        else
          section, formula_name, page = parse_default_args
          file = find_formula_manpage(formula_name, page, section:)
          render(file)
        end
      end

      private

      # Parses default-mode named arguments, detecting an optional
      # leading section number (e.g. `brew man 1 libressl openssl`).
      sig { returns([T.nilable(String), String, String]) }
      def parse_default_args
        named = args.named.to_a
        section = T.let(nil, T.nilable(String))

        if named.length >= 2 && T.must(named.first).match?(/\A\d+\z/)
          section = T.must(named.shift)
          odebug "Detected section argument: #{section}"
        end

        formula_name = T.must(named.first)
        page = named[1] || formula_name
        odebug "Formula: #{formula_name}, page: #{page}, section: #{section.inspect}"
        [section, formula_name, page]
      end

      # Finds the man page file inside a formula's installed keg.
      sig { params(formula_name: String, page: String, section: T.nilable(String)).returns(Pathname) }
      def find_formula_manpage(formula_name, page, section: nil)
        formula = Formula[formula_name]
        prefix = formula.opt_prefix
        odie "Formula not installed: #{formula_name}" unless prefix.exist?

        manpath = prefix/"share/man"
        man_dir_glob = section ? "man#{section}" : "man*"

        man_args = [require_man_cmd.to_s, "-w"]
        man_args << section if section
        man_args << page
        result = Utils.popen_read({ "MANPATH" => manpath.to_s }, *man_args).strip
        unless result.empty?
          odebug "man(1) found: #{result}"
          return Pathname(result)
        end

        # man(1) cannot resolve filenames that include a section suffix
        # (e.g. openssl.1ssl). Fall back to a direct filesystem search
        # that also handles compressed pages (.gz, .bz2, .xz, .zst, …).
        escaped = escape_glob(page)
        match = Pathname.glob(manpath/"#{man_dir_glob}/#{escaped}").select(&:file?).min ||
                Pathname.glob(manpath/"#{man_dir_glob}/#{escaped}.*").select(&:file?).min ||
                Pathname.glob(manpath/"#{man_dir_glob}/#{escaped}*").select(&:file?).min

        # Base name fallback: strip section suffix (e.g. openssl.1ssl → openssl)
        # to find pages with a different section suffix (e.g. openssl.1).
        if match.nil? && page.match?(/\.\d+[a-z]*$/i)
          base = page.sub(/\.\d+[a-z]*$/i, "")
          odebug "Trying base name '#{base}' (stripped section suffix from '#{page}')"
          escaped_base = escape_glob(base)
          match = Pathname.glob(manpath/"#{man_dir_glob}/#{escaped_base}.[0-9]*").select(&:file?).min
        end

        # Binary fallback: when no explicit page was given (page == formula_name)
        # and no match, try executable names shipped by the formula.
        if match.nil? && page == formula_name
          odebug "No man page '#{page}' in #{formula_name}, checking formula binaries"
          formula_binaries(prefix).each do |bin_name|
            escaped_bin = escape_glob(bin_name)
            match = Pathname.glob(manpath/"#{man_dir_glob}/#{escaped_bin}").select(&:file?).min ||
                    Pathname.glob(manpath/"#{man_dir_glob}/#{escaped_bin}.[0-9]*").select(&:file?).min
            if match
              odebug "Resolved to binary '#{bin_name}' → #{match}"
              break
            end
          end
        end

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

      # Lists every man page an installed formula provides.
      sig { params(name: String).void }
      def list_all_formula_manpages(name)
        results = all_formula_manpages(name)
        odie "No man pages found for formula: #{name}" if results.empty?

        ohai "#{name} provides:"
        results.each do |page_name, file|
          puts "  #{page_name}: #{file}"
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

      # Interactively selects from all man pages an installed formula provides.
      sig { params(name: String).returns(Pathname) }
      def interactive_all_formula_manpages(name)
        choices = all_formula_manpages(name)
        odie "No man pages found for formula: #{name}" if choices.empty?

        ohai "#{name} provides:"
        choices.each_with_index do |(page_name, file), i|
          puts "  #{i + 1}) #{page_name}: #{file}"
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
        escaped = escape_glob(name)
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
          odebug "Formula keg match: #{formula} → #{path}"
        end

        # Binary alias: find formulae providing a binary named `name`
        # and include their primary man page (e.g. awk → gawk ships
        # bin/awk and man1/gawk.1).
        [HOMEBREW_PREFIX/"opt/*/bin/#{escaped}",
         HOMEBREW_PREFIX/"opt/*/sbin/#{escaped}"].each do |pattern|
          Pathname.glob(pattern).sort.each do |bin_path|
            next unless bin_path.file?

            opt_dir = bin_path.parent.parent
            fname = opt_dir.basename.to_s
            man_dir = opt_dir/"share/man"
            next unless man_dir.directory?

            escaped_fn = escape_glob(fname)
            path = Pathname.glob(man_dir/"man*/#{escaped_fn}.[0-9]*").min ||
                   Pathname.glob(man_dir/"man*/#{escaped_fn}").min
            next if path.nil? || !path.exist?

            real = path.realpath.to_s
            next if seen.include?(real)

            seen.add(real)
            choices << [fname, path]
            odebug "Binary alias match: #{fname} provides bin/#{name} → #{path}"
          end
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
          odebug "System match: #{path}"
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

      # Returns executable names from a formula's bin and sbin directories.
      sig { params(prefix: Pathname).returns(T::Array[String]) }
      def formula_binaries(prefix)
        result = T.let([], T::Array[String])
        [prefix/"bin", prefix/"sbin"].each do |dir|
          next unless dir.directory?

          dir.children.each do |f|
            result << f.basename.to_s if f.file? || f.symlink?
          end
        end
        result.sort
      end

      # Returns all man pages from a formula's keg as [page_name, path] pairs.
      sig { params(name: String).returns(T::Array[[String, Pathname]]) }
      def all_formula_manpages(name)
        formula = Formula[name]
        prefix = formula.opt_prefix
        return [] unless prefix.exist?

        manpath = prefix/"share/man"
        return [] unless manpath.directory?

        Pathname.glob(manpath/"man*/*").select(&:file?).sort.map do |f|
          [f.basename.to_s, f]
        end
      rescue FormulaUnavailableError
        []
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

      # Escapes glob metacharacters in a string for safe use in Pathname.glob.
      sig { params(str: String).returns(String) }
      def escape_glob(str)
        str.gsub(/[*?\[\]{}\\]/) { |c| "\\#{c}" }
      end
    end
  end
end
