# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "fileutils"
require_relative "../../cmd/generate-tap-completions"
require "tmpdir"

RSpec.describe Homebrew::Cmd::GenerateTapCompletions do
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
end
