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

  describe "#collect_command_paths" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "collects from both cmd/ and dev-cmd/" do
      (tmpdir/"cmd").mkpath
      (tmpdir/"dev-cmd").mkpath
      (tmpdir/"cmd"/"alpha.rb").write("")
      (tmpdir/"dev-cmd"/"beta.rb").write("")

      result = cmd.send(:collect_command_paths, tmpdir)
      names = result.map(&:first).sort

      expect(names).to eq(["alpha", "beta"])
    end

    it "prefers dev-cmd/ path when same name exists in both" do
      (tmpdir/"cmd").mkpath
      (tmpdir/"dev-cmd").mkpath
      (tmpdir/"cmd"/"dup.rb").write("cmd version")
      (tmpdir/"dev-cmd"/"dup.rb").write("dev-cmd version")

      result = cmd.send(:collect_command_paths, tmpdir)
      dup_entry = result.find { |name, _| name == "dup" }

      expect(dup_entry.last.to_s).to include("dev-cmd")
    end

    it "returns empty array when no commands exist" do
      (tmpdir/"cmd").mkpath
      expect(cmd.send(:collect_command_paths, tmpdir)).to eq([])
    end
  end

  describe "#remove_stale_files" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }
    let(:bash_dir) { tmpdir/"bash" }
    let(:zsh_dir) { tmpdir/"zsh" }
    let(:fish_dir) { tmpdir/"fish" }
    let(:man_dir) { tmpdir/"man" }

    before { [bash_dir, zsh_dir, fish_dir, man_dir].each(&:mkpath) }

    after { FileUtils.rm_rf(tmpdir) }

    it "removes files for commands that no longer exist" do
      (bash_dir/"brew-old-cmd").write("stale")
      (zsh_dir/"_brew-old-cmd").write("stale")
      (fish_dir/"brew-old-cmd.fish").write("stale")
      (man_dir/"brew-old-cmd.1").write("stale")
      (man_dir/"brew-old-cmd.1.md").write("stale")

      cmd.send(:remove_stale_files, ["current-cmd"],
               bash_dir:, zsh_dir:, fish_dir:, man_dir:)

      expect((bash_dir/"brew-old-cmd").exist?).to be(false)
      expect((zsh_dir/"_brew-old-cmd").exist?).to be(false)
      expect((fish_dir/"brew-old-cmd.fish").exist?).to be(false)
      expect((man_dir/"brew-old-cmd.1").exist?).to be(false)
      expect((man_dir/"brew-old-cmd.1.md").exist?).to be(false)
    end

    it "preserves files for current commands" do
      (bash_dir/"brew-keep").write("keep")
      cmd.send(:remove_stale_files, ["keep"], bash_dir:, zsh_dir:, fish_dir:, man_dir:)
      expect((bash_dir/"brew-keep").exist?).to be(true)
    end

    it "skips .license sidecar files" do
      (bash_dir/"brew-old-cmd.license").write("license")
      cmd.send(:remove_stale_files, ["current"], bash_dir:, zsh_dir:, fish_dir:, man_dir:)
      expect((bash_dir/"brew-old-cmd.license").exist?).to be(true)
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
      expect(md).to include("`-v`, `--verbose`")
      expect(md).to include("Show verbose output.")
    end

    it "includes a title suffix when the first description line ends with a period" do
      parser = instance_double(Homebrew::CLI::Parser,
                               usage_banner_text: "`test-cmd`\n\nDo something useful.\n",
                               processed_options: [])
      allow(Homebrew::CLI::Parser).to receive(:from_cmd_path).and_return(parser)

      md = cmd.send(:man_page_markdown, "test-cmd", Pathname("/fake/cmd/test-cmd.rb"))

      expect(md).to include("brew-test-cmd(1) -- Do something useful")
    end

    it "excludes hidden options from the generated markdown" do
      parser = instance_double(Homebrew::CLI::Parser,
                               usage_banner_text: "`test-cmd`\n\nSome command.\n",
                               processed_options: [
                                 ["-v", "--verbose", "Show verbose output.", false],
                                 [nil, "--internal", "Hidden flag.", true],
                               ])
      allow(Homebrew::CLI::Parser).to receive(:from_cmd_path).and_return(parser)

      md = cmd.send(:man_page_markdown, "test-cmd", Pathname("/fake/cmd/test-cmd.rb"))

      expect(md).to include("--verbose")
      expect(md).not_to include("--internal")
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

  describe "#run", :integration_test do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }
    let(:cmd_no_exit) { described_class.new(["--no-exit-code"]) }

    after { FileUtils.rm_rf(tmpdir) }

    before do
      (tmpdir/"cmd").mkpath
      (tmpdir/"dev-cmd").mkpath
      (tmpdir/"completions"/"bash").mkpath
      (tmpdir/"completions"/"zsh").mkpath
      (tmpdir/"completions"/"fish").mkpath
      (tmpdir/"manpages").mkpath

      (tmpdir/"cmd"/"alpha.rb").write("# a command")
      (tmpdir/"dev-cmd"/"beta.rb").write("# a dev-command")

      mock_tap = instance_double(Tap, name: "test/tap", path: tmpdir)
      allow(Homebrew::EnvConfig).to receive(:developer?).and_return(true)
      allow(Homebrew).to receive(:install_bundler_gems!)

      parser = instance_double(Homebrew::CLI::Parser,
                               usage_banner_text: "`alpha`\n\nSome command.\n",
                               processed_options: [])
      allow(Homebrew::CLI::Parser).to receive(:from_cmd_path).and_return(parser)

      allow(Homebrew::Completions).to receive_messages(
        generate_bash_subcommand_completion: nil,
        generate_zsh_subcommand_completion:  nil,
        generate_fish_subcommand_completion: nil,
      )

      # Manpages modules are loaded dynamically in run via require. Pre-define
      # stub modules with the expected class methods so the requires are no-ops.
      # When the real modules exist (kramdown available), just use them.
      unless defined?(Homebrew::Manpages::Parser::Ronn)
        # Prevent run from loading the real files (which need kramdown)
        allow(cmd_no_exit).to receive(:require).and_call_original
        allow(cmd_no_exit).to receive(:require).with("manpages/parser/ronn")
        allow(cmd_no_exit).to receive(:require).with("manpages/converter/roff")

        mod = Module.new
        mod.const_set(:Parser, Module.new)
        mod.const_set(:Converter, Module.new)
        ronn = Module.new
        ronn.define_singleton_method(:parse) { |_md| [Object.new, ""] }
        mod::Parser.const_set(:Ronn, ronn)
        roff = Module.new
        roff.define_singleton_method(:convert) { |_root| [".TH TEST\n", ""] }
        mod::Converter.const_set(:Roff, roff)
        stub_const("Homebrew::Manpages", mod)
      end

      diff_result = instance_double(SystemCommand::Result,
                                    status: instance_double(Process::Status, success?: false))
      allow(cmd_no_exit).to receive_messages(resolve_tap: mock_tap, system_command: diff_result)
    end

    it "creates completion and man page files for commands in both cmd/ and dev-cmd/" do
      cmd_no_exit.run

      expect((tmpdir/"completions"/"bash"/"brew-alpha").exist?).to be(true)
      expect((tmpdir/"completions"/"zsh"/"_brew-alpha").exist?).to be(true)
      expect((tmpdir/"completions"/"fish"/"brew-alpha.fish").exist?).to be(true)
      expect((tmpdir/"completions"/"bash"/"brew-beta").exist?).to be(true)
      expect((tmpdir/"completions"/"zsh"/"_brew-beta").exist?).to be(true)
      expect((tmpdir/"completions"/"fish"/"brew-beta.fish").exist?).to be(true)
      expect((tmpdir/"manpages"/"brew-alpha.1.md").exist?).to be(true)
      expect((tmpdir/"manpages"/"brew-alpha.1").exist?).to be(true)
      expect((tmpdir/"manpages"/"brew-beta.1.md").exist?).to be(true)
      expect((tmpdir/"manpages"/"brew-beta.1").exist?).to be(true)
    end
  end
end
