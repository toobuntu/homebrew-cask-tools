# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later OR BSD-2-Clause

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "fileutils"
require_relative "../../cmd/man"
require "tmpdir"

RSpec.describe Homebrew::Cmd::Man do
  subject(:cmd) { described_class.new(["some-formula"]) }

  describe "#resolve_browser" do
    it "returns HOMEBREW_BROWSER when set" do
      with_env("HOMEBREW_BROWSER" => "/usr/bin/firefox") do
        expect(cmd.send(:resolve_browser)).to eq("/usr/bin/firefox")
      end
    end

    it "falls back to BROWSER when HOMEBREW_BROWSER is unset" do
      with_env("HOMEBREW_BROWSER" => nil, "BROWSER" => "/usr/bin/chromium") do
        expect(cmd.send(:resolve_browser)).to eq("/usr/bin/chromium")
      end
    end

    it "returns nil when neither HOMEBREW_BROWSER nor BROWSER is set" do
      with_env("HOMEBREW_BROWSER" => nil, "BROWSER" => nil) do
        expect(cmd.send(:resolve_browser)).to be_nil
      end
    end

    it "prefers HOMEBREW_BROWSER over BROWSER" do
      with_env("HOMEBREW_BROWSER" => "/usr/bin/firefox", "BROWSER" => "/usr/bin/chromium") do
        expect(cmd.send(:resolve_browser)).to eq("/usr/bin/firefox")
      end
    end
  end

  describe "#system_manpath" do
    it "returns an array of Pathname objects" do
      allow(Utils).to receive(:popen_read).with("/usr/bin/manpath").and_return("/usr/share/man:/usr/local/share/man")

      result = cmd.send(:system_manpath)
      expect(result).to all(be_a(Pathname))
      expect(result.map(&:to_s)).to eq(["/usr/share/man", "/usr/local/share/man"])
    end
  end

  describe "#formula_man_dirs" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "returns formula name and man1 dir for installed formulae" do
      man1_dir = tmpdir/"opt/some-pkg/share/man/man1"
      man1_dir.mkpath

      stub_const("HOMEBREW_PREFIX", tmpdir)
      result = cmd.send(:formula_man_dirs)
      expect(result).to include(["some-pkg", man1_dir])
    end

    it "returns empty array when no formulae have man pages" do
      (tmpdir/"opt").mkpath

      stub_const("HOMEBREW_PREFIX", tmpdir)
      expect(cmd.send(:formula_man_dirs)).to eq([])
    end
  end

  describe "#find_formula_manpage" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "finds a man page in the formula's keg" do
      man1_dir = tmpdir/"share/man/man1"
      man1_dir.mkpath
      manfile = man1_dir/"some-formula.1"
      FileUtils.touch(manfile)

      formula = instance_double(Formula, opt_prefix: tmpdir)
      allow(Formula).to receive(:[]).with("some-formula").and_return(formula)
      allow(Utils).to receive(:popen_read).and_return(manfile.to_s)

      expect(cmd.send(:find_formula_manpage, "some-formula", "some-formula")).to eq(manfile)
    end
  end

  describe "#list_manpages" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "lists system and formula man pages" do
      sys_man = tmpdir/"sys/man1"
      sys_man.mkpath
      FileUtils.touch(sys_man/"testcmd.1")

      formula_man = tmpdir/"opt/test-formula/share/man/man1"
      formula_man.mkpath
      FileUtils.touch(formula_man/"testcmd.1")

      allow(cmd).to receive(:system_manpath).and_return([tmpdir/"sys"])
      stub_const("HOMEBREW_PREFIX", tmpdir)

      expect { cmd.send(:list_manpages, "testcmd") }
        .to output(/system:.*testcmd\.1.*test-formula:.*testcmd\.1/m).to_stdout
    end
  end

  describe "#select_manpage" do
    it "dies when fzf is not installed" do
      allow(cmd).to receive(:which).with("fzf").and_return(nil)

      expect { cmd.send(:select_manpage, "testcmd") }
        .to raise_error(SystemExit)
    end
  end
end
