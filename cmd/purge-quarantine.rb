# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "system_command"

module Homebrew
  module Cmd
    class PurgeQuarantine < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        usage_banner "`purge-quarantine` <cask> [<cask> ...]"
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
        oh1 "Processing: #{token}" unless args.quiet?

        cask_dir = HOMEBREW_CASKROOM/token
        unless cask_dir.directory?
          ofail "#{token} is not a Homebrew-installed cask (not found in #{HOMEBREW_CASKROOM})"
          return
        end

        app_bundles = cask_dir.glob("*/*.app")

        if app_bundles.empty?
          opoo "No .app bundles found for #{token}" unless args.quiet?
          return
        end

        gatekeeper_disabled = false
        attrs_found = false

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

          attrs_found = true
          ohai "Removing quarantine from: #{resolved_path}" unless args.quiet?

          attrs_present.each do |attr|
            deleted = xattr_deleted?(resolved_path, attr)
            gatekeeper_disabled = true if deleted
            verify_xattr_removed(resolved_path, attr) if deleted
          end
        end

        if gatekeeper_disabled
          opoo "macOS's Gatekeeper has been disabled for #{token}" unless args.quiet?
        elsif !attrs_found
          # Already clean — exit 0 is correct (idempotent command), but surface a
          # visible message so the user knows the command ran and found nothing to do.
          ohai "No quarantine attributes found for #{token}" unless args.quiet?
        end
        # If attrs_found but !gatekeeper_disabled, xattr_deleted? already printed ofail.
      end

      # Returns the quarantine-related xattrs present anywhere inside the bundle
      # (recursive via -l -r). Used both as a pre-check before removal and by
      # verify_xattr_removed after deletion. Returns [] and warns on listing
      # failure so the caller can decide what to do.
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

      # Removes +attr+ from +path+ recursively. Returns true if the attribute
      # was successfully deleted (exit 0). On failure, distinguishes between
      # "attribute absent" (odebug) and a permission error (ofail with sudo hint).
      sig { params(path: Pathname, attr: String).returns(T::Boolean) }
      def xattr_deleted?(path, attr)
        result = system_command "/usr/bin/xattr",
                                args:         ["-d", "-r", attr, path.to_s],
                                print_stderr: false

        return true if result.exit_status.zero?

        if result.stderr.include?("No such")
          odebug "#{attr} not present on #{path.basename}"
        else
          ofail "Failed to remove #{attr} from #{path}.\n" \
                "To remove manually, run:\n  " \
                "sudo /usr/bin/xattr -d -r '#{attr}' '#{path}'"
        end
        false
      end

      # Verifies recursively that +attr+ is absent from all files inside the
      # bundle by reusing xattrs_present (which uses xattr -l -r).
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
