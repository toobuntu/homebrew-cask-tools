# frozen_string_literal: true

require "cli/parser"
require "tap"
require "cask/cask_loader"

module Homebrew
  module_function

  def cask_extract_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Extract a cask formula at a given version from this tap's history into another tap.
        Optionally add a postflight block to remove macOS's quarantine extended attribute.
      EOS

      named_args [:cask, :tap], number: 2

      flag   "--version=",
             description: "Extract this specific version from formula history."
      switch "--no-quarantine",
             description: "Add a postflight block to remove the quarantine xattr."
      switch "--unversioned",
             description: "Extract the cask without adding a version suffix."
      switch "--force",
             description: "Overwrite the destination if it already exists."
      switch "--no-shard",
             description: "Write to a flat Casks/ directory instead of a sharded one."
    end
  end

  def cask_extract
    args = cask_extract_args.parse

    token = args.named[0]
    destination_tap_name = args.named[1]

    destination_tap = Tap.fetch(destination_tap_name)
    destination_tap.install unless destination_tap.installed?

    if try_brew_extract_cask(token, destination_tap_name, args)
      post_process_extracted_cask(token, destination_tap, args)
    else
      fallback_extract(token, destination_tap, args)
    end
  end

  def try_brew_extract_cask(token, destination_tap_name, args)
    # Check whether the installed brew supports `brew extract --cask`.
    help_output = Utils.popen_read(HOMEBREW_BREW_FILE, "extract", "--help")
    return false unless help_output.include?("--cask")

    cmd = [HOMEBREW_BREW_FILE, "extract", "--cask", token, destination_tap_name]
    cmd += ["--version=#{args.version}"] if args.version
    cmd << "--force" if args.force?

    safe_system(*cmd)
    true
  rescue ErrorDuringExecution
    false
  end

  def post_process_extracted_cask(token, destination_tap, args)
    extracted_path = find_extracted_cask(token, destination_tap, args)
    unless extracted_path
      odie "Could not find extracted cask file for #{token} in #{destination_tap.path}"
    end

    warn_maintainer(token)

    if args.no_quarantine?
      add_quarantine_postflight(extracted_path, token)
    end

    ohai "Extracted to:", extracted_path.to_s
    puts "Install with: brew install --cask #{destination_tap}/#{token}"
  end

  def find_extracted_cask(token, tap, args)
    casks_dir = tap.path/"Casks"
    return nil unless casks_dir.exist?

    # Try sharded path first, then flat
    [
      casks_dir/"#{token[0]}"/"#{token}.rb",
      casks_dir/"#{token}.rb",
    ].find(&:exist?)
  end

  def fallback_extract(token, destination_tap, args)
    ohai "Falling back to manual extraction (brew extract --cask not available)"

    source_tap = Tap.fetch("homebrew/cask")
    unless source_tap.installed?
      odie "Source tap homebrew/cask is not installed."
    end

    content, source_path = find_cask_in_history(source_tap, token)
    odie "Could not find cask #{token}!" if content.nil?

    version = args.version || parse_version_from_content(content)
    odie "Could not determine version for cask #{token}!" if version.nil?

    versioned_token = args.unversioned? ? token : "#{token}@#{version}"
    content = content.gsub(/^(\s*cask\s+)["']#{Regexp.escape(token)}["']/, "\\1\"#{versioned_token}\"")

    dest_path = destination_cask_path(destination_tap, versioned_token, args)

    if dest_path.exist? && !args.force?
      odie "Destination already exists: #{dest_path}\nUse --force to overwrite."
    end

    dest_path.dirname.mkpath
    dest_path.write(content)

    warn_maintainer(token)

    if args.no_quarantine?
      add_quarantine_postflight(dest_path, versioned_token)
    end

    ohai "Extracted to:", dest_path.to_s
    puts "Install with: brew install --cask #{destination_tap}/#{versioned_token}"
  end

  def find_cask_in_history(tap, token)
    tap_path = tap.path

    # Search patterns: sharded and flat
    patterns = [
      "Casks/#{token[0]}/#{token}.rb",
      "Casks/#{token}.rb",
    ]

    # Try working tree first
    patterns.each do |pattern|
      full_path = tap_path/pattern
      return [full_path.read, full_path] if full_path.exist?
    end

    # Search git history
    patterns.each do |pattern|
      log_output = Utils.popen_read(
        "git", "-C", tap_path.to_s,
        "log", "--all", "--oneline", "--", pattern
      ).strip
      next if log_output.empty?

      commit = log_output.lines.first.split.first
      content = Utils.popen_read(
        "git", "-C", tap_path.to_s,
        "show", "#{commit}:#{pattern}"
      )
      return [content, tap_path/pattern] unless content.empty?
    end

    nil
  end

  def parse_version_from_content(content)
    match = content.match(/^\s*version\s+["']([^"']+)["']/)
    match&.captures&.first
  end

  def destination_cask_path(tap, token, args)
    casks_dir = tap.path/"Casks"

    if args.no_shard?
      casks_dir/"#{token}.rb"
    elsif token.start_with?("font-")
      casks_dir/"font"/"#{token}.rb"
    else
      casks_dir/"#{token[0]}"/"#{token}.rb"
    end
  end

  def warn_maintainer(token)
    opoo <<~EOS
      You are responsible for maintaining #{token}!
      It will not receive updates from Homebrew.
    EOS
  end

  def add_quarantine_postflight(cask_path, token)
    content = cask_path.read

    # Skip if a postflight block mentioning quarantine already exists
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

    # Insert the postflight block before the closing `end` of the cask block
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
