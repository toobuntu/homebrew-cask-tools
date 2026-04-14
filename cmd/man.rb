# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "system_command"

module Homebrew
  module Cmd
    # Opens man pages for Homebrew-installed formulae.
    class Man < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        usage_banner "`man` [<options>] <formula> [<manpage>]"
        description <<~EOS
          Display a man page bundled with an installed formula.

          In normal mode, shows the man page for <manpage> (defaulting to the
          formula name) from <formula>'s keg using the system `man` viewer.
          With `--html`, renders the man page via `mandoc -T html` and opens it
          in a browser.

          In `--list` mode, shows all locations where a given man page is found
          (both system paths and Homebrew formula kegs).

          In `--select` mode, uses `fzf` to interactively choose which copy of
          a man page to open. Requires `fzf` to be installed.
        EOS

        switch "--html", "-H",
               description: "Render the man page as HTML and open it in a browser."
        switch "--list",
               description: "List all locations where the named man page is found."
        switch "--select",
               description: "Interactively select which copy of the man page to view with `fzf`."

        conflicts "--html", "--list"
        conflicts "--html", "--select"
        conflicts "--list", "--select"

        named_args min: 1
      end

      MAN_PATH = T.let("/usr/bin/man", String)
      MANDOC_PATH = T.let("/usr/bin/mandoc", String)
      OPEN_PATH = T.let("/usr/bin/open", String)

      sig { override.void }
      def run
        raise UsageError, "`brew man` is only supported on macOS." unless OS.mac?

        if args.list?
          list_manpages(T.must(args.named.first))
        elsif args.select?
          file = select_manpage(T.must(args.named.first))
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
        result = Utils.popen_read({ "MANPATH" => manpath.to_s }, MAN_PATH, "-w", page).strip
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

      # Interactively selects a man page using fzf.
      sig { params(name: String).returns(Pathname) }
      def select_manpage(name)
        odie "fzf not installed. Install it with: brew install fzf" unless which("fzf")

        choices = T.let([], T::Array[String])

        system_manpath.each do |dir|
          file = dir/"man1/#{name}.1"
          choices << "system:#{file}" if file.exist?
        end

        formula_man_dirs.each do |formula, dir|
          file = dir/"#{name}.1"
          choices << "#{formula}:#{file}" if file.exist?
        end

        odie "No man pages found for: #{name}" if choices.empty?

        result = Utils.popen_read("fzf", input: choices.join("\n")).strip
        odie "No selection made." if result.empty?

        path_str = T.must(result.split(":", 2).last)
        Pathname(path_str)
      end

      # Renders a man page file, either via man(1) or as HTML in a browser.
      sig { params(file: Pathname).void }
      def render(file)
        if args.html?
          render_html(file)
        else
          safe_system MAN_PATH, file.to_s
        end
      end

      # Renders the man page as HTML and opens it in a browser.
      sig { params(file: Pathname).void }
      def render_html(file)
        tmpfile = Tempfile.new(["brew-man-", ".html"])
        begin
          html = Utils.popen_read(MANDOC_PATH, "-T", "html", file.to_s)
          odie "mandoc failed to render #{file}" if html.empty?

          tmpfile.write(html)
          tmpfile.close

          browser = resolve_browser
          if browser
            safe_system browser, tmpfile.path
          else
            safe_system OPEN_PATH, tmpfile.path
          end
        ensure
          tmpfile.close!
        end
      end

      # Resolves the browser to use, following Homebrew's environment model:
      # 1. HOMEBREW_BROWSER from shell environment (including brew.env)
      # 2. BROWSER from shell environment
      # Falls back to nil (caller uses system default via /usr/bin/open).
      sig { returns(T.nilable(String)) }
      def resolve_browser
        Homebrew::EnvConfig.browser || ENV.fetch("BROWSER", nil).presence
      end

      # Returns the list of system man directories from manpath(1).
      sig { returns(T::Array[Pathname]) }
      def system_manpath
        Utils.popen_read("/usr/bin/manpath").strip.split(":").map { |d| Pathname(d) }
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
