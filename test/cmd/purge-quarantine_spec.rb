# frozen_string_literal: true

require_relative "../../cmd/purge-quarantine"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::PurgeQuarantine do
  it_behaves_like "parseable arguments"

  subject(:cmd) { described_class.new(["some-cask"]) }

  # Helpers to build a fake SystemCommand::Result
  def ok_result(stdout: "", stderr: "")
    instance_double(SystemCommand::Result, exit_status: 0, stdout:, stderr:)
  end

  def err_result(stderr: "Operation not permitted")
    instance_double(SystemCommand::Result, exit_status: 1, stdout: "", stderr:)
  end

  describe "#xattrs_present" do
    it "returns empty array when xattr exits non-zero" do
      allow(cmd).to receive(:system_command).and_return(err_result)
      expect(cmd.send(:xattrs_present, Pathname("/fake/App.app"))).to eq([])
    end

    it "returns only attributes present in xattr output" do
      stdout = "App.app: com.apple.quarantine\n0083;...\nApp.app: com.apple.provenance\n"
      allow(cmd).to receive(:system_command).and_return(ok_result(stdout:))
      result = cmd.send(:xattrs_present, Pathname("/fake/App.app"))
      expect(result).to contain_exactly("com.apple.quarantine", "com.apple.provenance")
    end

    it "returns empty when output has neither quarantine nor provenance" do
      allow(cmd).to receive(:system_command).and_return(ok_result(stdout: "com.example.other\n"))
      expect(cmd.send(:xattrs_present, Pathname("/fake/App.app"))).to eq([])
    end
  end

  describe "#xattr_deleted?" do
    it "returns true when xattr -d exits 0" do
      allow(cmd).to receive(:system_command).and_return(ok_result)
      expect(cmd.send(:xattr_deleted?, Pathname("/fake/App.app"), "com.apple.quarantine")).to be(true)
    end

    it "returns false when xattr -d exits non-zero" do
      allow(cmd).to receive(:system_command).and_return(err_result)
      expect(cmd.send(:xattr_deleted?, Pathname("/fake/App.app"), "com.apple.quarantine")).to be(false)
    end
  end

  describe "#verify_xattr_removed" do
    it "calls ofail when attribute is still present" do
      allow(cmd).to receive(:xattrs_present).and_return(["com.apple.quarantine"])
      expect(cmd).to receive(:ofail)
      cmd.send(:verify_xattr_removed, Pathname("/fake/App.app"), "com.apple.quarantine")
    end

    it "does not call ofail when attribute is gone" do
      allow(cmd).to receive(:xattrs_present).and_return([])
      expect(cmd).not_to receive(:ofail)
      cmd.send(:verify_xattr_removed, Pathname("/fake/App.app"), "com.apple.quarantine")
    end
  end

  describe "#quarantinable_bundles_for" do
    it "returns empty and falls through to metadata when cask dir has no bundle subdirs" do
      Dir.mktmpdir do |cask_dir_s|
        cask_dir = Pathname(cask_dir_s)
        allow(cmd).to receive(:bundles_from_cask_definition).and_return([])
        allow(cmd).to receive(:bundles_from_cask_metadata).and_return([])
        result = cmd.send(:quarantinable_bundles_for, "test-cask", cask_dir)
        expect(result).to eq([])
      end
    end

    it "returns bundle dirs found directly under a version subdirectory" do
      Dir.mktmpdir do |cask_dir_s|
        cask_dir = Pathname(cask_dir_s)
        bundle = cask_dir/"1.0"/"My App.app"
        bundle.mkpath
        result = cmd.send(:quarantinable_bundles_for, "test-cask", cask_dir)
        expect(result).to include(bundle)
      end
    end
  end

  describe "#bundles_from_cask_metadata" do
    it "returns empty when .metadata directory does not exist" do
      Dir.mktmpdir do |cask_dir_s|
        cask_dir = Pathname(cask_dir_s)
        expect(cmd.send(:bundles_from_cask_metadata, "test-cask", cask_dir)).to eq([])
      end
    end

    it "finds the app in the configured appdir" do
      Dir.mktmpdir do |tmp|
        tmp = Pathname(tmp)
        cask_dir = tmp/"test-cask"
        appdir = tmp/"apps"
        app = appdir/"My App.app"
        app.mkpath

        config_path = cask_dir/".metadata"/"config.json"
        config_path.dirname.mkpath
        config_path.write(JSON.generate({ "explicit" => { "appdir" => appdir.to_s } }))

        cask_json_path = cask_dir/".metadata"/"1.0"/"20260101000000.0"/"Casks"/"test-cask.json"
        cask_json_path.dirname.mkpath
        cask_json_path.write(JSON.generate({ "artifacts" => [{ "app" => ["My App.app"] }] }))

        result = cmd.send(:bundles_from_cask_metadata, "test-cask", cask_dir)
        expect(result).to include(app)
      end
    end
  end

  describe "#purge_quarantine_for_cask", :integration_test do
    it "calls ofail for a cask not found in Caskroom" do
      Dir.mktmpdir do |tmpdir|
        stub_const("HOMEBREW_CASKROOM", Pathname(tmpdir))
        expect { cmd.send(:purge_quarantine_for_cask, "no-such-cask") }
          .to output(/no-such-cask/).to_stderr
      end
    end
  end
end
