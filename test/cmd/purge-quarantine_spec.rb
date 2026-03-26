# typed: false
# frozen_string_literal: true

require_relative "../../cmd/purge-quarantine"
require "json"
require "tmpdir"

RSpec.describe Homebrew::Cmd::PurgeQuarantine do
  subject(:cmd) { described_class.new(["some-cask"]) }

  it_behaves_like "parseable arguments"

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
    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = Pathname(dir)
        example.run
      end
    end

    it "returns bundles staged inside the Caskroom version directory" do
      cask_dir = @tmpdir/"some-cask"
      bundle   = cask_dir/"3.0"/"Some App.app"
      (bundle/"Contents").mkpath

      result = cmd.send(:quarantinable_bundles_for, "some-cask", cask_dir)

      expect(result).to include(bundle)
    end

    it "falls back to cask definition when Caskroom has no bundles" do
      cask_dir = @tmpdir/"empty-cask"
      cask_dir.mkpath
      allow(cmd).to receive(:bundles_from_cask_definition)
        .and_return([Pathname("/Applications/MyApp.app")])

      result = cmd.send(:quarantinable_bundles_for, "empty-cask", cask_dir)

      expect(result).to eq([Pathname("/Applications/MyApp.app")])
    end

    it "falls back to cask metadata when cask definition returns nothing" do
      cask_dir = @tmpdir/"pkg-cask"
      cask_dir.mkpath
      allow(cmd).to receive_messages(
        bundles_from_cask_definition: [],
        bundles_from_cask_metadata:   [Pathname("/Applications/PkgApp.app")],
      )

      result = cmd.send(:quarantinable_bundles_for, "pkg-cask", cask_dir)

      expect(result).to eq([Pathname("/Applications/PkgApp.app")])
    end

    it "falls back to pkgutil when all previous tiers return nothing" do
      cask_dir = @tmpdir/"receipt-cask"
      cask_dir.mkpath
      allow(cmd).to receive_messages(
        bundles_from_cask_definition: [],
        bundles_from_cask_metadata:   [],
        bundles_from_pkgutil:         [Pathname("/Applications/ReceiptApp.app")],
      )

      result = cmd.send(:quarantinable_bundles_for, "receipt-cask", cask_dir)

      expect(result).to eq([Pathname("/Applications/ReceiptApp.app")])
    end

  end

  describe "#bundles_from_cask_metadata" do
    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = Pathname(dir)
        example.run
      end
    end

    let(:token)    { "my-cask" }
    let(:appdir)   { @tmpdir/"apps" }
    let(:app)      { appdir/"My App.app" }
    let(:cask_dir) { @tmpdir/"Caskroom"/"my-cask" }

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

      expect(result).to include(appdir/"My App.app")
    end

    it "returns [] when the .metadata directory is absent" do
      result = cmd.send(:bundles_from_cask_metadata, "nonexistent", @tmpdir/"nonexistent")

      expect(result).to eq([])
    end

  end
end
