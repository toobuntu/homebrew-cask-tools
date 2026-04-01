# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "tap"

module Homebrew
  module Cmd
    # Extracts a cask into a personal tap, optionally adding quarantine removal.
    class CaskExtract < AbstractCommand
      cmd_args do
        usage_banner "`cask-extract` [<options>] <cask> <tap>"
        description <<~EOS
          Extract a cask from Homebrew's git history into a personal tap.
          Optionally add a postflight block to remove macOS's quarantine
          extended attribute so un-notarized apps can launch without
          Gatekeeper blocking them.

          To extract a cask from a tap other than `homebrew/cask`, use the
          fully-qualified form `user/repo/cask`.
        EOS

        flag   "--version=",
               description: "Extract the cask at this specific version from git history."
        switch "--no-quarantine",
               description: "Add a `postflight` block that removes the quarantine xattr."
        switch "--unversioned",
               description: "Copy without adding a version suffix to the cask token."
        switch "--force",
               description: "Overwrite the destination file if it already exists."
        switch "--no-shard",
               description: "Write to a flat `Casks/` directory instead of a sharded one."

        named_args number: 2
      end

      sig { override.void }
      def run
        source_tap_name, token = resolve_cask_spec(T.must(args.named.first))
        destination_tap_name = T.must(args.named.second)

        destination_tap = Tap.fetch(destination_tap_name)
        destination_tap.install unless destination_tap.installed?

        # --unversioned and --no-shard are only supported in the fallback path;
        # skip delegation when either is set so their semantics are honoured.
        if !args.unversioned? && !args.no_shard? &&
           try_brew_extract_cask(token, destination_tap_name, source_tap_name)
          post_process_extracted_cask(token, destination_tap)
        else
          fallback_extract(token, destination_tap, source_tap_name)
        end
      end

      private

      sig { params(cask_spec: String).returns([String, String]) }
      def resolve_cask_spec(cask_spec)
        parts = cask_spec.split("/")
        if parts.length == 3
          ["#{parts[0]}/#{parts[1]}", parts[2]]
        else
          ["homebrew/cask", cask_spec]
        end
      end

      sig { params(token: String, destination_tap_name: String, source_tap_name: String).returns(T::Boolean) }
      def try_brew_extract_cask(token, destination_tap_name, source_tap_name)
        help_output = Utils.popen_read(HOMEBREW_BREW_FILE, "extract", "--help")
        return false unless help_output.include?("--cask")

        qualified_token = "#{source_tap_name}/#{token}"
        cmd = [HOMEBREW_BREW_FILE, "extract", "--cask", qualified_token, destination_tap_name]
        cmd << "--version=#{args.version}" if args.version
        cmd << "--force" if args.force?

        safe_system(*cmd)
        true
      rescue ErrorDuringExecution
        false
      end

      sig { params(token: String, destination_tap: Tap).void }
      def post_process_extracted_cask(token, destination_tap)
        extracted_token = extracted_cask_token(token)
        extracted_path = find_extracted_cask(extracted_token, token, destination_tap)
        unless extracted_path
          odie "Could not find extracted cask file for #{extracted_token} in #{destination_tap.path}"
        end

        warn_maintainer(token)
        add_quarantine_postflight(extracted_path) if args.no_quarantine?

        ohai "Extracted to:", extracted_path.to_s
        puts "Install with: brew install --cask #{destination_tap}/#{extracted_token}"
      end

      sig { params(token: String).returns(String) }
      def extracted_cask_token(token)
        return token if args.unversioned? || args.version.nil?

        "#{token}@#{args.version}"
      end

      sig { params(extracted_token: String, bare_token: String, tap: Tap).returns(T.nilable(Pathname)) }
      def find_extracted_cask(extracted_token, bare_token, tap)
        casks_dir = tap.path/"Casks"
        return unless casks_dir.exist?

        shard = bare_token.start_with?("font-") ? "font" : bare_token[0]
        candidates = T.let([
          casks_dir/shard/"#{extracted_token}.rb",
          casks_dir/"#{extracted_token}.rb",
        ], T::Array[Pathname])

        # Also search for versioned variants (token@*.rb) when looking up
        # a bare token (e.g. after brew extract creates token@version).
        if extracted_token == bare_token
          sharded_dir = casks_dir/shard
          candidates.concat(Pathname.glob(sharded_dir/"#{bare_token}@*.rb")) if sharded_dir.exist?
          candidates.concat(Pathname.glob(casks_dir/"#{bare_token}@*.rb"))
        end

        candidates.find(&:exist?)
      end

      sig { params(token: String, destination_tap: Tap, source_tap_name: String).void }
      def fallback_extract(token, destination_tap, source_tap_name)
        ohai "Falling back to manual extraction (brew extract --cask not available)"

        source_tap = Tap.fetch(source_tap_name)
        odie "Source tap #{source_tap_name} is not installed." unless source_tap.installed?

        content = find_cask_in_history(source_tap, token)
        odie "Could not find cask #{token}!" if content.nil?

        version = args.version || parse_version_from_content(content)
        odie "Could not determine version for cask #{token}!" if version.nil?

        versioned_token = args.unversioned? ? token : "#{token}@#{version}"
        content = content.gsub(/^(\s*cask\s+)["']#{Regexp.escape(token)}["']/, "\\1\"#{versioned_token}\"")

        dest_path = destination_cask_path(destination_tap, versioned_token)

        odie "Destination already exists: #{dest_path}\nUse --force to overwrite." if dest_path.exist? && !args.force?

        dest_path.dirname.mkpath
        dest_path.write(content)

        warn_maintainer(token)
        add_quarantine_postflight(dest_path) if args.no_quarantine?

        ohai "Extracted to:", dest_path.to_s
        puts "Install with: brew install --cask #{destination_tap}/#{versioned_token}"
      end

      sig { params(tap: Tap, token: String).returns(T.nilable(String)) }
      def find_cask_in_history(tap, token)
        tap_path = tap.path
        shard = token.start_with?("font-") ? "font" : token[0]

        patterns = [
          "Casks/#{shard}/#{token}.rb",
          "Casks/#{token}.rb",
        ]

        patterns.each do |pattern|
          full_path = tap_path/pattern
          return full_path.read if full_path.exist?

          log_output = Utils.popen_read(
            "git", "-C", tap_path.to_s,
            "log", "--all", "--oneline", "--", pattern
          ).strip
          next if log_output.empty?

          commit = T.must(log_output.lines.first).split.first
          content = Utils.popen_read(
            "git", "-C", tap_path.to_s,
            "show", "#{commit}:#{pattern}"
          )
          return content unless content.empty?
        end

        nil
      end

      sig { params(content: String).returns(T.nilable(String)) }
      def parse_version_from_content(content)
        match = content.match(/^\s*version\s+["']([^"']+)["']/)
        match&.captures&.first
      end

      sig { params(tap: Tap, token: String).returns(Pathname) }
      def destination_cask_path(tap, token)
        casks_dir = tap.path/"Casks"

        if args.no_shard?
          casks_dir/"#{token}.rb"
        elsif token.start_with?("font-")
          casks_dir/"font"/"#{token}.rb"
        else
          casks_dir/token[0]/"#{token}.rb"
        end
      end

      sig { params(token: String).void }
      def warn_maintainer(token)
        opoo <<~EOS
          You are responsible for maintaining #{token}!
          It will not receive updates from Homebrew.
        EOS
      end

      sig { params(cask_path: Pathname).void }
      def add_quarantine_postflight(cask_path)
        content = cask_path.read

        if content.include?("com.apple.quarantine")
          ohai "#{cask_path.basename} already has quarantine handling; skipping."
          return
        end

        app_names = content.scan(/^\s*app\s+["']([^"']+)["']/).flatten

        if app_names.empty?
          opoo "No app stanza found; quarantine removal may need to be configured manually."
          return
        end

        postflight_lines = ["  postflight do"]
        app_names.each do |app|
          postflight_lines << "    system_command \"/usr/bin/xattr\","
          postflight_lines << "                   args: [\"-dr\", \"com.apple.quarantine\", \"\#{appdir}/#{app}\"],"
          postflight_lines << "                   sudo: false"
        end
        postflight_lines << "  end"
        postflight_block = "\n#{postflight_lines.join("\n")}\n"

        modified = content.sub(/(\nend\s*\z)/, "#{postflight_block}\\1")

        if modified == content
          opoo "Could not locate insertion point for postflight block in #{cask_path.basename}."
          return
        end

        cask_path.write(modified)

        opoo <<~EOS
          A postflight block has been added to remove the quarantine attribute.
          This bypasses macOS Gatekeeper. Verify the safety of this software.
        EOS
      end
    end
  end
end
