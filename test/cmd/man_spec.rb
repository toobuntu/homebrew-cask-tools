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

  describe "#formula_man_dirs" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "returns formula name and man dir for installed formulae with man1" do
      man1_dir = tmpdir/"opt/some-pkg/share/man/man1"
      man1_dir.mkpath

      stub_const("HOMEBREW_PREFIX", tmpdir)
      result = cmd.send(:formula_man_dirs)
      expect(result).to include(["some-pkg", man1_dir.parent])
    end

    it "returns formula name and man dir for formulae with non-man1 sections" do
      man3_dir = tmpdir/"opt/openssl/share/man/man3"
      man3_dir.mkpath

      stub_const("HOMEBREW_PREFIX", tmpdir)
      result = cmd.send(:formula_man_dirs)
      expect(result).to include(["openssl", man3_dir.parent])
    end

    it "deduplicates formulae with multiple man sections" do
      (tmpdir/"opt/curl/share/man/man1").mkpath
      (tmpdir/"opt/curl/share/man/man3").mkpath

      stub_const("HOMEBREW_PREFIX", tmpdir)
      result = cmd.send(:formula_man_dirs)
      formula_names = result.map(&:first)
      expect(formula_names.count("curl")).to eq(1)
    end

    it "returns empty array when no formulae have man pages" do
      (tmpdir/"opt").mkpath

      stub_const("HOMEBREW_PREFIX", tmpdir)
      expect(cmd.send(:formula_man_dirs)).to eq([])
    end
  end

  describe "#parse_default_args" do
    it "detects a section number as first argument" do
      section_cmd = described_class.new(["1", "libressl", "openssl"])
      section, formula_name, page = section_cmd.send(:parse_default_args)
      expect(section).to eq("1")
      expect(formula_name).to eq("libressl")
      expect(page).to eq("openssl")
    end

    it "passes through when first argument is not a section" do
      no_section_cmd = described_class.new(["libressl", "openssl"])
      section, formula_name, page = no_section_cmd.send(:parse_default_args)
      expect(section).to be_nil
      expect(formula_name).to eq("libressl")
      expect(page).to eq("openssl")
    end

    it "does not treat a digit-prefixed formula name as a section" do
      formula_cmd = described_class.new(["7zip", "some-page"])
      section, formula_name, page = formula_cmd.send(:parse_default_args)
      expect(section).to be_nil
      expect(formula_name).to eq("7zip")
      expect(page).to eq("some-page")
    end

    it "defaults page to formula name when only formula is given" do
      formula_only_cmd = described_class.new(["curl"])
      section, formula_name, page = formula_only_cmd.send(:parse_default_args)
      expect(section).to be_nil
      expect(formula_name).to eq("curl")
      expect(page).to eq("curl")
    end
  end

  describe "#formula_binaries" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "returns sorted executable names from bin and sbin" do
      (tmpdir/"bin").mkpath
      FileUtils.touch(tmpdir/"bin/openssl")
      FileUtils.touch(tmpdir/"bin/c_rehash")
      (tmpdir/"sbin").mkpath
      FileUtils.touch(tmpdir/"sbin/ocspcheck")

      result = cmd.send(:formula_binaries, tmpdir)
      expect(result).to eq(["c_rehash", "ocspcheck", "openssl"])
    end

    it "includes symlinks" do
      (tmpdir/"bin").mkpath
      FileUtils.touch(tmpdir/"bin/gawk")
      FileUtils.ln_sf(tmpdir/"bin/gawk", tmpdir/"bin/awk")

      result = cmd.send(:formula_binaries, tmpdir)
      expect(result).to include("awk", "gawk")
    end

    it "returns empty when no bin or sbin exists" do
      expect(cmd.send(:formula_binaries, tmpdir)).to eq([])
    end
  end

  describe "#all_formula_manpages" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "lists all man pages from a formula's keg" do
      man1 = tmpdir/"share/man/man1"
      man1.mkpath
      FileUtils.touch(man1/"openssl.1")
      FileUtils.touch(man1/"c_rehash.1")
      man3 = tmpdir/"share/man/man3"
      man3.mkpath
      FileUtils.touch(man3/"SSL_CTX_new.3")

      formula = instance_double(Formula, opt_prefix: tmpdir)
      allow(Formula).to receive(:[]).with("libressl").and_return(formula)

      result = cmd.send(:all_formula_manpages, "libressl")
      page_names = result.map(&:first)
      expect(page_names).to contain_exactly("SSL_CTX_new.3", "c_rehash.1", "openssl.1")
    end

    it "returns empty for unavailable formulae" do
      allow(Formula).to receive(:[]).with("nonexistent").and_raise(FormulaUnavailableError, "nonexistent")
      expect(cmd.send(:all_formula_manpages, "nonexistent")).to eq([])
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
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      allow(Utils).to receive(:popen_read).and_return(manfile.to_s)

      expect(cmd.send(:find_formula_manpage, "some-formula", "some-formula")).to eq(manfile)
    end

    it "finds a page with a section suffix via glob fallback" do
      man1_dir = tmpdir/"share/man/man1"
      man1_dir.mkpath
      manfile = man1_dir/"openssl.1ssl"
      FileUtils.touch(manfile)

      formula = instance_double(Formula, opt_prefix: tmpdir)
      allow(Formula).to receive(:[]).with("libressl").and_return(formula)
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      allow(Utils).to receive(:popen_read).and_return("")

      expect(cmd.send(:find_formula_manpage, "libressl", "openssl.1ssl")).to eq(manfile)
    end

    it "finds a compressed page via glob fallback" do
      man1_dir = tmpdir/"share/man/man1"
      man1_dir.mkpath
      manfile = man1_dir/"testcmd.1.gz"
      FileUtils.touch(manfile)

      formula = instance_double(Formula, opt_prefix: tmpdir)
      allow(Formula).to receive(:[]).with("test-formula").and_return(formula)
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      allow(Utils).to receive(:popen_read).and_return("")

      expect(cmd.send(:find_formula_manpage, "test-formula", "testcmd.1")).to eq(manfile)
    end

    it "finds a subsection page when given partial section" do
      man1_dir = tmpdir/"share/man/man1"
      man1_dir.mkpath
      manfile = man1_dir/"openssl.1ssl"
      FileUtils.touch(manfile)

      formula = instance_double(Formula, opt_prefix: tmpdir)
      allow(Formula).to receive(:[]).with("openssl@3").and_return(formula)
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      allow(Utils).to receive(:popen_read).and_return("")

      expect(cmd.send(:find_formula_manpage, "openssl@3", "openssl.1")).to eq(manfile)
    end

    it "falls back to base name when section suffix does not match" do
      man1_dir = tmpdir/"share/man/man1"
      man1_dir.mkpath
      manfile = man1_dir/"openssl.1"
      FileUtils.touch(manfile)

      formula = instance_double(Formula, opt_prefix: tmpdir)
      allow(Formula).to receive(:[]).with("libressl").and_return(formula)
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      allow(Utils).to receive(:popen_read).and_return("")

      expect(cmd.send(:find_formula_manpage, "libressl", "openssl.1ssl")).to eq(manfile)
    end

    it "falls back to formula binaries when page matches formula name" do
      man1_dir = tmpdir/"share/man/man1"
      man1_dir.mkpath
      manfile = man1_dir/"openssl.1"
      FileUtils.touch(manfile)
      bin_dir = tmpdir/"bin"
      bin_dir.mkpath
      FileUtils.touch(bin_dir/"openssl")
      FileUtils.touch(bin_dir/"c_rehash")

      formula = instance_double(Formula, opt_prefix: tmpdir)
      allow(Formula).to receive(:[]).with("libressl").and_return(formula)
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      allow(Utils).to receive(:popen_read).and_return("")

      expect(cmd.send(:find_formula_manpage, "libressl", "libressl")).to eq(manfile)
    end

    it "scopes search to a specific section when given" do
      man1_dir = tmpdir/"share/man/man1"
      man1_dir.mkpath
      man3_dir = tmpdir/"share/man/man3"
      man3_dir.mkpath
      man1_file = man1_dir/"openssl.1"
      man3_file = man3_dir/"openssl.3"
      FileUtils.touch(man1_file)
      FileUtils.touch(man3_file)

      formula = instance_double(Formula, opt_prefix: tmpdir)
      allow(Formula).to receive(:[]).with("openssl@3").and_return(formula)
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      allow(Utils).to receive(:popen_read).and_return("")

      expect(cmd.send(:find_formula_manpage, "openssl@3", "openssl", section: "3")).to eq(man3_file)
    end
  end

  describe "#list_manpages" do
    it "lists system and formula man pages" do
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
        ["test-formula", Pathname("/opt/homebrew/opt/test-formula/share/man/man1/testcmd.1")],
      ])

      expect { cmd.send(:list_manpages, "testcmd") }
        .to output(/system:.*testcmd\.1.*test-formula:.*testcmd\.1/m).to_stdout
    end

    it "does not hardcode a man section in the header" do
      allow(cmd).to receive(:collect_manpages).with("openssl").and_return([
        ["openssl@3", Pathname("/opt/homebrew/opt/openssl@3/share/man/man3/openssl.3")],
      ])

      expect { cmd.send(:list_manpages, "openssl") }
        .to output(/openssl found in:/).to_stdout
    end
  end

  describe "#list_all_formula_manpages" do
    it "lists all man pages a formula provides" do
      man1_file = Pathname("/opt/homebrew/opt/libressl/share/man/man1/openssl.1")
      allow(cmd).to receive(:all_formula_manpages).with("libressl").and_return([
        ["openssl.1", man1_file],
      ])

      expect { cmd.send(:list_all_formula_manpages, "libressl") }
        .to output(/libressl provides:.*openssl\.1/m).to_stdout
    end

    it "dies when formula has no man pages" do
      allow(cmd).to receive(:all_formula_manpages).with("empty-formula").and_return([])

      expect { cmd.send(:list_all_formula_manpages, "empty-formula") }
        .to raise_error(SystemExit)
    end
  end

  describe "#interactive_all_formula_manpages" do
    it "prompts and returns the selected formula page" do
      manfile = Pathname("/opt/homebrew/opt/libressl/share/man/man1/openssl.1")
      allow(cmd).to receive(:all_formula_manpages).with("libressl").and_return([
        ["openssl.1", manfile],
      ])
      allow($stdin).to receive(:gets).and_return("1\n")

      expect(cmd.send(:interactive_all_formula_manpages, "libressl")).to eq(manfile)
    end

    it "dies when formula has no man pages" do
      allow(cmd).to receive(:all_formula_manpages).with("empty-formula").and_return([])

      expect { cmd.send(:interactive_all_formula_manpages, "empty-formula") }
        .to raise_error(SystemExit)
    end
  end

  describe "#collect_manpages" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "returns formula and system matches as label/path pairs" do
      sys_man = tmpdir/"sys/man1"
      sys_man.mkpath
      manfile_sys = sys_man/"testcmd.1"
      FileUtils.touch(manfile_sys)

      formula_man = tmpdir/"opt/test-formula/share/man/man1"
      formula_man.mkpath
      manfile_formula = formula_man/"testcmd.1"
      FileUtils.touch(manfile_formula)

      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      stub_const("HOMEBREW_PREFIX", tmpdir)
      allow(Utils).to receive(:popen_read)
        .with("/usr/bin/man", "-w", "-a", "testcmd")
        .and_return("#{manfile_sys}\n")

      result = cmd.send(:collect_manpages, "testcmd")
      expect(result.map(&:first)).to eq(["test-formula", "system"])
    end

    it "returns empty array when no matches exist" do
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      stub_const("HOMEBREW_PREFIX", tmpdir)
      (tmpdir/"opt").mkpath
      allow(Utils).to receive(:popen_read)
        .with("/usr/bin/man", "-w", "-a", "nonexistent")
        .and_return("")

      expect(cmd.send(:collect_manpages, "nonexistent")).to eq([])
    end

    it "deduplicates results by realpath" do
      real_man = tmpdir/"opt/openssl@3/share/man/man1"
      real_man.mkpath
      manfile = real_man/"openssl.1"
      FileUtils.touch(manfile)

      FileUtils.ln_sf(tmpdir/"opt/openssl@3", tmpdir/"opt/openssl")

      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      stub_const("HOMEBREW_PREFIX", tmpdir)
      allow(Utils).to receive(:popen_read)
        .with("/usr/bin/man", "-w", "-a", "openssl")
        .and_return("")

      result = cmd.send(:collect_manpages, "openssl")
      expect(result.length).to eq(1)
    end

    it "finds pages across multiple formula kegs" do
      libressl_man = tmpdir/"opt/libressl/share/man/man1"
      libressl_man.mkpath
      libressl_file = libressl_man/"openssl.1"
      FileUtils.touch(libressl_file)

      openssl_man = tmpdir/"opt/openssl@3/share/man/man1"
      openssl_man.mkpath
      openssl_file = openssl_man/"openssl.1"
      FileUtils.touch(openssl_file)

      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      stub_const("HOMEBREW_PREFIX", tmpdir)
      allow(Utils).to receive(:popen_read)
        .with("/usr/bin/man", "-w", "-a", "openssl")
        .and_return("")

      result = cmd.send(:collect_manpages, "openssl")
      expect(result.map(&:first)).to contain_exactly("libressl", "openssl@3")
    end

    it "labels Homebrew-linked pages by formula when man -wa finds the link" do
      formula_man = tmpdir/"opt/openssl@3/share/man/man1"
      formula_man.mkpath
      formula_file = formula_man/"openssl.1ssl"
      FileUtils.touch(formula_file)

      brew_man = tmpdir/"share/man/man1"
      brew_man.mkpath
      FileUtils.ln_sf(formula_file, brew_man/"openssl.1ssl")

      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      stub_const("HOMEBREW_PREFIX", tmpdir)
      allow(Utils).to receive(:popen_read)
        .with("/usr/bin/man", "-w", "-a", "openssl")
        .and_return("#{brew_man}/openssl.1ssl\n")

      result = cmd.send(:collect_manpages, "openssl")
      labels = result.map(&:first)
      expect(labels).to include("openssl@3")
      expect(labels).not_to include("system")
    end

    it "includes compressed system man pages found by man -wa" do
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      stub_const("HOMEBREW_PREFIX", tmpdir)
      (tmpdir/"opt").mkpath

      gz_file = tmpdir/"sys/man1/testcmd.1.gz"
      (tmpdir/"sys/man1").mkpath
      FileUtils.touch(gz_file)

      allow(Utils).to receive(:popen_read)
        .with("/usr/bin/man", "-w", "-a", "testcmd")
        .and_return("#{gz_file}\n")

      result = cmd.send(:collect_manpages, "testcmd")
      expect(result).to eq([["system", gz_file]])
    end

    it "finds formula pages when name already includes a section suffix" do
      formula_man = tmpdir/"opt/openssl@3/share/man/man1"
      formula_man.mkpath
      manfile = formula_man/"openssl.1ssl"
      FileUtils.touch(manfile)

      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      stub_const("HOMEBREW_PREFIX", tmpdir)
      allow(Utils).to receive(:popen_read)
        .with("/usr/bin/man", "-w", "-a", "openssl.1ssl")
        .and_return("")

      result = cmd.send(:collect_manpages, "openssl.1ssl")
      expect(result).to eq([["openssl@3", manfile]])
    end

    it "skips broken symlinks in formula kegs" do
      formula_man = tmpdir/"opt/broken-pkg/share/man/man1"
      formula_man.mkpath
      FileUtils.ln_sf(tmpdir/"nonexistent", formula_man/"testcmd.1")

      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      stub_const("HOMEBREW_PREFIX", tmpdir)
      allow(Utils).to receive(:popen_read)
        .with("/usr/bin/man", "-w", "-a", "testcmd")
        .and_return("")

      result = cmd.send(:collect_manpages, "testcmd")
      expect(result).to eq([])
    end

    it "finds formulae by binary alias" do
      gawk_man = tmpdir/"opt/gawk/share/man/man1"
      gawk_man.mkpath
      gawk_file = gawk_man/"gawk.1"
      FileUtils.touch(gawk_file)
      gawk_bin = tmpdir/"opt/gawk/bin"
      gawk_bin.mkpath
      FileUtils.touch(gawk_bin/"gawk")
      FileUtils.touch(gawk_bin/"awk")

      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      stub_const("HOMEBREW_PREFIX", tmpdir)
      allow(Utils).to receive(:popen_read)
        .with("/usr/bin/man", "-w", "-a", "awk")
        .and_return("")

      result = cmd.send(:collect_manpages, "awk")
      expect(result.map(&:first)).to include("gawk")
    end
  end

  describe "#interactive_manpage" do
    it "dies when no man pages are found" do
      allow(cmd).to receive(:collect_manpages).with("nonexistent").and_return([])

      expect { cmd.send(:interactive_manpage, "nonexistent") }
        .to raise_error(SystemExit)
    end

    it "shows selector and prompts even for a single match" do
      manfile = Pathname("/usr/share/man/man1/testcmd.1")
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([["system", manfile]])
      allow($stdin).to receive(:gets).and_return("1\n")

      expect(cmd.send(:interactive_manpage, "testcmd")).to eq(manfile)
    end

    it "prompts and returns the selected man page when multiple matches exist" do
      sys_manfile = Pathname("/usr/share/man/man1/testcmd.1")
      formula_manfile = Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", sys_manfile],
        ["pkg", formula_manfile],
      ])
      allow($stdin).to receive(:gets).and_return("1\n")

      expect(cmd.send(:interactive_manpage, "testcmd")).to eq(sys_manfile)
    end

    it "dies on invalid selection" do
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
        ["pkg", Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")],
      ])
      allow($stdin).to receive(:gets).and_return("99\n")

      expect { cmd.send(:interactive_manpage, "testcmd") }
        .to raise_error(SystemExit)
    end

    it "dies when stdin returns nil (EOF)" do
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
        ["pkg", Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")],
      ])
      allow($stdin).to receive(:gets).and_return(nil)

      expect { cmd.send(:interactive_manpage, "testcmd") }
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

  describe "#require_man_cmd" do
    it "returns the man command path" do
      allow(cmd).to receive(:which).with("man").and_return(Pathname("/usr/bin/man"))
      expect(cmd.send(:require_man_cmd)).to eq(Pathname("/usr/bin/man"))
    end

    it "caches the result across multiple calls" do
      expect(cmd).to receive(:which).with("man").once.and_return(Pathname("/usr/bin/man"))
      cmd.send(:require_man_cmd)
      cmd.send(:require_man_cmd)
    end

    it "dies when man is not found" do
      allow(cmd).to receive(:which).with("man").and_return(nil)
      expect { cmd.send(:require_man_cmd) }.to raise_error(SystemExit)
    end
  end

  describe "#run --html validation" do
    it "raises UsageError when --html is used with --find without --interactive" do
      html_find_cmd = described_class.new(["--html", "--find", "openssl"])

      expect { html_find_cmd.run }.to raise_error(UsageError, /--html.*requires.*--interactive/)
    end

    it "raises UsageError when --html is used with --list without --interactive" do
      html_list_cmd = described_class.new(["--html", "--list", "libressl"])

      expect { html_list_cmd.run }.to raise_error(UsageError, /--html.*requires.*--interactive/)
    end
  end
end
