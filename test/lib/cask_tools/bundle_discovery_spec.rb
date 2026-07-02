# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "fileutils"
require_relative "../../../lib/cask_tools/bundle_discovery"
require "json"
require "tmpdir"

RSpec.describe Homebrew::CaskTools::BundleDiscovery do
  describe "#bundles" do
    let(:tmpdir)   { Pathname(Dir.mktmpdir) }
    let(:cask_dir) { tmpdir/"some-cask" }

    after { FileUtils.rm_rf(tmpdir) }

    it "returns bundles staged inside the Caskroom version directory" do
      bundle = cask_dir/"3.0"/"Some App.app"
      (bundle/"Contents").mkpath
      FileUtils.touch(bundle/"Contents"/"Info.plist")

      expect(described_class.new("some-cask", cask_dir).bundles).to include(bundle)
    end

    it "falls back to cask definition when Caskroom has no bundles" do
      cask_dir.mkpath
      discovery = described_class.new("empty-cask", cask_dir)
      allow(discovery).to receive(:bundles_from_cask_definition)
        .and_return([Pathname("/Applications/MyApp.app")])

      expect(discovery.bundles).to eq([Pathname("/Applications/MyApp.app")])
    end

    it "falls back to cask metadata when cask definition returns nothing" do
      cask_dir.mkpath
      discovery = described_class.new("pkg-cask", cask_dir)
      allow(discovery).to receive_messages(
        bundles_from_cask_definition: [],
        bundles_from_cask_metadata:   [Pathname("/Applications/PkgApp.app")],
      )

      expect(discovery.bundles).to eq([Pathname("/Applications/PkgApp.app")])
    end

    it "falls back to lsregister when metadata returns nothing" do
      cask_dir.mkpath
      discovery = described_class.new("lsr-cask", cask_dir)
      allow(discovery).to receive_messages(
        bundles_from_cask_definition: [],
        bundles_from_cask_metadata:   [],
        bundles_from_lsregister:      [Pathname("/Applications/RegisteredApp.app")],
      )

      expect(discovery.bundles).to eq([Pathname("/Applications/RegisteredApp.app")])
    end

    it "falls back to pkgutil receipts when lsregister returns nothing" do
      cask_dir.mkpath
      discovery = described_class.new("receipt-cask", cask_dir)
      allow(discovery).to receive_messages(
        bundles_from_cask_definition:  [],
        bundles_from_cask_metadata:    [],
        bundles_from_lsregister:       [],
        bundles_from_pkgutil_receipts: [Pathname("/Applications/ReceiptApp.app")],
      )

      expect(discovery.bundles).to eq([Pathname("/Applications/ReceiptApp.app")])
    end

    it "falls back to pkgutil BOM when receipts return nothing" do
      cask_dir.mkpath
      discovery = described_class.new("bom-cask", cask_dir)
      allow(discovery).to receive_messages(
        bundles_from_cask_definition:  [],
        bundles_from_cask_metadata:    [],
        bundles_from_lsregister:       [],
        bundles_from_pkgutil_receipts: [],
        bundles_from_pkgutil_bom:      [Pathname("/Applications/BomApp.app")],
      )

      expect(discovery.bundles).to eq([Pathname("/Applications/BomApp.app")])
    end

    it "falls back to mdfind when pkgutil BOM returns nothing" do
      cask_dir.mkpath
      discovery = described_class.new("mdfind-cask", cask_dir)
      allow(discovery).to receive_messages(
        bundles_from_cask_definition:  [],
        bundles_from_cask_metadata:    [],
        bundles_from_lsregister:       [],
        bundles_from_pkgutil_receipts: [],
        bundles_from_pkgutil_bom:      [],
        bundles_from_mdfind:           [Pathname("/Applications/SpotlightApp.app")],
      )

      expect(discovery.bundles).to eq([Pathname("/Applications/SpotlightApp.app")])
    end
  end

  describe "#bundles_from_cask_metadata" do
    let(:tmpdir)   { Pathname(Dir.mktmpdir) }
    let(:token)    { "my-cask" }
    let(:cask_dir) { tmpdir/"Caskroom"/"my-cask" }
    let(:appdir)   { tmpdir/"apps" }
    let(:app)      { appdir/"My App.app" }

    after { FileUtils.rm_rf(tmpdir) }

    before do
      (app/"Contents").mkpath
      (app/"Contents"/"Info.plist").write("<plist/>")
      metadata_dir = cask_dir/".metadata"
      (metadata_dir/"1.0"/"Casks").mkpath
      (metadata_dir/"config.json").write(
        { "explicit" => { "appdir" => appdir.to_s } }.to_json,
      )
      (metadata_dir/"1.0"/"Casks"/"my-cask.json").write(
        { "artifacts" => [{ "app" => ["My App.app"] }] }.to_json,
      )
    end

    it "finds the app bundle in the configured appdir" do
      result = described_class.new(token, cask_dir).send(:bundles_from_cask_metadata)

      expect(result).to include(app)
    end

    it "returns [] when the .metadata directory is absent" do
      discovery = described_class.new("nonexistent", tmpdir/"nonexistent")
      result = discovery.send(:bundles_from_cask_metadata)

      expect(result).to eq([])
    end
  end

  describe "#bundles_from_pkgutil_bom" do
    let(:tmpdir)   { Pathname(Dir.mktmpdir) }
    let(:cask_dir) { tmpdir/"my-cask" }
    let(:install)  { tmpdir/"Applications" }
    let(:app)      { install/"My App.app" }

    after { FileUtils.rm_rf(tmpdir) }

    before { (cask_dir/"1.0").mkpath }

    it "finds bundles using lsbom output and install_dirs" do
      pkg = cask_dir/"1.0"/"install.pkg"
      pkg.write("")
      (app/"Contents").mkpath
      bom_result = instance_double(SystemCommand::Result,
                                   exit_status: 0, stdout: "/tmp/fake.bom\n", stderr: "")
      lsbom_result = instance_double(SystemCommand::Result,
                                     exit_status: 0,
                                     stdout:      "./My App.app\n./My App.app/Contents/MacOS/helper\n",
                                     stderr:      "")
      discovery = described_class.new("my-cask", cask_dir)
      allow(discovery).to receive(:system_command)
        .with("/usr/sbin/pkgutil", hash_including(args: ["--bom", pkg.to_s]))
        .and_return(bom_result)
      allow(discovery).to receive(:system_command)
        .with("/usr/bin/lsbom", hash_including(args: ["-s", "/tmp/fake.bom"]))
        .and_return(lsbom_result)
      allow(discovery).to receive(:install_dirs).and_return([install])

      result = discovery.send(:bundles_from_pkgutil_bom)

      expect(result).to include(app)
    end

    it "returns [] when no .pkg files are present" do
      result = described_class.new("my-cask", cask_dir).send(:bundles_from_pkgutil_bom)

      expect(result).to eq([])
    end
  end

  describe "#bundles_from_lsregister" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }
    let(:app)    { tmpdir/"My App.app" }

    after { FileUtils.rm_rf(tmpdir) }

    before { (app/"Contents").mkpath }

    it "finds bundles matching candidate names in the lsregister dump" do
      dump = "------------------------------------------------------------\n" \
             "path:           #{app}\n" \
             "bundle id:      com.example.myapp\n"
      allow(described_class).to receive(:lsregister_dump).and_return(dump)

      discovery = described_class.new("my-cask", tmpdir/"my-cask")
      found = discovery.send(:bundles_from_lsregister, ["My App.app"])

      expect(found).to include(app)
    end

    it "returns [] when no candidate names are given" do
      discovery = described_class.new("my-cask", tmpdir/"my-cask")
      expect(discovery.send(:bundles_from_lsregister, [])).to eq([])
    end
  end

  describe "#candidate_names" do
    let(:tmpdir)   { Pathname(Dir.mktmpdir) }
    let(:cask_dir) { tmpdir/"Caskroom"/"my-cask" }

    after { FileUtils.rm_rf(tmpdir) }

    it "extracts app names from metadata JSON" do
      metadata_dir = cask_dir/".metadata"/"1.0"/"Casks"
      metadata_dir.mkpath
      (metadata_dir/"my-cask.json").write(
        { "artifacts" => [{ "app" => ["My App.app"] }] }.to_json,
      )

      result = described_class.new("my-cask", cask_dir).candidate_names
      expect(result).to include("My App.app")
    end

    it "extracts delete paths with bundle extensions" do
      metadata_dir = cask_dir/".metadata"/"1.0"/"Casks"
      metadata_dir.mkpath
      (metadata_dir/"my-cask.json").write(
        { "artifacts" => [{ "uninstall" => [{ "delete" => ["/Applications/My App.app"] }] }] }.to_json,
      )

      result = described_class.new("my-cask", cask_dir).candidate_names
      expect(result).to include("My App.app")
    end

    it "returns empty array when metadata directory is absent" do
      cask_dir.mkpath
      expect(described_class.new("my-cask", cask_dir).candidate_names).to eq([])
    end

    it "returns empty array when no JSON files exist" do
      (cask_dir/".metadata").mkpath
      expect(described_class.new("my-cask", cask_dir).candidate_names).to eq([])
    end

    it "filters delete paths that are not bundle extensions" do
      metadata_dir = cask_dir/".metadata"/"1.0"/"Casks"
      metadata_dir.mkpath
      (metadata_dir/"my-cask.json").write(
        { "artifacts" => [{ "uninstall" => [{ "delete" => ["/usr/local/bin/tool"] }] }] }.to_json,
      )

      expect(described_class.new("my-cask", cask_dir).candidate_names).to eq([])
    end

    it "extracts bundle names from pkgutil when available" do
      metadata_dir = cask_dir/".metadata"/"1.0"/"Casks"
      metadata_dir.mkpath
      (metadata_dir/"my-cask.json").write(
        { "artifacts" => [{ "uninstall" => [{ "pkgutil" => ["com.example.*"] }] }] }.to_json,
      )

      pkgs_result = instance_double(SystemCommand::Result,
                                    exit_status: 0, stdout: "com.example.pkg\n", stderr: "")
      files_result = instance_double(SystemCommand::Result,
                                     exit_status: 0,
                                     stdout:      "My App.app/Contents/MacOS/app\n",
                                     stderr:      "")
      discovery = described_class.new("my-cask", cask_dir)
      allow(discovery).to receive(:system_command)
        .with("/usr/sbin/pkgutil", hash_including(args: ["--pkgs=com.example.*"]))
        .and_return(pkgs_result)
      allow(discovery).to receive(:system_command)
        .with("/usr/sbin/pkgutil", hash_including(args: ["--files", "com.example.pkg"]))
        .and_return(files_result)

      result = discovery.candidate_names
      expect(result).to include("My App.app")
    end

    it "handles pkgutil failures gracefully" do
      metadata_dir = cask_dir/".metadata"/"1.0"/"Casks"
      metadata_dir.mkpath
      (metadata_dir/"my-cask.json").write(
        { "artifacts" => [{ "uninstall" => [{ "pkgutil" => ["com.example.*"] }] }] }.to_json,
      )

      pkgs_result = instance_double(SystemCommand::Result,
                                    exit_status: 1, stdout: "", stderr: "error")
      discovery = described_class.new("my-cask", cask_dir)
      allow(discovery).to receive(:system_command)
        .with("/usr/sbin/pkgutil", hash_including(args: ["--pkgs=com.example.*"]))
        .and_return(pkgs_result)

      expect(discovery.candidate_names).to eq([])
    end

    it "deduplicates results from multiple sources" do
      metadata_dir = cask_dir/".metadata"/"1.0"/"Casks"
      metadata_dir.mkpath
      (metadata_dir/"my-cask.json").write(
        { "artifacts" => [
          { "app" => ["My App.app"] },
          { "uninstall" => [{ "delete" => ["/Applications/My App.app"] }] },
        ] }.to_json,
      )

      result = described_class.new("my-cask", cask_dir).candidate_names
      expect(result.count("My App.app")).to eq(1)
    end

    it "memoizes the computed names on the instance" do
      metadata_dir = cask_dir/".metadata"/"1.0"/"Casks"
      metadata_dir.mkpath
      (metadata_dir/"my-cask.json").write(
        { "artifacts" => [{ "app" => ["My App.app"] }] }.to_json,
      )

      discovery = described_class.new("my-cask", cask_dir)
      first = discovery.candidate_names
      FileUtils.rm_rf(cask_dir/".metadata")

      expect(discovery.candidate_names).to equal(first)
    end
  end

  describe "#bundles_from_mdfind" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }
    let(:app)    { tmpdir/"My App.app" }

    after { FileUtils.rm_rf(tmpdir) }

    before { (app/"Contents").mkpath }

    it "finds bundles by name via Spotlight" do
      result = instance_double(SystemCommand::Result,
                               exit_status: 0, stdout: "#{app}\n", stderr: "")
      discovery = described_class.new("my-cask", tmpdir/"my-cask")
      allow(discovery).to receive(:system_command)
        .with("/usr/bin/mdfind", hash_including(args: ["-name", "My App.app"]))
        .and_return(result)

      found = discovery.send(:bundles_from_mdfind, ["My App.app"])

      expect(found).to include(app)
    end

    it "returns [] when no candidate names are given" do
      discovery = described_class.new("my-cask", tmpdir/"my-cask")
      expect(discovery.send(:bundles_from_mdfind, [])).to eq([])
    end
  end
end
