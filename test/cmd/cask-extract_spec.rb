# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "fileutils"
require_relative "../../cmd/cask-extract"
require "tmpdir"

RSpec.describe Homebrew::Cmd::CaskExtract do
  subject(:cmd) { described_class.new(["some-cask", "user/tap"]) }

  describe "#parse_version_from_content" do
    it "extracts a double-quoted version string" do
      content = <<~RUBY
        cask "some-cask" do
          version "1.2.3"
          sha256 "abc123"
        end
      RUBY

      expect(cmd.send(:parse_version_from_content, content)).to eq("1.2.3")
    end

    it "extracts a single-quoted version string" do
      content = <<~RUBY
        cask "some-cask" do
          version '4.5.6'
          sha256 "abc123"
        end
      RUBY

      expect(cmd.send(:parse_version_from_content, content)).to eq("4.5.6")
    end

    it "returns nil when no version stanza is present" do
      content = <<~RUBY
        cask "some-cask" do
          sha256 "abc123"
        end
      RUBY

      expect(cmd.send(:parse_version_from_content, content)).to be_nil
    end

    it "ignores commented-out version lines" do
      content = <<~RUBY
        cask "some-cask" do
          # version "0.0.1"
          version "2.0.0"
        end
      RUBY

      expect(cmd.send(:parse_version_from_content, content)).to eq("2.0.0")
    end
  end

  describe "#destination_cask_path" do
    let(:tmpdir)  { Pathname(Dir.mktmpdir) }
    let(:tap)     { instance_double(Tap, path: tmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "shards by first letter for normal tokens" do
      path = cmd.send(:destination_cask_path, tap, "iterm2")

      expect(path).to eq(tmpdir/"Casks"/"i"/"iterm2.rb")
    end

    it "shards into font/ for font- tokens" do
      path = cmd.send(:destination_cask_path, tap, "font-fira-code")

      expect(path).to eq(tmpdir/"Casks"/"font"/"font-fira-code.rb")
    end

    it "writes flat when --no-shard is set" do
      no_shard_cmd = described_class.new(["some-cask", "user/tap", "--no-shard"])
      path = no_shard_cmd.send(:destination_cask_path, tap, "iterm2")

      expect(path).to eq(tmpdir/"Casks"/"iterm2.rb")
    end
  end

  describe "#add_quarantine_postflight" do
    let(:tmpdir)    { Pathname(Dir.mktmpdir) }
    let(:cask_file) { tmpdir/"some-cask.rb" }

    after { FileUtils.rm_rf(tmpdir) }

    it "inserts a postflight block for a single app stanza" do
      cask_file.write(<<~RUBY)
        cask "some-cask" do
          version "1.0"
          app "Some App.app"
        end
      RUBY

      cmd.send(:add_quarantine_postflight, cask_file)

      result = cask_file.read
      expect(result).to include("postflight do")
      expect(result).to include("com.apple.quarantine")
      expect(result).to include("Some App.app")
    end

    it "inserts postflight blocks for multiple app stanzas" do
      cask_file.write(<<~RUBY)
        cask "multi-app" do
          version "2.0"
          app "App One.app"
          app "App Two.app"
        end
      RUBY

      cmd.send(:add_quarantine_postflight, cask_file)

      result = cask_file.read
      expect(result).to include("App One.app")
      expect(result).to include("App Two.app")
      expect(result.scan("system_command").length).to eq(2)
    end

    it "skips if quarantine handling already exists" do
      cask_file.write(<<~RUBY)
        cask "some-cask" do
          version "1.0"
          app "Some App.app"
          postflight do
            system_command "/usr/bin/xattr",
                           args: ["-dr", "com.apple.quarantine", "\#{appdir}/Some App.app"]
          end
        end
      RUBY

      expect(cmd).to receive(:ohai).with("some-cask.rb already has quarantine handling; skipping.")
      cmd.send(:add_quarantine_postflight, cask_file)
    end

    it "warns when no app stanza is found" do
      cask_file.write(<<~RUBY)
        cask "pkg-only" do
          version "1.0"
          pkg "installer.pkg"
        end
      RUBY

      expected_msg = "No app stanza found; quarantine removal may need to be configured manually."
      expect(cmd).to receive(:opoo).with(expected_msg)
      cmd.send(:add_quarantine_postflight, cask_file)
    end

    it "warns when no insertion point is found" do
      # Has an app stanza (on its own line) but no "\nend" at end of file
      cask_file.write("cask \"broken\" do\n  app \"X.app\"\n")

      expect(cmd).to receive(:opoo).with(/Could not locate insertion point/)
      cmd.send(:add_quarantine_postflight, cask_file)
    end
  end

  describe "#find_extracted_cask" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }
    let(:tap)    { instance_double(Tap, path: tmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "finds a sharded cask file" do
      sharded = tmpdir/"Casks"/"s"/"some-cask.rb"
      sharded.dirname.mkpath
      sharded.write("cask content")

      expect(cmd.send(:find_extracted_cask, "some-cask", tap)).to eq(sharded)
    end

    it "finds a flat cask file" do
      flat = tmpdir/"Casks"/"some-cask.rb"
      flat.dirname.mkpath
      flat.write("cask content")

      expect(cmd.send(:find_extracted_cask, "some-cask", tap)).to eq(flat)
    end

    it "returns nil when Casks directory does not exist" do
      expect(cmd.send(:find_extracted_cask, "missing", tap)).to be_nil
    end
  end

  describe "#find_cask_in_history" do
    let(:tmpdir)  { Pathname(Dir.mktmpdir) }
    let(:tap)     { instance_double(Tap, path: tmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "reads from the working tree when a sharded file exists" do
      sharded = tmpdir/"Casks"/"s"/"silverlock.rb"
      sharded.dirname.mkpath
      sharded.write('cask "silverlock" do; end')

      expect(cmd.send(:find_cask_in_history, tap, "silverlock")).to eq('cask "silverlock" do; end')
    end

    it "reads from the working tree when a flat file exists" do
      flat = tmpdir/"Casks"/"silverlock.rb"
      flat.dirname.mkpath
      flat.write('cask "silverlock" do; end')
      # The combined loop tries the sharded pattern first; mock the git search
      # for it returning empty so the loop falls through to the flat pattern.
      allow(Utils).to receive(:popen_read).and_return("")

      expect(cmd.send(:find_cask_in_history, tap, "silverlock")).to eq('cask "silverlock" do; end')
    end

    it "returns nil when the cask is not found anywhere" do
      tmpdir.mkpath
      allow(Utils).to receive(:popen_read).and_return("")

      expect(cmd.send(:find_cask_in_history, tap, "nonexistent")).to be_nil
    end
  end

  describe "integration: fallback extraction", :integration_test do
    let(:tmpdir)       { Pathname(Dir.mktmpdir) }
    let(:source_path)  { tmpdir/"source" }
    let(:dest_path)    { tmpdir/"dest" }

    after { FileUtils.rm_rf(tmpdir) }

    before do
      source_cask = source_path/"Casks"/"s"/"silverlock.rb"
      source_cask.dirname.mkpath
      source_cask.write(<<~RUBY)
        cask "silverlock" do
          version "2.1.0"
          sha256 "deadbeef"

          url "https://example.com/silverlock-2.1.0.dmg"
          name "Silver Lock"

          app "Silver Lock.app"
        end
      RUBY
    end

    it "extracts with versioned token and quarantine postflight" do
      extract_cmd = described_class.new([
        "silverlock", "user/tap", "--no-quarantine"
      ])

      source_tap = instance_double(Tap, path: source_path, installed?: true)
      dest_tap = instance_double(Tap, path: dest_path, installed?: true, to_s: "user/tap")

      allow(Tap).to receive(:fetch).with("user/tap").and_return(dest_tap)
      allow(Tap).to receive(:fetch).with("homebrew/cask").and_return(source_tap)
      allow(Utils).to receive(:popen_read)
        .with(HOMEBREW_BREW_FILE, "extract", "--help")
        .and_return("Usage: brew extract")

      expect { extract_cmd.run }.to output(/Extracted to:/).to_stdout

      result_path = dest_path/"Casks"/"s"/"silverlock@2.1.0.rb"
      expect(result_path).to exist

      content = result_path.read
      expect(content).to include('cask "silverlock@2.1.0"')
      expect(content).to include("postflight do")
      expect(content).to include("com.apple.quarantine")
      expect(content).to include("Silver Lock.app")
    end

    it "extracts unversioned when --unversioned is passed" do
      extract_cmd = described_class.new([
        "silverlock", "user/tap", "--unversioned"
      ])

      source_tap = instance_double(Tap, path: source_path, installed?: true)
      dest_tap = instance_double(Tap, path: dest_path, installed?: true, to_s: "user/tap")

      allow(Tap).to receive(:fetch).with("user/tap").and_return(dest_tap)
      allow(Tap).to receive(:fetch).with("homebrew/cask").and_return(source_tap)
      allow(Utils).to receive(:popen_read)
        .with(HOMEBREW_BREW_FILE, "extract", "--help")
        .and_return("Usage: brew extract")

      expect { extract_cmd.run }.to output(/Extracted to:/).to_stdout

      result_path = dest_path/"Casks"/"s"/"silverlock.rb"
      expect(result_path).to exist
      expect(result_path.read).to include('cask "silverlock"')
    end
  end
end
