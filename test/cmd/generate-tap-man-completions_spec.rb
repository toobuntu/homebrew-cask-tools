# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "fileutils"
require_relative "../../cmd/generate-tap-man-completions"
require "tmpdir"

RSpec.describe Homebrew::Cmd::GenerateTapManCompletions do
  subject(:cmd) { described_class.new([]) }

  describe "cmd_args" do
    it "accepts --no-exit-code" do
      cmd_with_flag = described_class.new(["--no-exit-code"])
      expect(cmd_with_flag.args.no_exit_code?).to be(true)
    end

    it "accepts --tap" do
      cmd_with_tap = described_class.new(["--tap=toobuntu/cask-tools"])
      expect(cmd_with_tap.args.tap).to eq("toobuntu/cask-tools")
    end
  end

  describe "#write_if_changed" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "creates a new file when it does not exist" do
      path = tmpdir/"new.txt"
      cmd.send(:write_if_changed, path, "hello")
      expect(path.read).to eq("hello")
    end

    it "overwrites the file when content differs" do
      path = tmpdir/"existing.txt"
      path.write("old content")
      cmd.send(:write_if_changed, path, "new content")
      expect(path.read).to eq("new content")
    end

    it "does not modify the file when content is unchanged" do
      path = tmpdir/"unchanged.txt"
      path.write("same")
      original_mtime = path.mtime
      cmd.send(:write_if_changed, path, "same")
      expect(path.mtime).to eq(original_mtime)
    end
  end

  describe "#bash_content" do
    it "starts with the generated-file header" do
      allow(Homebrew::Completions).to receive(:generate_bash_subcommand_completion).and_return(nil)
      result = cmd.send(:bash_content, "test-cmd")
      expect(result).to start_with(described_class::HEADER)
    end

    it "uses Completions output when available" do
      generated = "_brew_test_cmd() { echo hi; }\n"
      allow(Homebrew::Completions).to receive(:generate_bash_subcommand_completion)
        .with("test-cmd").and_return(generated)
      expect(cmd.send(:bash_content, "test-cmd")).to eq("#{described_class::HEADER}#{generated}")
    end

    it "generates a no-op stub when Completions returns nil" do
      allow(Homebrew::Completions).to receive(:generate_bash_subcommand_completion).and_return(nil)
      result = cmd.send(:bash_content, "test-cmd")
      expect(result).to include("_brew_test_cmd()")
    end
  end

  describe "#zsh_content" do
    it "starts with the generated-file header" do
      allow(Homebrew::Completions).to receive(:generate_zsh_subcommand_completion).and_return(nil)
      result = cmd.send(:zsh_content, "test-cmd")
      expect(result).to start_with(described_class::HEADER)
    end

    it "generates a no-op stub when Completions returns nil" do
      allow(Homebrew::Completions).to receive(:generate_zsh_subcommand_completion).and_return(nil)
      result = cmd.send(:zsh_content, "test-cmd")
      expect(result).to include("_brew_test_cmd()")
    end
  end

  describe "#fish_content" do
    it "starts with the generated-file header" do
      allow(Homebrew::Completions).to receive(:generate_fish_subcommand_completion).and_return(nil)
      result = cmd.send(:fish_content, "test-cmd")
      expect(result).to start_with(described_class::HEADER)
    end

    it "generates a fallback completion directive when Completions returns nil" do
      allow(Homebrew::Completions).to receive(:generate_fish_subcommand_completion).and_return(nil)
      result = cmd.send(:fish_content, "test-cmd")
      expect(result).to include("__fish_brew_complete_cmd")
      expect(result).to include("test-cmd")
    end
  end

  describe "#man_page_markdown" do
    it "generates Ronn-format markdown with synopsis, description, and options" do
      parser = instance_double(Homebrew::CLI::Parser,
                               usage_banner_text: "`test-cmd` [`--verbose`]\n\nDo something useful.\n",
                               processed_options: [
                                 ["-v", "--verbose", "Show verbose output.", false],
                               ])
      allow(Homebrew::CLI::Parser).to receive(:from_cmd_path).and_return(parser)

      md = cmd.send(:man_page_markdown, "test-cmd", Pathname("/fake/cmd/test-cmd.rb"))

      expect(md).to include("brew-test-cmd(1)")
      expect(md).to include("## SYNOPSIS")
      expect(md).to include("## DESCRIPTION")
      expect(md).to include("## OPTIONS")
      expect(md).to include("`--verbose`")
    end

    it "includes a title suffix when the first description line ends with a period" do
      parser = instance_double(Homebrew::CLI::Parser,
                               usage_banner_text: "`test-cmd`\n\nDo something useful.\n",
                               processed_options: [])
      allow(Homebrew::CLI::Parser).to receive(:from_cmd_path).and_return(parser)

      md = cmd.send(:man_page_markdown, "test-cmd", Pathname("/fake/cmd/test-cmd.rb"))

      expect(md).to include("brew-test-cmd(1) -- Do something useful")
    end

    it "returns nil when from_cmd_path returns nil" do
      allow(Homebrew::CLI::Parser).to receive(:from_cmd_path).and_return(nil)
      expect(cmd.send(:man_page_markdown, "none", Pathname("/fake"))).to be_nil
    end

    it "returns nil when usage_banner_text is nil" do
      parser = instance_double(Homebrew::CLI::Parser, usage_banner_text: nil)
      allow(Homebrew::CLI::Parser).to receive(:from_cmd_path).and_return(parser)
      expect(cmd.send(:man_page_markdown, "none", Pathname("/fake"))).to be_nil
    end
  end
end
