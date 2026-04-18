# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "prism"
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

      # Stanza names that follow postflight in Homebrew's canonical order.
      STANZAS_AFTER_POSTFLIGHT = T.let([
        :uninstall_preflight, :uninstall_postflight, :uninstall, :zap, :caveats
      ].freeze, T::Array[Symbol])

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
          next if commit.blank?

          content = Utils.popen_read(
            "git", "-C", tap_path.to_s,
            "show", "#{commit}:#{pattern}"
          )
          next if content.empty?

          odebug "Found #{token} at #{commit}:#{pattern} (#{content.length} bytes)"
          return content
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

        parsed = Prism.parse(content)
        cask_block = find_cask_block(parsed.value)

        unless cask_block
          if parsed.errors.empty?
            opoo "Could not find a `cask` block in #{cask_path.basename}."
          else
            opoo "Could not parse cask block in #{cask_path.basename}."
          end
          return
        end

        unless parsed.errors.empty?
          opoo "Parse errors in #{cask_path.basename}; postflight may be incorrectly placed. Verify the result."
        end

        stmts = cask_block_stmts(cask_block)
        app_names = extract_app_names(stmts)

        if app_names.empty?
          opoo "No app stanza found; quarantine removal may need to be configured manually."
          return
        end

        xattr_lines = build_xattr_lines(app_names)

        existing_pf = stmts.find do |n|
          n.is_a?(Prism::CallNode) && n.name == :postflight && n.block.is_a?(Prism::BlockNode)
        end

        modified = if existing_pf
          pf_block = T.cast(T.cast(existing_pf, Prism::CallNode).block, Prism::BlockNode)
          append_to_postflight(content, pf_block, xattr_lines)
        else
          insert_new_postflight(content, stmts, cask_block, xattr_lines)
        end

        cask_path.write(modified)

        opoo <<~EOS
          A postflight block has been added to remove the quarantine attribute.
          This bypasses macOS Gatekeeper. Verify the safety of this software.
        EOS
      end

      sig { params(program: Prism::ProgramNode).returns(T.nilable(Prism::BlockNode)) }
      def find_cask_block(program)
        program.statements.body.each do |node|
          next if !node.is_a?(Prism::CallNode) || node.name != :cask

          block = node.block
          return block if block.is_a?(Prism::BlockNode)
        end
        nil
      end

      sig { params(cask_block: Prism::BlockNode).returns(T::Array[Prism::Node]) }
      def cask_block_stmts(cask_block)
        body = cask_block.body
        return [] unless body.is_a?(Prism::StatementsNode)

        body.body
      end

      sig { params(stmts: T::Array[Prism::Node]).returns(T::Array[String]) }
      def extract_app_names(stmts)
        stmts.flat_map { |node| extract_app_names_from_node(node) }
      end

      sig { params(node: Prism::Node).returns(T::Array[String]) }
      def extract_app_names_from_node(node)
        app_names = T.let([], T::Array[String])

        if node.is_a?(Prism::CallNode) && node.name == :app
          first_arg = node.arguments&.arguments&.first
          app_names << first_arg.content if first_arg.is_a?(Prism::StringNode)
        end

        node.compact_child_nodes.each do |child|
          app_names.concat(extract_app_names_from_node(child))
        end

        app_names
      end

      sig { params(app_names: T::Array[String]).returns(String) }
      def build_xattr_lines(app_names)
        app_names.map do |app|
          <<~RUBY.chomp
            system_command "/usr/bin/xattr",
                           args: ["-dr", "com.apple.quarantine", "\#{appdir}/#{app}"],
                           sudo: false
          RUBY
        end.join("\n    ")
      end

      sig { params(content: String, pf_block: Prism::BlockNode, xattr_lines: String).returns(String) }
      def append_to_postflight(content, pf_block, xattr_lines)
        closing_offset = pf_block.closing_loc.start_offset
        line_start = line_start_offset(content, closing_offset)
        prefix = content[line_start...closing_offset]

        if T.must(prefix).strip.empty?
          content.dup.insert(line_start, "    #{xattr_lines}\n")
        else
          content.dup.insert(closing_offset, "\n    #{xattr_lines}\n  ")
        end
      end

      sig {
        params(
          content:     String,
          stmts:       T::Array[Prism::Node],
          cask_block:  Prism::BlockNode,
          xattr_lines: String,
        ).returns(String)
      }
      def insert_new_postflight(content, stmts, cask_block, xattr_lines)
        # Insert before the first stanza that canonically follows postflight,
        # or before the cask block's closing `end` if no such stanza exists.
        anchor = stmts.find do |n|
          n.is_a?(Prism::CallNode) && STANZAS_AFTER_POSTFLIGHT.include?(n.name)
        end

        offset = if anchor
          anchor.location.start_offset
        else
          cask_block.closing_loc.start_offset
        end

        insert_pos = line_start_offset(content, offset)
        content.dup.insert(insert_pos, "  postflight do\n    #{xattr_lines}\n  end\n")
      end

      sig { params(content: String, offset: Integer).returns(Integer) }
      def line_start_offset(content, offset)
        newline = content.rindex("\n", offset - 1)
        newline ? newline + 1 : offset
      end
    end
  end
end
