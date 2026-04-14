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

  describe "#system_manpath" do
    it "returns an array of Pathname objects" do
      allow(cmd).to receive(:which).with("manpath").and_return(Pathname("/usr/bin/manpath"))
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
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "dies when no man pages are found" do
      allow(cmd).to receive(:system_manpath).and_return([])
      stub_const("HOMEBREW_PREFIX", tmpdir)
      (tmpdir/"opt").mkpath

      expect { cmd.send(:select_manpage, "nonexistent") }
        .to raise_error(SystemExit)
    end

    it "returns the selected man page path" do
      sys_man = tmpdir/"sys/man1"
      sys_man.mkpath
      manfile = sys_man/"testcmd.1"
      FileUtils.touch(manfile)

      allow(cmd).to receive(:system_manpath).and_return([tmpdir/"sys"])
      stub_const("HOMEBREW_PREFIX", tmpdir)
      (tmpdir/"opt").mkpath
      allow($stdin).to receive(:gets).and_return("1\n")

      expect(cmd.send(:select_manpage, "testcmd")).to eq(manfile)
    end

    it "dies on invalid selection" do
      sys_man = tmpdir/"sys/man1"
      sys_man.mkpath
      FileUtils.touch(sys_man/"testcmd.1")

      allow(cmd).to receive(:system_manpath).and_return([tmpdir/"sys"])
      stub_const("HOMEBREW_PREFIX", tmpdir)
      (tmpdir/"opt").mkpath
      allow($stdin).to receive(:gets).and_return("99\n")

      expect { cmd.send(:select_manpage, "testcmd") }
        .to raise_error(SystemExit)
    end

    it "dies when stdin returns nil (EOF)" do
      sys_man = tmpdir/"sys/man1"
      sys_man.mkpath
      FileUtils.touch(sys_man/"testcmd.1")

      allow(cmd).to receive(:system_manpath).and_return([tmpdir/"sys"])
      stub_const("HOMEBREW_PREFIX", tmpdir)
      (tmpdir/"opt").mkpath
      allow($stdin).to receive(:gets).and_return(nil)

      expect { cmd.send(:select_manpage, "testcmd") }
        .to raise_error(SystemExit)
    end
  end

  describe "#render_html" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "writes mandoc HTML output to a temp file and opens it in the browser" do
      manpage = tmpdir/"testcmd.1"
      manpage.write(".TH testcmd 1\n")
      html_output = "<html><body>rendered man page</body></html>"

      allow(cmd).to receive(:which).with("mandoc").and_return(Pathname("/usr/bin/mandoc"))
      allow(Utils).to receive(:popen_read).and_return(html_output)

      rendered_content = T.let(nil, T.nilable(String))
      allow(cmd).to receive(:exec_browser) { |path| rendered_content = File.read(path) }

      cmd.send(:render_html, manpage)

      expect(rendered_content).to eq(html_output)
    end

    it "exits when mandoc returns empty output" do
      manpage = tmpdir/"testcmd.1"
      manpage.write(".TH testcmd 1\n")

      allow(cmd).to receive(:which).with("mandoc").and_return(Pathname("/usr/bin/mandoc"))
      allow(Utils).to receive(:popen_read).and_return("")

      expect(cmd).not_to receive(:exec_browser)
      expect { cmd.send(:render_html, manpage) }.to raise_error(SystemExit)
    end

    it "exits when mandoc is not found" do
      manpage = tmpdir/"testcmd.1"
      manpage.write(".TH testcmd 1\n")

      allow(cmd).to receive(:which).with("mandoc").and_return(nil)

      expect { cmd.send(:render_html, manpage) }.to raise_error(SystemExit)
    end
  end
end
