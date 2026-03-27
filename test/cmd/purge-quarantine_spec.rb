# typed: true
# frozen_string_literal: true

require "fileutils"
require_relative "../../cmd/purge-quarantine"
require "json"
require "tmpdir"

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

  describe "#quarantinable_bundles_for" do
    let(:tmpdir)   { Pathname(Dir.mktmpdir) }
    let(:cask_dir) { tmpdir/"some-cask" }

    after { FileUtils.rm_rf(tmpdir) }

    it "returns bundles staged inside the Caskroom version directory" do
      bundle = cask_dir/"3.0"/"Some App.app"
      (bundle/"Contents").mkpath
      FileUtils.touch(bundle/"Contents"/"Info.plist")

      expect(cmd.send(:quarantinable_bundles_for, "some-cask", cask_dir)).to include(bundle)
    end

    it "falls back to cask definition when Caskroom has no bundles" do
      cask_dir.mkpath
      allow(cmd).to receive(:bundles_from_cask_definition)
        .and_return([Pathname("/Applications/MyApp.app")])

      expect(cmd.send(:quarantinable_bundles_for, "empty-cask", cask_dir))
        .to eq([Pathname("/Applications/MyApp.app")])
    end

    it "falls back to cask metadata when cask definition returns nothing" do
      cask_dir.mkpath
      allow(cmd).to receive_messages(
        bundles_from_cask_definition: [],
        bundles_from_cask_metadata:   [Pathname("/Applications/PkgApp.app")],
      )

      expect(cmd.send(:quarantinable_bundles_for, "pkg-cask", cask_dir))
        .to eq([Pathname("/Applications/PkgApp.app")])
    end

    it "falls back to lsregister when metadata returns nothing" do
      cask_dir.mkpath
      allow(cmd).to receive_messages(
        bundles_from_cask_definition: [],
        bundles_from_cask_metadata:   [],
        bundles_from_lsregister:      [Pathname("/Applications/RegisteredApp.app")],
      )

      expect(cmd.send(:quarantinable_bundles_for, "lsr-cask", cask_dir))
        .to eq([Pathname("/Applications/RegisteredApp.app")])
    end

    it "falls back to pkgutil receipts when lsregister returns nothing" do
      cask_dir.mkpath
      allow(cmd).to receive_messages(
        bundles_from_cask_definition:  [],
        bundles_from_cask_metadata:    [],
        bundles_from_lsregister:       [],
        bundles_from_pkgutil_receipts: [Pathname("/Applications/ReceiptApp.app")],
      )

      expect(cmd.send(:quarantinable_bundles_for, "receipt-cask", cask_dir))
        .to eq([Pathname("/Applications/ReceiptApp.app")])
    end

    it "falls back to pkgutil BOM when receipts return nothing" do
      cask_dir.mkpath
      allow(cmd).to receive_messages(
        bundles_from_cask_definition:  [],
        bundles_from_cask_metadata:    [],
        bundles_from_lsregister:       [],
        bundles_from_pkgutil_receipts: [],
        bundles_from_pkgutil_bom:      [Pathname("/Applications/BomApp.app")],
      )

      expect(cmd.send(:quarantinable_bundles_for, "bom-cask", cask_dir))
        .to eq([Pathname("/Applications/BomApp.app")])
    end

    it "falls back to mdfind when pkgutil BOM returns nothing" do
      cask_dir.mkpath
      allow(cmd).to receive_messages(
        bundles_from_cask_definition:  [],
        bundles_from_cask_metadata:    [],
        bundles_from_lsregister:       [],
        bundles_from_pkgutil_receipts: [],
        bundles_from_pkgutil_bom:      [],
        bundles_from_mdfind:           [Pathname("/Applications/SpotlightApp.app")],
      )

      expect(cmd.send(:quarantinable_bundles_for, "mdfind-cask", cask_dir))
        .to eq([Pathname("/Applications/SpotlightApp.app")])
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
      result = cmd.send(:bundles_from_cask_metadata, token, cask_dir)

      expect(result).to include(app)
    end

    it "returns [] when the .metadata directory is absent" do
      result = cmd.send(:bundles_from_cask_metadata, "nonexistent", tmpdir/"nonexistent")

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
      allow(cmd).to receive(:system_command)
        .with("/usr/sbin/pkgutil", hash_including(args: ["--bom", pkg.to_s]))
        .and_return(bom_result)
      allow(cmd).to receive(:system_command)
        .with("/usr/bin/lsbom", hash_including(args: ["-s", "/tmp/fake.bom"]))
        .and_return(lsbom_result)
      allow(cmd).to receive(:install_dirs).and_return([install])

      result = cmd.send(:bundles_from_pkgutil_bom, "my-cask", cask_dir)

      expect(result).to include(app)
    end

    it "returns [] when no .pkg files are present" do
      result = cmd.send(:bundles_from_pkgutil_bom, "my-cask", cask_dir)

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
      allow(cmd).to receive(:lsregister_dump).and_return(dump)

      found = cmd.send(:bundles_from_lsregister, ["My App.app"])

      expect(found).to include(app)
    end

    it "returns [] when no candidate names are given" do
      expect(cmd.send(:bundles_from_lsregister, [])).to eq([])
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
      allow(cmd).to receive(:system_command)
        .with("/usr/bin/mdfind", hash_including(args: ["-name", "My App.app"]))
        .and_return(result)

      found = cmd.send(:bundles_from_mdfind, ["My App.app"])

      expect(found).to include(app)
    end

    it "returns [] when no candidate names are given" do
      expect(cmd.send(:bundles_from_mdfind, [])).to eq([])
    end
  end
end
