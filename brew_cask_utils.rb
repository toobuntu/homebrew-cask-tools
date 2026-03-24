# frozen_string_literal: true

# DEPRECATED: The QuarantinePurger class has been superseded by the
# `brew purge-quarantine` external command in cmd/brew-purge-quarantine.rb.
# This file is retained for backward compatibility only and will be removed
# in a future release. Use `brew purge-quarantine <cask>` instead.

# Removes macOS quarantine and provenance extended attributes from installed
# cask app bundles.
#
# @deprecated Use `brew purge-quarantine` instead.
class QuarantinePurger
  QUARANTINE_ATTR = "com.apple.quarantine"
  PROVENANCE_ATTR = "com.apple.provenance"

  def initialize(debug: false)
    @debug = debug
  end

  # Removes quarantine and provenance xattrs for all .app bundles belonging
  # to the given cask token.
  #
  # @param token [String] the cask token (e.g. "firefox")
  def purge(token)
    caskroom = caskroom_path
    cask_dir = File.join(caskroom, token)

    unless File.directory?(cask_dir)
      warn "Cask directory not found: #{cask_dir}"
      return
    end

    app_bundles = Dir.glob(File.join(cask_dir, "*", "*.app"))

    if app_bundles.empty?
      warn "No .app bundles found for #{token}"
      return
    end

    app_bundles.each do |app_path|
      real_path = File.realpath(app_path)
      info_plist = File.join(real_path, "Contents", "Info.plist")
      unless File.exist?(info_plist)
        log_debug "Skipping #{real_path}: no Contents/Info.plist"
        next
      end

      $stderr.puts "Removing quarantine from: #{real_path}"
      remove_xattr(real_path, QUARANTINE_ATTR)
      remove_xattr(real_path, PROVENANCE_ATTR)
    rescue => e
      warn "Error processing #{app_path}: #{e.message}"
    end
  end

  private

  def caskroom_path
    `brew --caskroom`.strip
  end

  def remove_xattr(path, attr)
    success = system("/usr/bin/xattr", "-d", "-r", attr, path)
    warn "Failed to remove #{attr} from #{path}" unless success
  end

  def log_debug(message)
    $stderr.puts "[DEBUG] #{message}" if @debug
  end
end
