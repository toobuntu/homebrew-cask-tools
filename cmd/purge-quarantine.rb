# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shellwords"
require "system_command"

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

        named_args min: 1
      end

      BUNDLE_EXTENSIONS = T.let(
        %w[.app .component .colorpicker .saver .webplugin .vst .vst3 .dext .systemextension].freeze,
        T::Array[String],
      )

      LSREGISTER_PATH = T.let(
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/" \
        "LaunchServices.framework/Versions/A/Support/lsregister",
        String,
      )

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
        # Tier 1: bundles staged inside Caskroom version directory. Covers all
        # standard casks (.app, .component, etc.) that unzip directly to Caskroom.
        bundles = cask_dir.glob("*/*").select(&:directory?)
        return bundles unless bundles.empty?

        # Tier 2: live cask definition via the Cask API (CaskLoader). Reads `app`
        # and other Moved artifact targets plus uninstall.delete paths. Works for
        # pkg-based casks (e.g. adobe-acrobat-reader) when the cask is still tapped.
        odebug "No bundles in Caskroom for #{token}; trying cask definition"
        bundles = bundles_from_cask_definition(token)
        return bundles unless bundles.empty?

        # Tier 3: .metadata JSON on disk. Contains the same data as tier 2 but is
        # read directly from the Caskroom filesystem rather than through the Cask API,
        # because the API requires the cask to be present in a tapped repo whereas the
        # .metadata directory persists in the Caskroom even after a cask is removed
        # from all taps.
        odebug "No bundles from cask definition for #{token}; trying cask metadata"
        bundles = bundles_from_cask_metadata(token, cask_dir)
        return bundles unless bundles.empty?

        # Candidate bundle names are used by the lsregister and mdfind tiers.
        candidate_names = candidate_bundle_names(token, cask_dir)

        # Tier 4: macOS Launch Services registry (lsregister). Scans the lsregister
        # dump for `path:` entries whose basename matches a candidate bundle name.
        # Promoted above pkgutil because macOS itself maintains this database and it
        # records the actual installed location regardless of how the app was installed.
        odebug "No bundles from cask metadata for #{token}; trying lsregister"
        bundles = bundles_from_lsregister(candidate_names)
        return bundles unless bundles.empty?

        # Tier 5: pkgutil receipt database. Expands wildcard pkg identifier patterns
        # from .metadata JSON via `pkgutil --pkgs`, then filters the registered file
        # list for bundle extensions and searches common install dirs. Requires the
        # package to be registered with macOS (i.e., the receipt is present).
        odebug "No bundles from lsregister for #{token}; trying pkgutil receipts"
        bundles = bundles_from_pkgutil_receipts(token, cask_dir)
        return bundles unless bundles.empty?

        # Tier 6: pkgutil BOM. Extracts the Bill of Materials from staged .pkg files
        # in the Caskroom using `pkgutil --bom` + `lsbom -s`, identifies top-level
        # bundle names, then searches common install dirs. Does not require the package
        # to be registered with pkgutil, only that the .pkg file is still present.
        odebug "No bundles from pkgutil receipts for #{token}; trying pkgutil BOM"
        bundles = bundles_from_pkgutil_bom(token, cask_dir)
        return bundles unless bundles.empty?

        # Tier 7: Spotlight / mdfind. Searches the Spotlight metadata index by bundle
        # name. A robust last resort that works as long as Spotlight has indexed the
        # install location.
        odebug "No bundles from pkgutil BOM for #{token}; trying mdfind"
        bundles_from_mdfind(candidate_names)
      end

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

      sig { params(cask_dir: Pathname).returns(T::Array[Pathname]) }
      def install_dirs(cask_dir)
        dirs = [Pathname("/Applications"), Pathname(Dir.home)/"Applications"]
        config_path = cask_dir/".metadata"/"config.json"
        if config_path.exist?
          require "json"
          config = JSON.parse(config_path.read)
          appdir = config.dig("explicit", "appdir") ||
                   config.dig("env", "appdir") ||
                   config.dig("default", "appdir")
          dirs.unshift(Pathname(appdir)) if appdir.present?
        end
        dirs.uniq
      rescue => e
        odebug "Could not read install dirs from config.json: #{e.message}"
        [Pathname("/Applications"), Pathname(Dir.home)/"Applications"]
      end

      sig { params(token: String, cask_dir: Pathname).returns(T::Array[String]) }
      def candidate_bundle_names(token, cask_dir)
        require "json"
        json_files = (cask_dir/".metadata").glob("**/Casks/#{token}.json")
        return [] if json_files.empty?

        data = JSON.parse(json_files.max_by(&:mtime).read)
        artifacts = Array(data["artifacts"])
        app_names = artifacts.flat_map { |a| Array(a["app"]) }
        delete_names = artifacts.flat_map { |a| Array(a["uninstall"]) }
                                .flat_map { |u| Array(u["delete"]) }
                                .select { |p| BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) } }
                                .map { |p| File.basename(p) }
        (app_names + delete_names).uniq.reject(&:empty?)
      rescue => e
        odebug "Could not extract candidate bundle names for #{token}: #{e.message}"
        []
      end

      sig { params(token: String, cask_dir: Pathname).returns(T::Array[Pathname]) }
      def bundles_from_cask_metadata(token, cask_dir)
        require "json"

        metadata_dir = cask_dir/".metadata"
        return [] unless metadata_dir.directory?

        json_files = metadata_dir.glob("**/Casks/#{token}.json")
        return [] if json_files.empty?

        data = JSON.parse(json_files.max_by(&:mtime).read)
        artifacts = Array(data["artifacts"])
        dirs = install_dirs(cask_dir)

        app_names = artifacts.flat_map { |a| Array(a["app"]) }
        name_candidates = app_names.flat_map { |name| dirs.map { |dir| dir/name } }

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

      sig { params(token: String, cask_dir: Pathname).returns(T::Array[Pathname]) }
      def bundles_from_pkgutil_bom(token, cask_dir)
        pkg_files = cask_dir.glob("*/**/*.pkg").select(&:file?)
        return [] if pkg_files.empty?

        dirs = install_dirs(cask_dir)
        found = T.let([], T::Array[Pathname])

        pkg_files.each do |pkg_file|
          bom_result = system_command("/usr/sbin/pkgutil",
                                     args:         ["--bom", pkg_file.to_s],
                                     print_stderr: false)
          next unless bom_result.exit_status.zero?

          bom_path = bom_result.stdout.chomp
          next if bom_path.empty?

          lsbom_result = system_command("/usr/bin/lsbom",
                                       args:         ["-s", bom_path],
                                       print_stderr: false)
          next unless lsbom_result.exit_status.zero?

          names = lsbom_result.stdout.lines
                              .map { |l| l.chomp.delete_prefix("./") }
                              .reject { |p| p.include?("/") }
                              .select { |p| BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) } }
                              .uniq
          next if names.empty?

          odebug "BOM bundles in #{pkg_file.basename}: #{names.join(", ")}"
          names.each do |name|
            dirs.each do |dir|
              candidate = dir/name
              found << candidate if candidate.directory?
            end
          end
        end

        found.uniq
      rescue => e
        odebug "pkgutil BOM lookup failed for #{token}: #{e.message}"
        []
      end

      sig { params(token: String, cask_dir: Pathname).returns(T::Array[Pathname]) }
      def bundles_from_pkgutil_receipts(token, cask_dir)
        require "json"

        metadata_dir = cask_dir/".metadata"
        return [] unless metadata_dir.directory?

        json_files = metadata_dir.glob("**/Casks/#{token}.json")
        return [] if json_files.empty?

        data = JSON.parse(json_files.max_by(&:mtime).read)
        pkg_patterns = Array(data["artifacts"])
                       .flat_map { |a| Array(a["uninstall"]) }
                       .flat_map { |u| Array(u["pkgutil"]) }
        return [] if pkg_patterns.empty?

        found = T.let([], T::Array[Pathname])

        dirs = install_dirs(cask_dir)

        pkg_patterns.each do |pattern|
          pkg_ids = system_command("/usr/sbin/pkgutil",
                                   args:         ["--pkgs=#{pattern}"],
                                   print_stderr: false)
          next unless pkg_ids.exit_status.zero?

          pkg_ids.stdout.lines.map(&:chomp).reject(&:empty?).each do |pkg_id|
            files = system_command("/usr/sbin/pkgutil",
                                   args:         ["--files", pkg_id],
                                   print_stderr: false)
            next unless files.exit_status.zero?

            # The receipt records where files were staged during installation, not
            # where postinstall scripts ultimately placed them.  Extract bundle names
            # from the file list and search install_dirs instead of using the prefix.
            bundle_names = files.stdout.lines
                                .map(&:chomp)
                                .reject(&:empty?)
                                .filter_map do |rel|
                                  rel.split("/").find do |p|
                                    BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) }
                                  end
                                end
                                .uniq

            bundle_names.each do |name|
              dirs.each do |dir|
                candidate = dir/name
                found << candidate if candidate.directory?
              end
            end
          end
        end

        found.uniq
      rescue => e
        odebug "pkgutil receipts lookup failed for #{token}: #{e.message}"
        []
      end

      sig { params(candidate_names: T::Array[String]).returns(T::Array[Pathname]) }
      def bundles_from_lsregister(candidate_names)
        return [] if candidate_names.empty?

        result = system_command(LSREGISTER_PATH,
                                args:         ["-dump"],
                                print_stderr: false)
        return [] unless result.exit_status.zero?

        found = T.let([], T::Array[Pathname])

        result.stdout.lines.each do |line|
          next unless (m = line.match(/^\s*path:\s+(.+)$/))

          path = Pathname(m[1].strip)
          next unless path.directory?
          next unless BUNDLE_EXTENSIONS.any? { |ext| path.basename.to_s.downcase.end_with?(ext) }
          next unless candidate_names.any? { |name| name.casecmp(path.basename.to_s).zero? }

          found << path
        end

        found.uniq
      rescue => e
        odebug "lsregister lookup failed: #{e.message}"
        []
      end

      sig { params(candidate_names: T::Array[String]).returns(T::Array[Pathname]) }
      def bundles_from_mdfind(candidate_names)
        return [] if candidate_names.empty?

        found = T.let([], T::Array[Pathname])

        candidate_names.each do |name|
          result = system_command("/usr/bin/mdfind",
                                  args:         ["-name", name],
                                  print_stderr: false)
          next unless result.exit_status.zero?

          result.stdout.lines.map(&:chomp).reject(&:empty?).each do |path_str|
            p = Pathname(path_str)
            next unless p.directory?
            next unless p.basename.to_s.casecmp(name).zero?
            next unless BUNDLE_EXTENSIONS.any? { |ext| p.basename.to_s.downcase.end_with?(ext) }

            found << p
          end
        end

        found.uniq
      rescue => e
        odebug "mdfind lookup failed: #{e.message}"
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
