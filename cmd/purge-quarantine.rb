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
          from their installed macOS bundles (`.app`, `.component`, `.colorPicker`,
          `.saver`, `.webplugin`, and other artifact types).
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

        bundles = quarantinable_bundles_for(token, cask_dir)

        if bundles.empty?
          opoo "No quarantinable bundles found for #{token}" unless args.quiet?
          return
        end

        gatekeeper_disabled = false
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
            gatekeeper_disabled = true if deleted
            verify_xattr_removed(resolved_path, attr) if deleted
          end
        end

        if gatekeeper_disabled
          opoo "macOS's Gatekeeper has been disabled for #{token}" unless args.quiet?
        elsif !attrs_found
          ohai "No quarantine attributes found for #{token}" unless args.quiet?
        end
      end

      sig { params(token: String, cask_dir: Pathname).returns(T::Array[Pathname]) }
      def quarantinable_bundles_for(token, cask_dir)
        bundles = cask_dir.glob("*/*").select(&:directory?)
        return bundles unless bundles.empty?

        odebug "No bundles in Caskroom for #{token}; trying cask definition"
        bundles = bundles_from_cask_definition(token)
        return bundles unless bundles.empty?

        odebug "No bundles from cask definition for #{token}; trying cask metadata"
        bundles_from_cask_metadata(token, cask_dir)
      end

      BUNDLE_EXTENSIONS = T.let(
        %w[.app .component .colorpicker .saver .webplugin .vst .vst3 .dext .systemextension].freeze,
        T::Array[String],
      )

      sig { params(token: String).returns(T::Array[Pathname]) }
      def bundles_from_cask_definition(token)
        require "cask/cask_loader"
        require "cask/artifact/moved"
        require "cask/artifact/uninstall"
        cask = T.unsafe(Cask::CaskLoader).load(token)
        artifacts = T.unsafe(cask).artifacts

        moved = artifacts
                .select { |a| T.unsafe(a).is_a?(Cask::Artifact::Moved) }
                .map { |a| Pathname(T.unsafe(a).target.to_s) }

        uninstall_delete = artifacts
                           .select { |a| T.unsafe(a).is_a?(Cask::Artifact::Uninstall) }
                           .flat_map { |a| Array(T.unsafe(a).directives[:delete]) }
                           .select { |p| BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) } }
                           .map { |p| Pathname(p) }

        (moved + uninstall_delete).uniq.select(&:directory?)
      rescue => e
        odebug "Could not load cask definition for #{token}: #{e.message}"
        []
      end

      sig { params(token: String, cask_dir: Pathname).returns(T::Array[Pathname]) }
      def bundles_from_cask_metadata(token, cask_dir)
        require "json"

        metadata_dir = cask_dir/".metadata"
        return [] unless metadata_dir.directory?

        config_path = metadata_dir/"config.json"
        appdir = if config_path.exist?
          config = JSON.parse(config_path.read)
          config.dig("explicit", "appdir") ||
            config.dig("env", "appdir") ||
            config.dig("default", "appdir") ||
            "/Applications"
        else
          "/Applications"
        end

        json_files = metadata_dir.glob("*/**/Casks/#{token}.json")
        return [] if json_files.empty?

        data = JSON.parse(json_files.max_by(&:mtime).read)
        artifacts = Array(data["artifacts"])

        # Relative names from `app` stanzas — install to appdir
        app_names = artifacts.flat_map { |a| Array(a["app"]) }
        name_candidates = app_names.flat_map do |name|
          [Pathname(appdir)/name, Pathname("/Applications")/name, Dir.home/"Applications"/name]
        end

        # Absolute paths from `uninstall.delete` entries (covers pkg-only casks)
        uninstall_candidates = artifacts.flat_map { |a| Array(a["uninstall"]) }
                                        .flat_map { |u| Array(u["delete"]) }
                                        .select { |p| BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) } }
                                        .map { |p| Pathname(p) }

        candidates = (name_candidates + uninstall_candidates).uniq
        odebug "Metadata candidates for #{token}: #{candidates.map(&:to_s).join(", ")}"
        candidates.select(&:directory?)
      rescue => e
        odebug "Could not read cask metadata for #{token}: #{e.message}"
        []
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
              /usr/bin/xattr -d -r '#{attr}' '#{path}'
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
