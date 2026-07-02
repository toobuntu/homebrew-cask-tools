# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cask/caskroom"
require "shellwords"
require "system_command"
require_relative "../lib/cask_tools/bundle_discovery"

module Homebrew
  module Cmd
    # Removes macOS quarantine and provenance xattrs from installed cask bundles.
    class PurgeQuarantine < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        usage_banner "`purge-quarantine` <cask> [<cask> ...]"
        description <<~EOS
          Disables macOS's Gatekeeper for the named casks by removing the
          `com.apple.quarantine` and `com.apple.provenance` extended attributes
          from their installed macOS bundles (`.app`, `.component`, `.colorPicker`,
          `.saver`, `.webplugin`, and other artifact types).
        EOS

        named_args :installed_cask, min: 1
      end

      sig { override.void }
      def run
        raise UsageError, "`brew purge-quarantine` is only supported on macOS." unless OS.mac?

        args.named.each do |token|
          purge_quarantine_for_cask(token)
        end
      end

      private

      sig { params(token: String).void }
      def purge_quarantine_for_cask(token)
        oh1 "Processing: #{token}" unless args.quiet?

        cask_dir = Cask::Caskroom.path/token
        unless cask_dir.directory?
          ofail "#{token} is not a Homebrew-installed cask (not found in #{Cask::Caskroom.path})"
          return
        end

        bundles = CaskTools::BundleDiscovery.new(token, cask_dir).bundles

        if bundles.empty?
          unless args.quiet?
            opoo <<~EOS
              No quarantinable bundles found for #{token}.
              If this cask was removed from all taps, try re-running with --verbose to see which discovery tiers were attempted.
            EOS
          end
          return
        end

        gatekeeper_disabled = false
        any_failure = false
        attrs_found = false

        bundles.each do |bundle_path|
          resolved_path = begin
            bundle_path.realpath
          rescue Errno::ENOENT => e
            odebug "Could not resolve symlink for #{bundle_path}: #{e.message}"
            next
          end

          info_plist = resolved_path/"Contents"/"Info.plist"
          unless info_plist.exist?
            odebug "Skipping #{resolved_path.basename}: no Contents/Info.plist found"
            next
          end

          attrs_present = xattrs_present(resolved_path)

          if attrs_present.empty?
            odebug "No quarantine attributes present on #{resolved_path.basename}"
            next
          end

          odebug "Found on #{resolved_path.basename}: #{attrs_present.join(", ")}"

          attrs_found = true
          ohai "Removing quarantine from: #{resolved_path}" unless args.quiet?

          attrs_present.each do |attr|
            deleted = xattr_deleted?(resolved_path, attr)
            if deleted
              gatekeeper_disabled = true
              verify_xattr_removed(resolved_path, attr)
            else
              any_failure = true
            end
          end
        end

        if gatekeeper_disabled && any_failure
          opoo "Gatekeeper partially disabled for #{token}: some attributes could not be removed" unless args.quiet?
        elsif gatekeeper_disabled
          ohai "macOS's Gatekeeper has been disabled for #{token}" unless args.quiet?
        elsif !attrs_found
          ohai "No quarantine attributes found for #{token}" unless args.quiet?
        end
      end

      sig { params(path: Pathname).returns(T::Array[String]) }
      def xattrs_present(path)
        result = system_command "/usr/bin/xattr",
                                args:         ["-l", "-r", path.to_s],
                                print_stderr: false

        unless result.exit_status.zero?
          opoo "Could not list xattrs on #{path.basename}: #{result.stderr.chomp}"
          return []
        end

        [
          "com.apple.quarantine",
          "com.apple.provenance",
        ].select { |attr| result.stdout.include?(attr) }
      end

      sig { params(path: Pathname, attr: String).returns(T::Boolean) }
      def xattr_deleted?(path, attr)
        result = system_command "/usr/bin/xattr",
                                args:         ["-d", "-r", attr, path.to_s],
                                print_stderr: false

        return true if result.exit_status.zero?

        if result.stderr.include?("No such")
          odebug "#{attr} not present on #{path.basename}"
        else
          ofail <<~EOS
            Failed to remove #{attr} from #{path}.
            To remove manually, run:
              /usr/bin/xattr -d -r #{Shellwords.shellescape(attr)} #{Shellwords.shellescape(path.to_s)}
            Or try it with sudo.
          EOS
        end
        false
      end

      sig { params(path: Pathname, attr: String).void }
      def verify_xattr_removed(path, attr)
        if xattrs_present(path).include?(attr)
          ofail "#{attr} still present inside #{path.basename} after removal attempt"
        else
          odebug "#{attr} successfully removed from #{path.basename}"
        end
      end
    end
  end
end
