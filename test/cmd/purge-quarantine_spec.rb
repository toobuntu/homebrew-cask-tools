# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "fileutils"
require_relative "../../cmd/purge-quarantine"

RSpec.describe Homebrew::Cmd::PurgeQuarantine do
  subject(:cmd) { described_class.new(["some-cask"]) }

  describe "#xattrs_present" do
    it "returns matching quarantine attrs from xattr output" do
      result = instance_double(SystemCommand::Result,
                               exit_status: 0,
                               stdout:      "com.apple.quarantine: foo\ncom.apple.provenance: bar",
                               stderr:      "")
      allow(cmd).to receive(:system_command).and_return(result)

      expect(cmd.send(:xattrs_present, Pathname("/some/App.app")))
        .to eq(["com.apple.quarantine", "com.apple.provenance"])
    end

    it "returns [] and emits opoo on non-zero exit" do
      result = instance_double(SystemCommand::Result,
                               exit_status: 1,
                               stdout:      "",
                               stderr:      "Operation not permitted")
      allow(cmd).to receive(:system_command).and_return(result)
      expect(cmd).to receive(:opoo)

      expect(cmd.send(:xattrs_present, Pathname("/some/App.app"))).to eq([])
    end
  end

  describe "#purge_quarantine_for_cask" do
    let(:token)    { "delegated-cask" }
    let(:cask_dir) { HOMEBREW_CASKROOM/token }

    after { FileUtils.rm_rf(cask_dir) }

    it "delegates bundle discovery to CaskTools::BundleDiscovery" do
      cask_dir.mkpath
      discovery = instance_double(Homebrew::CaskTools::BundleDiscovery, bundles: [])
      expect(Homebrew::CaskTools::BundleDiscovery).to receive(:new)
        .with(token, cask_dir).and_return(discovery)
      allow(cmd).to receive(:oh1)
      allow(cmd).to receive(:opoo)

      cmd.send(:purge_quarantine_for_cask, token)
    end
  end
end
