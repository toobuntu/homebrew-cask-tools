# frozen_string_literal: true

#: * `brew purge-quarantine` <cask> [<cask> ...]
#:
#:   Remove macOS quarantine and provenance extended attributes from installed
#:   cask app bundles. Useful for apps that were downloaded with Gatekeeper
#:   quarantine flags that you have already verified as safe.

require "abstract_command"

module Homebrew
  module Cmd
    class PurgeQuarantine < ::Homebrew::AbstractCommand
      cmd_args do
        description <<~EOS
          Remove macOS quarantine and provenance extended attributes from installed
          cask app bundles. Useful for apps that were downloaded with Gatekeeper
          quarantine flags that you have already verified as safe.
        EOS

        named_args :cask, min: 1
      end

      def run
        args.named.each do |token|
          purge_quarantine_for_cask(token)
        end
      end

      private

      def purge_quarantine_for_cask(token)
        oh1 "Processing cask: #{token}"

        cask_dir = Pathname.new(HOMEBREW_CASKROOM)/token
        odie "Cask #{token} is not installed" unless cask_dir.directory?

        app_bundles = Pathname.glob("#{cask_dir}/*/*.app")

        if app_bundles.empty?
          opoo "No .app bundles found for #{token}"
          return
        end

        app_bundles.each do |app_path|
          begin
            resolved_path = app_path.realpath
          rescue Errno::ENOENT => e
            odebug "Could not resolve symlink for #{app_path}: #{e.message}"
            next
          end

          info_plist = resolved_path/"Contents"/"Info.plist"
          unless info_plist.exist?
            odebug "Skipping #{resolved_path.basename}: no Contents/Info.plist found"
            next
          end

          ohai "Removing quarantine from: #{resolved_path}"

          remove_xattr(token, resolved_path, "com.apple.quarantine")
          remove_xattr(token, resolved_path, "com.apple.provenance")

          verify_xattr_removed(resolved_path, "com.apple.quarantine")
          verify_xattr_removed(resolved_path, "com.apple.provenance")
        end
      end

      def remove_xattr(token, path, attr)
        result = system_command "/usr/bin/xattr",
                                args:         ["-d", "-r", attr, path.to_s],
                                print_stderr: false

        return if result.exit_status.zero?

        if result.stderr.include?("No such attr")
          opoo "#{attr} not present on #{path.basename}"
        else
          ofail "Failed to remove #{attr} from #{path}.\n" \
                "Try running with sudo: sudo brew purge-quarantine #{token}"
        end
      end

      def verify_xattr_removed(path, attr)
        result = system_command "/usr/bin/xattr",
                                args:         ["-l", path.to_s],
                                print_stderr: false

        if result.stdout.include?(attr)
          odebug "#{attr} still present on #{path} after removal attempt"
        else
          odebug "#{attr} successfully removed from #{path}"
        end
      end
    end
  end
end
