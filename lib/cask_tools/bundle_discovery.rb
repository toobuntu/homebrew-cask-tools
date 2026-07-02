# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: strict
# frozen_string_literal: true

require "context"
require "system_command"
require "utils/output"

module Homebrew
  # Namespace for shared helpers provided by the toobuntu/cask-tools tap.
  #
  # Deliberately NOT `Homebrew::Cask`: defining that constant would shadow the
  # top-level `::Cask` module for all brew code written inside `module Homebrew`
  # (Ruby resolves bare `Cask::...` references lexically before falling back to
  # `Object`), breaking Homebrew internals at runtime.
  module CaskTools
    # Locates the installed macOS bundles (`.app`, `.component`, `.saver`, ...)
    # belonging to an installed cask, via a seven-tier search that keeps working
    # even after a cask has been removed from all taps. Extracted from
    # `cmd/purge-quarantine.rb` so other consumers (e.g. the babble external
    # command) can reuse the discovery without the quarantine removal.
    #
    # Verbose tier-transition messages honor `--verbose` via `Context`; per-tier
    # diagnostics honor `--debug` via `odebug`.
    class BundleDiscovery
      include Context
      include SystemCommand::Mixin
      include Utils::Output::Mixin

      extend SystemCommand::Mixin
      extend Utils::Output::Mixin

      BUNDLE_EXTENSIONS = T.let(
        %w[.app .component .colorpicker .saver .webplugin .vst .vst3 .dext .systemextension].freeze,
        T::Array[String],
      )

      LSREGISTER_PATH = T.let(
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/" \
        "LaunchServices.framework/Versions/A/Support/lsregister",
        String,
      )

      LSREGISTER_CACHE_TTL = T.let(300, Integer)

      sig { params(token: String, cask_dir: Pathname).void }
      def initialize(token, cask_dir)
        @token = T.let(token, String)
        @cask_dir = T.let(cask_dir, Pathname)
        @candidate_names = T.let(nil, T.nilable(T::Array[String]))
      end

      # Cached `lsregister -dump` output, shared across instances and consumers
      # through an on-disk cache with a 5-minute TTL.
      sig { returns(T.nilable(String)) }
      def self.lsregister_dump
        cache_path = HOMEBREW_CACHE/"purge-quarantine"/"lsregister.dump"
        if cache_path.exist? && (Time.now - cache_path.mtime) < LSREGISTER_CACHE_TTL
          age_s = (Time.now - cache_path.mtime).round
          odebug "Tier 4: using cached lsregister dump (#{age_s}s old, TTL #{LSREGISTER_CACHE_TTL}s)"
          return cache_path.read
        end

        odebug "Tier 4: running lsregister -dump (may take ~20s); result will be cached for #{LSREGISTER_CACHE_TTL}s"
        result = system_command(LSREGISTER_PATH, args: ["-dump"], print_stderr: false)
        return unless result.exit_status.zero?

        cache_path.dirname.mkpath
        cache_path.write(result.stdout)
        result.stdout
      rescue => e
        odebug "Tier 4: lsregister dump failed: #{e.message}"
        nil
      end

      sig { returns(T::Array[Pathname]) }
      def bundles
        # Tier 1: bundles staged inside Caskroom version directory. Covers all
        # standard casks (.app, .component, etc.) that unzip directly to Caskroom.
        # Filter by Contents/Info.plist to exclude non-bundle dirs (.metadata, etc.)
        # that would otherwise short-circuit the fallback tiers for pkg-based casks.
        bundles = cask_dir.glob("*/*").select do |d|
          d.directory? && (d/"Contents"/"Info.plist").exist?
        end
        tier1_names = bundles.map { |b| b.basename.to_s }.then { |ns| ns.empty? ? "(none)" : ns.join(", ") }
        odebug "Tier 1 Caskroom bundles for #{token}: #{tier1_names}"
        return bundles unless bundles.empty?

        # Tier 2: live cask definition via the Cask API (CaskLoader). Reads `app`
        # and other Moved artifact targets plus uninstall.delete paths. Works for
        # pkg-based casks (e.g. adobe-acrobat-reader) when the cask is still tapped.
        ohai "Tier 1→Tier 2: no Caskroom bundles for #{token}; trying cask definition" if verbose?
        bundles = bundles_from_cask_definition
        return bundles unless bundles.empty?

        # Tier 3: .metadata JSON on disk. Contains the same data as tier 2 but is
        # read directly from the Caskroom filesystem rather than through the Cask API,
        # because the API requires the cask to be present in a tapped repo whereas the
        # .metadata directory persists in the Caskroom even after a cask is removed
        # from all taps.
        ohai "Tier 2→Tier 3: no bundles from cask definition for #{token}; trying cask metadata" if verbose?
        bundles = bundles_from_cask_metadata
        return bundles unless bundles.empty?

        # Tier 4: macOS Launch Services registry (lsregister). Scans the lsregister
        # dump for `path:` entries whose basename matches a candidate bundle name.
        # Promoted above pkgutil because macOS itself maintains this database and it
        # records the actual installed location regardless of how the app was installed.
        # Candidate bundle names (from metadata app/delete/pkgutil) are used by the
        # lsregister and mdfind tiers.
        ohai "Tier 3→Tier 4: no bundles from cask metadata for #{token}; trying lsregister" if verbose?
        bundles = bundles_from_lsregister(candidate_names)
        return bundles unless bundles.empty?

        # Tier 5: pkgutil receipt database. Expands wildcard pkg identifier patterns
        # from .metadata JSON via `pkgutil --pkgs`, then filters the registered file
        # list for bundle extensions and searches common install dirs. Requires the
        # package to be registered with macOS (i.e., the receipt is present).
        ohai "Tier 4→Tier 5: no bundles from lsregister for #{token}; trying pkgutil receipts" if verbose?
        bundles = bundles_from_pkgutil_receipts
        return bundles unless bundles.empty?

        # Tier 6: pkgutil BOM. Extracts the Bill of Materials from staged .pkg files
        # in the Caskroom using `pkgutil --bom` + `lsbom -s`, identifies top-level
        # bundle names, then searches common install dirs. Does not require the package
        # to be registered with pkgutil, only that the .pkg file is still present.
        ohai "Tier 5→Tier 6: no bundles from pkgutil receipts for #{token}; trying pkgutil BOM" if verbose?
        bundles = bundles_from_pkgutil_bom
        return bundles unless bundles.empty?

        # Tier 7: Spotlight / mdfind. Searches the Spotlight metadata index by bundle
        # name. A robust last resort that works as long as Spotlight has indexed the
        # install location.
        ohai "Tier 6→Tier 7: no bundles from pkgutil BOM for #{token}; trying mdfind" if verbose?
        bundles_from_mdfind(candidate_names)
      end

      sig { returns(T::Array[String]) }
      def candidate_names
        @candidate_names ||= begin
          require "json"
          json_files = (cask_dir/".metadata").glob("**/Casks/#{token}.json")
          if json_files.empty?
            []
          else
            data = JSON.parse(json_files.max_by(&:mtime).read)
            artifacts = Array(data["artifacts"])
            app_names = artifacts.flat_map { |a| Array(a["app"]) }
            delete_names = artifacts.flat_map { |a| Array(a["uninstall"]) }
                                    .flat_map { |u| Array(u["delete"]) }
                                    .select { |p| BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) } }
                                    .map { |p| File.basename(p) }

            # For pkg-based casks (no app stanza), extract bundle names from pkgutil receipts
            # so that lsregister/mdfind can find bundles installed outside the Caskroom.
            pkg_patterns = artifacts.flat_map { |a| Array(a["uninstall"]) }
                                    .flat_map { |u| Array(u["pkgutil"]) }
            pkgutil_names = pkg_patterns.flat_map do |pattern|
              ids = system_command("/usr/sbin/pkgutil", args: ["--pkgs=#{pattern}"], print_stderr: false)
              next [] unless ids.exit_status.zero?

              ids.stdout.lines.map(&:chomp).reject(&:empty?).flat_map do |pkg_id|
                files = system_command("/usr/sbin/pkgutil", args: ["--files", pkg_id], print_stderr: false)
                next [] unless files.exit_status.zero?

                files.stdout.lines.map(&:chomp).reject(&:empty?)
                     .filter_map do |rel|
                       rel.split("/").find do |p|
                         BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) }
                       end
                     end
              end
            end

            (app_names + delete_names + pkgutil_names).uniq.reject(&:empty?)
          end
        rescue => e
          odebug "Could not extract candidate bundle names for #{token}: #{e.message}"
          []
        end
      end

      private

      sig { returns(String) }
      attr_reader :token

      sig { returns(Pathname) }
      attr_reader :cask_dir

      sig { returns(T::Array[Pathname]) }
      def bundles_from_cask_definition
        require "cask/cask_loader"
        require "cask/artifact/moved"
        require "cask/artifact/uninstall"
        cask = T.unsafe(Cask::CaskLoader).load(token)
        artifacts = T.unsafe(cask).artifacts

        moved = artifacts
                .select { |a| T.unsafe(a).is_a?(Cask::Artifact::Moved) }
                .map { |a| Pathname(T.unsafe(a).target.to_s) }
        odebug "Tier 2: Cask definition Moved targets for #{token}: #{moved.join(", ").then do |s|
          s.empty? ? "(none)" : s
        end}"

        uninstall_delete = artifacts
                           .select { |a| T.unsafe(a).is_a?(Cask::Artifact::Uninstall) }
                           .flat_map { |a| Array(T.unsafe(a).directives[:delete]) }
                           .select { |p| BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) } }
                           .map { |p| Pathname(p) }
        uninstall_delete_debug = uninstall_delete.join(", ").then do |s|
          s.empty? ? "(none)" : s
        end
        odebug "Tier 2: Cask definition uninstall.delete bundles for #{token}: #{uninstall_delete_debug}"

        (moved + uninstall_delete).uniq.select(&:directory?)
      rescue => e
        odebug "Could not load cask definition for #{token}: #{e.message}"
        []
      end

      sig { returns(T::Array[Pathname]) }
      def install_dirs
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

      sig { returns(T::Array[Pathname]) }
      def bundles_from_cask_metadata
        require "json"

        metadata_dir = cask_dir/".metadata"
        return [] unless metadata_dir.directory?

        json_files = metadata_dir.glob("**/Casks/#{token}.json")
        return [] if json_files.empty?

        data = JSON.parse(json_files.max_by(&:mtime).read)
        artifacts = Array(data["artifacts"])
        dirs = install_dirs

        app_names = artifacts.flat_map { |a| Array(a["app"]) }
        name_candidates = app_names.flat_map { |name| dirs.map { |dir| dir/name } }

        uninstall_candidates = artifacts.flat_map { |a| Array(a["uninstall"]) }
                                        .flat_map { |u| Array(u["delete"]) }
                                        .select { |p| BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) } }
                                        .map { |p| Pathname(p) }

        candidates = (name_candidates + uninstall_candidates).uniq
        odebug "Tier 3: Metadata candidates for #{token}: #{candidates.empty? ? "(none)" : candidates.join(", ")}"
        candidates.select(&:directory?)
      rescue => e
        odebug "Could not read cask metadata for #{token}: #{e.message}"
        []
      end

      sig { returns(T::Array[Pathname]) }
      def bundles_from_pkgutil_bom
        pkg_files = cask_dir.glob("*/**/*.pkg").select(&:file?)
        return [] if pkg_files.empty?

        dirs = install_dirs
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

          odebug "Tier 6: BOM bundles in #{pkg_file.basename}: #{names.join(", ")}"
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

      sig { returns(T::Array[Pathname]) }
      def bundles_from_pkgutil_receipts
        require "json"

        metadata_dir = cask_dir/".metadata"
        return [] unless metadata_dir.directory?

        json_files = metadata_dir.glob("**/Casks/#{token}.json")
        if json_files.empty?
          odebug "No metadata JSON found for #{token} in #{metadata_dir}"
          return []
        end

        data = JSON.parse(json_files.max_by(&:mtime).read)
        pkg_patterns = Array(data["artifacts"])
                       .flat_map { |a| Array(a["uninstall"]) }
                       .flat_map { |u| Array(u["pkgutil"]) }
        if pkg_patterns.empty?
          odebug "No pkgutil patterns in metadata for #{token}"
          return []
        end
        odebug "Tier 5: pkgutil patterns for #{token}: #{pkg_patterns.join(", ")}"

        found = T.let([], T::Array[Pathname])

        pkg_patterns.each do |pattern|
          pkg_ids = system_command("/usr/sbin/pkgutil",
                                   args:         ["--pkgs=#{pattern}"],
                                   print_stderr: false)
          unless pkg_ids.exit_status.zero?
            odebug "pkgutil --pkgs=#{pattern}: no matching receipts"
            next
          end

          pkg_ids.stdout.lines.map(&:chomp).reject(&:empty?).each do |pkg_id|
            info = system_command("/usr/sbin/pkgutil",
                                  args:         ["--pkg-info", pkg_id],
                                  print_stderr: false)
            next unless info.exit_status.zero?

            # pkgutil --pkg-info output: "volume: /" and "location: <rel-path>"
            volume = info.stdout.match(/^volume: (.+)$/)&.[](1)&.strip || "/"
            location = info.stdout.match(/^location: (.+)$/)&.[](1)&.strip
            next unless location

            # Plugin packages record their plugin directory as the install
            # location (e.g. Library/Audio/Plug-Ins/VST3). App packages may
            # record a temp staging path that no longer exists at runtime.
            prefix = Pathname(volume)/location

            files = system_command("/usr/sbin/pkgutil",
                                   args:         ["--files", pkg_id],
                                   print_stderr: false)
            next unless files.exit_status.zero?

            bundle_names = files.stdout.lines
                                .map(&:chomp)
                                .reject(&:empty?)
                                .filter_map do |rel|
                                  rel.split("/").find do |p|
                                    BUNDLE_EXTENSIONS.any? { |ext| p.downcase.end_with?(ext) }
                                  end
                                end
                                .uniq
            if bundle_names.empty?
              odebug "pkgutil #{pkg_id}: no bundle-extension files found"
              next
            end

            odebug "Tier 5: pkgutil #{pkg_id}: prefix=#{prefix}, bundles=#{bundle_names.join(", ")}"

            bundle_names.each do |name|
              # Try the receipt's recorded install prefix first (correct for plugins).
              # Fall back to common install dirs for app packages whose receipt
              # records a staging path (e.g. tmp/com.example.pkg) rather than the
              # final location.
              search_dirs = [prefix] + install_dirs
              search_dirs.each do |dir|
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

        dump = self.class.lsregister_dump
        return [] if dump.nil?

        found = T.let([], T::Array[Pathname])

        dump.lines.each do |line|
          next unless (m = line.match(/^\s*path:\s+(.+)$/))

          # Cheap string checks first; the directory? stat only runs for the
          # few dump lines that already match a candidate bundle name.
          path = Pathname(m[1].strip)
          next unless BUNDLE_EXTENSIONS.any? { |ext| path.basename.to_s.downcase.end_with?(ext) }
          next unless candidate_names.any? { |name| name.casecmp(path.basename.to_s).zero? }
          next unless path.directory?

          found << path
        end

        found.uniq
      rescue => e
        odebug "Tier 4: lsregister lookup failed: #{e.message}"
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
        odebug "Tier 7: mdfind lookup failed: #{e.message}"
        []
      end
    end
  end
end
