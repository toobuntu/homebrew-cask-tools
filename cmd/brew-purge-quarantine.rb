# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "system_command"

module Homebrew
  module Cmd
    class PurgeQuarantine < AbstractCommand
      include SystemCommand::Mixin
      cmd_args do
        usage_banner "`brew purge-quarantine` <cask> [<cask> ...]"
        description <<~EOS
          Disables macOS's Gatekeeper for the named casks by removing the
          `com.apple.quarantine` and `com.apple.provenance` extended attributes
          from their installed `.app` bundles.
        EOS

        named_args min: 1
      end

      sig { override.void }
      def run
        args.named.each do |token|
          purge_quarantine_for_cask(token)
        end
      end

      private

      sig { params(token: String).void }
      def purge_quarantine_for_cask(token)
        cask_dir = Pathname.new(HOMEBREW_CASKROOM)/token
        unless cask_dir.directory?
          ofail "#{token} is not a Homebrew-installed cask (not found in #{HOMEBREW_CASKROOM})"
          return
        end

        app_bundles = Pathname.glob("#{cask_dir}/*/*.app")

        if app_bundles.empty?
          opoo "No .app bundles found for #{token}"
          return
        end

        gatekeeper_disabled = false

        app_bundles.each do |app_path|
          resolved_path = begin
            app_path.realpath
          rescue Errno::ENOENT => e
            odebug "Could not resolve symlink for #{app_path}: #{e.message}"
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

          ohai "Removing quarantine from: #{resolved_path}"

          attrs_present.each do |attr|
            removed = remove_xattr(token, resolved_path, attr)
            gatekeeper_disabled = true if removed
            verify_xattr_removed(resolved_path, attr) if removed
          end
        end

        opoo "macOS's Gatekeeper has been disabled for #{token}" if gatekeeper_disabled
      end

      # Returns an array of the quarantine-related xattrs currently present on +path+.
      sig { params(path: Pathname).returns(T::Array[String]) }
      def xattrs_present(path)
        result = system_command "/usr/bin/xattr",
                                args:         ["-l", path.to_s],
                                print_stderr: false
        [
          "com.apple.quarantine",
          "com.apple.provenance",
        ].select { |attr| result.stdout.include?(attr) }
      end

      # Removes +attr+ from +path+ recursively. Returns true on success.
      # xattrs_present checks only the bundle root via -l; sub-files inside the
      # bundle may still carry the attr, so a "No such" fallback is kept here.
      sig { params(token: String, path: Pathname, attr: String).returns(T::Boolean) }
      def remove_xattr(token, path, attr)
        result = system_command "/usr/bin/xattr",
                                args:         ["-d", "-r", attr, path.to_s],
                                print_stderr: false

        return true if result.exit_status.zero?

        if result.stderr.include?("No such")
          odebug "#{attr} not present on #{path.basename}"
          false
        else
          ofail "Failed to remove #{attr} from #{path}.\n" \
                "Try running with sudo: sudo brew purge-quarantine #{token}"
          false
        end
      end

      sig { params(path: Pathname, attr: String).void }
      def verify_xattr_removed(path, attr)
        if xattrs_present(path).include?(attr)
          ofail "#{attr} still present on #{path.basename} after removal attempt"
        else
          odebug "#{attr} successfully removed from #{path.basename}"
        end
      end
    end
  end
end
