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

    it "returns sorted entry names from bin and sbin" do
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

      result = cmd.send(:all_formula_manpages, formula)
      page_names = result.map(&:first)
      expect(page_names).to contain_exactly("SSL_CTX_new.3", "c_rehash.1", "openssl.1")
    end

    it "returns empty when man directory does not exist" do
      formula = instance_double(Formula, opt_prefix: tmpdir)
      expect(cmd.send(:all_formula_manpages, formula)).to eq([])
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
      opt_prefix = Pathname("/opt/homebrew/opt/libressl")
      mock_formula = instance_double(Formula, opt_prefix:)
      allow(opt_prefix).to receive(:exist?).and_return(true)
      allow(Formula).to receive(:[]).with("libressl").and_return(mock_formula)
      allow(cmd).to receive(:all_formula_manpages).with(mock_formula).and_return([
        ["openssl.1", man1_file],
      ])

      expect { cmd.send(:list_all_formula_manpages, "libressl") }
        .to output(/libressl provides:.*openssl\.1/m).to_stdout
    end

    it "dies when formula has no man pages" do
      opt_prefix = Pathname("/opt/homebrew/opt/empty-formula")
      mock_formula = instance_double(Formula, opt_prefix:)
      allow(opt_prefix).to receive(:exist?).and_return(true)
      allow(Formula).to receive(:[]).with("empty-formula").and_return(mock_formula)
      allow(cmd).to receive(:all_formula_manpages).with(mock_formula).and_return([])

      expect { cmd.send(:list_all_formula_manpages, "empty-formula") }
        .to raise_error(SystemExit)
    end
  end

  describe "pager behavior" do
    before do
      allow(Homebrew::EnvConfig).to receive(:bat?).and_return(false)
    end

    it "outputs directly when stdout is not a TTY" do
      allow($stdout).to receive(:tty?).and_return(false)
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
      ])

      expect { cmd.send(:list_manpages, "testcmd") }
        .to output(/testcmd found in:/).to_stdout
    end

    it "skips pager when output fits in the terminal" do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(Tty).to receive(:height).and_return(40)
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
      ])

      expect(IO).not_to receive(:popen)

      expect { cmd.send(:list_manpages, "testcmd") }
        .to output(/testcmd found in:/).to_stdout
    end

    it "skips pager when output exactly fills the terminal height" do
      allow($stdout).to receive(:tty?).and_return(true)
      # 2 results + 1 header = 3 lines; height = 3 → exact fit, pager skipped
      allow(Tty).to receive(:height).and_return(3)
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
        ["pkg", Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")],
      ])

      expect(IO).not_to receive(:popen)

      expect { cmd.send(:list_manpages, "testcmd") }
        .to output(/testcmd found in:/).to_stdout
    end

    it "pipes output through a pager when output exceeds terminal height" do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(Tty).to receive(:height).and_return(2)
      pager_io = StringIO.new
      allow(IO).to receive(:popen).with("less -R", "w").and_yield(pager_io)
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
        ["pkg", Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")],
      ])

      cmd.send(:list_manpages, "testcmd")

      expect(pager_io.string).to include("system:")
    end

    it "respects the PAGER environment variable" do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(Tty).to receive(:height).and_return(2)
      pager_io = StringIO.new
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PAGER").and_return("more")
      allow(IO).to receive(:popen).with("more", "w").and_yield(pager_io)
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
        ["pkg", Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")],
      ])

      cmd.send(:list_manpages, "testcmd")

      expect(pager_io.string).to include("system:")
    end

    it "prefers bat when HOMEBREW_BAT is set" do
      allow(Homebrew::EnvConfig).to receive_messages(
        bat?:            true,
        bat_config_path: "/custom/bat.conf",
        bat_theme:       "TwoDark",
      )
      allow(cmd).to receive(:which).with("bat").and_return(Pathname("/usr/local/bin/bat"))
      allow($stdout).to receive(:tty?).and_return(true)
      allow(Tty).to receive(:height).and_return(2)
      pager_io = StringIO.new
      allow(IO).to receive(:popen).with("/usr/local/bin/bat", "w").and_yield(pager_io)
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
        ["pkg", Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")],
      ])
      old_bat_config = ENV.fetch("BAT_CONFIG_PATH", nil)
      old_bat_theme = ENV.fetch("BAT_THEME", nil)

      cmd.send(:list_manpages, "testcmd")

      expect(pager_io.string).to include("system:")
      expect(ENV.fetch("BAT_CONFIG_PATH", nil)).to eq("/custom/bat.conf")
      expect(ENV.fetch("BAT_THEME", nil)).to eq("TwoDark")
    ensure
      ENV["BAT_CONFIG_PATH"] = old_bat_config
      ENV["BAT_THEME"] = old_bat_theme
    end

    it "handles EPIPE gracefully when user quits pager early" do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(Tty).to receive(:height).and_return(2)
      allow(IO).to receive(:popen).with("less -R", "w").and_raise(Errno::EPIPE)
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
        ["pkg", Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")],
      ])

      expect { cmd.send(:list_manpages, "testcmd") }.not_to raise_error
    end
  end

  describe "#interactive_all_formula_manpages" do
    before { allow(cmd).to receive(:which).with("fzf").and_return(nil) }

    it "prompts and returns the selected formula page" do
      manfile = Pathname("/opt/homebrew/opt/libressl/share/man/man1/openssl.1")
      opt_prefix = Pathname("/opt/homebrew/opt/libressl")
      mock_formula = instance_double(Formula, opt_prefix:)
      allow(opt_prefix).to receive(:exist?).and_return(true)
      allow(Formula).to receive(:[]).with("libressl").and_return(mock_formula)
      allow(cmd).to receive(:all_formula_manpages).with(mock_formula).and_return([
        ["openssl.1", manfile],
      ])
      allow($stdin).to receive(:gets).and_return("1\n")

      expect(cmd.send(:interactive_all_formula_manpages, "libressl")).to eq(manfile)
    end

    it "returns the last item when the upper boundary is selected" do
      page1 = Pathname("/opt/homebrew/opt/libressl/share/man/man1/openssl.1")
      page2 = Pathname("/opt/homebrew/opt/libressl/share/man/man1/c_rehash.1")
      opt_prefix = Pathname("/opt/homebrew/opt/libressl")
      mock_formula = instance_double(Formula, opt_prefix:)
      allow(opt_prefix).to receive(:exist?).and_return(true)
      allow(Formula).to receive(:[]).with("libressl").and_return(mock_formula)
      allow(cmd).to receive(:all_formula_manpages).with(mock_formula).and_return([
        ["openssl.1", page1],
        ["c_rehash.1", page2],
      ])
      allow($stdin).to receive(:gets).and_return("2\n")

      expect(cmd.send(:interactive_all_formula_manpages, "libressl")).to eq(page2)
    end

    it "dies on empty input" do
      manfile = Pathname("/opt/homebrew/opt/libressl/share/man/man1/openssl.1")
      opt_prefix = Pathname("/opt/homebrew/opt/libressl")
      mock_formula = instance_double(Formula, opt_prefix:)
      allow(opt_prefix).to receive(:exist?).and_return(true)
      allow(Formula).to receive(:[]).with("libressl").and_return(mock_formula)
      allow(cmd).to receive(:all_formula_manpages).with(mock_formula).and_return([
        ["openssl.1", manfile],
      ])
      allow($stdin).to receive(:gets).and_return("\n")

      expect { cmd.send(:interactive_all_formula_manpages, "libressl") }
        .to raise_error(SystemExit)
    end

    it "dies when stdin returns nil (EOF)" do
      manfile = Pathname("/opt/homebrew/opt/libressl/share/man/man1/openssl.1")
      opt_prefix = Pathname("/opt/homebrew/opt/libressl")
      mock_formula = instance_double(Formula, opt_prefix:)
      allow(opt_prefix).to receive(:exist?).and_return(true)
      allow(Formula).to receive(:[]).with("libressl").and_return(mock_formula)
      allow(cmd).to receive(:all_formula_manpages).with(mock_formula).and_return([
        ["openssl.1", manfile],
      ])
      allow($stdin).to receive(:gets).and_return(nil)

      expect { cmd.send(:interactive_all_formula_manpages, "libressl") }
        .to raise_error(SystemExit)
    end

    it "dies when formula is not installed" do
      opt_prefix = Pathname("/opt/homebrew/opt/libressl")
      mock_formula = instance_double(Formula, opt_prefix:)
      allow(opt_prefix).to receive(:exist?).and_return(false)
      allow(Formula).to receive(:[]).with("libressl").and_return(mock_formula)

      expect { cmd.send(:interactive_all_formula_manpages, "libressl") }
        .to raise_error(SystemExit)
    end

    it "dies when formula is unavailable" do
      allow(Formula).to receive(:[]).with("nonexistent").and_raise(FormulaUnavailableError, "nonexistent")

      expect { cmd.send(:interactive_all_formula_manpages, "nonexistent") }
        .to raise_error(SystemExit)
    end

    it "dies when formula has no man pages" do
      opt_prefix = Pathname("/opt/homebrew/opt/empty-formula")
      mock_formula = instance_double(Formula, opt_prefix:)
      allow(opt_prefix).to receive(:exist?).and_return(true)
      allow(Formula).to receive(:[]).with("empty-formula").and_return(mock_formula)
      allow(cmd).to receive(:all_formula_manpages).with(mock_formula).and_return([])

      expect { cmd.send(:interactive_all_formula_manpages, "empty-formula") }
        .to raise_error(SystemExit)
    end
  end

  describe "#interactive_select_fzf" do
    it "delegates to fzf and returns the selected file" do
      manfile = Pathname("/usr/share/man/man1/testcmd.1")
      choices = [["system", manfile], ["pkg", Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")]]
      pipe = instance_double(IO)
      allow(IO).to receive(:popen).with(array_including("/usr/bin/fzf"), "r+").and_yield(pipe)
      allow(pipe).to receive(:write)
      allow(pipe).to receive(:close_write)
      allow(pipe).to receive(:read).and_return("  1) system: /usr/share/man/man1/testcmd.1")

      result = cmd.send(:interactive_select_fzf, choices, header:   "test:",
                                                          fzf_path: Pathname("/usr/bin/fzf")) do |label, file, i|
        "  #{i + 1}) #{label}: #{file}"
      end

      expect(result).to eq(manfile)
    end

    it "exits cleanly when fzf returns no selection" do
      choices = [["system", Pathname("/usr/share/man/man1/testcmd.1")]]
      pipe = instance_double(IO)
      allow(IO).to receive(:popen).with(array_including("/usr/bin/fzf"), "r+").and_yield(pipe)
      allow(pipe).to receive(:write)
      allow(pipe).to receive(:close_write)
      allow(pipe).to receive(:read).and_return("")

      expect do
        cmd.send(:interactive_select_fzf, choices, header:   "test:",
                                                   fzf_path: Pathname("/usr/bin/fzf")) do |label, file, i|
          "  #{i + 1}) #{label}: #{file}"
        end
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    it "prints 'No selection made.' to stderr when --verbose and fzf returns no selection" do
      verbose_cmd = described_class.new(["some-formula", "--verbose"])
      choices = [["system", Pathname("/usr/share/man/man1/testcmd.1")]]
      pipe = instance_double(IO)
      allow(IO).to receive(:popen).with(array_including("/usr/bin/fzf"), "r+").and_yield(pipe)
      allow(pipe).to receive(:write)
      allow(pipe).to receive(:close_write)
      allow(pipe).to receive(:read).and_return("")

      expect($stderr).to receive(:puts).with("No selection made.")
      expect do
        verbose_cmd.send(:interactive_select_fzf, choices, header:   "test:",
                                                           fzf_path: Pathname("/usr/bin/fzf")) do |label, file, i|
          "  #{i + 1}) #{label}: #{file}"
        end
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    it "writes candidate lines to fzf stdin and closes write end" do
      manfile = Pathname("/usr/share/man/man1/testcmd.1")
      choices = [["system", manfile]]
      pipe = instance_double(IO)
      allow(IO).to receive(:popen).with(array_including("/usr/bin/fzf"), "r+").and_yield(pipe)
      allow(pipe).to receive(:read).and_return("  1) system: /usr/share/man/man1/testcmd.1")

      expect(pipe).to receive(:write).with("  1) system: /usr/share/man/man1/testcmd.1")
      expect(pipe).to receive(:close_write)

      cmd.send(:interactive_select_fzf, choices, header:   "test:",
                                                 fzf_path: Pathname("/usr/bin/fzf")) do |label, file, i|
        "  #{i + 1}) #{label}: #{file}"
      end
    end
  end

  describe "#interactive_select_paged" do
    it "reads from stdin in non-TTY mode" do
      manfile = Pathname("/usr/share/man/man1/testcmd.1")
      choices = [["system", manfile]]
      allow($stdin).to receive(:gets).and_return("1\n")

      result = cmd.send(:interactive_select_paged, choices, header: "test:") do |label, file, i|
        "  #{i + 1}) #{label}: #{file}"
      end

      expect(result).to eq(manfile)
    end

    it "dies on invalid selection in non-TTY mode" do
      choices = [["system", Pathname("/usr/share/man/man1/testcmd.1")]]
      allow($stdin).to receive(:gets).and_return("99\n")

      expect do
        cmd.send(:interactive_select_paged, choices, header: "test:") do |label, file, i|
          "  #{i + 1}) #{label}: #{file}"
        end
      end.to raise_error(SystemExit)
    end

    it "exits with error on EOF in non-TTY mode" do
      choices = [["system", Pathname("/usr/share/man/man1/testcmd.1")]]
      allow($stdin).to receive(:gets).and_return(nil)

      expect do
        cmd.send(:interactive_select_paged, choices, header: "test:") do |label, file, i|
          "  #{i + 1}) #{label}: #{file}"
        end
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end

    it "exits 1 silently on EOF in non-TTY mode when quiet" do
      quiet_cmd = described_class.new(["some-formula", "--quiet"])
      choices = [["system", Pathname("/usr/share/man/man1/testcmd.1")]]
      allow($stdin).to receive(:gets).and_return(nil)
      expect($stderr).not_to receive(:puts)

      expect do
        quiet_cmd.send(:interactive_select_paged, choices, header: "test:") do |label, file, i|
          "  #{i + 1}) #{label}: #{file}"
        end
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end

    context "when stdout is a TTY" do
      before { allow($stdout).to receive(:tty?).and_return(true) }

      it "pages the list and reads selection from /dev/tty" do
        manfile = Pathname("/usr/share/man/man1/testcmd.1")
        choices = [["system", manfile]]
        tty_io = StringIO.new("1\n")
        allow(File).to receive(:open).with("/dev/tty", "r").and_yield(tty_io)
        allow(cmd).to receive(:page_list)

        result = cmd.send(:interactive_select_paged, choices, header: "test:") do |label, file, i|
          "  #{i + 1}) #{label}: #{file}"
        end

        expect(result).to eq(manfile)
      end

      it "re-pages the list when user enters 'l'" do
        manfile = Pathname("/usr/share/man/man1/testcmd.1")
        choices = [["system", manfile]]
        tty_io = StringIO.new("l\n1\n")
        allow(File).to receive(:open).with("/dev/tty", "r").and_yield(tty_io)
        # Initial page + re-page on 'l' = 2 calls
        expect(cmd).to receive(:page_list).twice

        result = cmd.send(:interactive_select_paged, choices, header: "test:") do |label, file, i|
          "  #{i + 1}) #{label}: #{file}"
        end

        expect(result).to eq(manfile)
      end

      it "dies on invalid selection via /dev/tty" do
        choices = [["system", Pathname("/usr/share/man/man1/testcmd.1")]]
        tty_io = StringIO.new("99\n")
        allow(File).to receive(:open).with("/dev/tty", "r").and_yield(tty_io)
        allow(cmd).to receive(:page_list)

        expect do
          cmd.send(:interactive_select_paged, choices, header: "test:") do |label, file, i|
            "  #{i + 1}) #{label}: #{file}"
          end
        end.to raise_error(SystemExit)
      end

      it "exits cleanly on EOF from /dev/tty" do
        choices = [["system", Pathname("/usr/share/man/man1/testcmd.1")]]
        tty_io = StringIO.new
        allow(File).to receive(:open).with("/dev/tty", "r").and_yield(tty_io)
        allow(cmd).to receive(:page_list)

        expect do
          cmd.send(:interactive_select_paged, choices, header: "test:") do |label, file, i|
            "  #{i + 1}) #{label}: #{file}"
          end
        end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end

      it "prints 'No selection made.' to stderr when --verbose and /dev/tty reaches EOF" do
        verbose_cmd = described_class.new(["some-formula", "--verbose"])
        choices = [["system", Pathname("/usr/share/man/man1/testcmd.1")]]
        tty_io = StringIO.new
        allow(File).to receive(:open).with("/dev/tty", "r").and_yield(tty_io)
        allow(verbose_cmd).to receive(:page_list)

        expect($stderr).to receive(:puts).with("No selection made.")
        expect do
          verbose_cmd.send(:interactive_select_paged, choices, header: "test:") do |label, file, i|
            "  #{i + 1}) #{label}: #{file}"
          end
        end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end
    end
  end

  describe "#collect_manpages" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "returns formula and system matches as provider/path pairs" do
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

    it "attributes Homebrew-linked pages to their provider formula" do
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
      providers = result.map(&:first)
      expect(providers).to include("openssl@3")
      expect(providers).not_to include("system")
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
    before { allow(cmd).to receive(:which).with("fzf").and_return(nil) }

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

    it "returns the last item when the upper boundary is selected" do
      sys_manfile = Pathname("/usr/share/man/man1/testcmd.1")
      formula_manfile = Pathname("/opt/homebrew/opt/pkg/share/man/man1/testcmd.1")
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", sys_manfile],
        ["pkg", formula_manfile],
      ])
      allow($stdin).to receive(:gets).and_return("2\n")

      expect(cmd.send(:interactive_manpage, "testcmd")).to eq(formula_manfile)
    end

    it "dies on zero selection" do
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
      ])
      allow($stdin).to receive(:gets).and_return("0\n")

      expect { cmd.send(:interactive_manpage, "testcmd") }
        .to raise_error(SystemExit)
    end

    it "dies on empty input" do
      allow(cmd).to receive(:collect_manpages).with("testcmd").and_return([
        ["system", Pathname("/usr/share/man/man1/testcmd.1")],
      ])
      allow($stdin).to receive(:gets).and_return("\n")

      expect { cmd.send(:interactive_manpage, "testcmd") }
        .to raise_error(SystemExit)
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

  describe "#prune_html_tempfiles" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    before { allow(Dir).to receive(:tmpdir).and_return(tmpdir.to_s) }

    after { FileUtils.rm_rf(tmpdir) }

    it "removes brew-man-*.html files older than 24 hours" do
      old_file = tmpdir/"brew-man-old.html"
      old_file.write("stale")
      FileUtils.touch(old_file, mtime: Time.now - (25 * 60 * 60))

      cmd.send(:prune_html_tempfiles)

      expect(old_file.exist?).to be false
    end

    it "preserves brew-man-*.html files newer than 24 hours" do
      recent_file = tmpdir/"brew-man-recent.html"
      recent_file.write("fresh")

      cmd.send(:prune_html_tempfiles)

      expect(recent_file.exist?).to be true
    end

    it "ignores non-matching files in the temp directory" do
      unrelated = tmpdir/"other-file.html"
      unrelated.write("keep me")
      FileUtils.touch(unrelated, mtime: Time.now - (48 * 60 * 60))

      cmd.send(:prune_html_tempfiles)

      expect(unrelated.exist?).to be true
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

  describe "#glob_manpage" do
    let(:tmpdir) { Pathname(Dir.mktmpdir) }

    after { FileUtils.rm_rf(tmpdir) }

    it "finds a numbered man page" do
      man1_dir = tmpdir/"man1"
      man1_dir.mkpath
      manfile = man1_dir/"openssl.1"
      FileUtils.touch(manfile)

      expect(cmd.send(:glob_manpage, tmpdir, "openssl")).to eq(manfile)
    end

    it "finds a compressed man page" do
      man1_dir = tmpdir/"man1"
      man1_dir.mkpath
      manfile = man1_dir/"openssl.1.gz"
      FileUtils.touch(manfile)

      expect(cmd.send(:glob_manpage, tmpdir, "openssl")).to eq(manfile)
    end

    it "finds a subsection man page" do
      man1_dir = tmpdir/"man1"
      man1_dir.mkpath
      manfile = man1_dir/"openssl.1ssl"
      FileUtils.touch(manfile)

      expect(cmd.send(:glob_manpage, tmpdir, "openssl")).to eq(manfile)
    end

    it "finds an exact match page" do
      man1_dir = tmpdir/"man1"
      man1_dir.mkpath
      manfile = man1_dir/"openssl.1ssl"
      FileUtils.touch(manfile)

      expect(cmd.send(:glob_manpage, tmpdir, "openssl.1ssl")).to eq(manfile)
    end

    it "scopes search to a specific section" do
      (tmpdir/"man1").mkpath
      (tmpdir/"man3").mkpath
      FileUtils.touch(tmpdir/"man1/openssl.1")
      man3_file = tmpdir/"man3/openssl.3"
      FileUtils.touch(man3_file)

      expect(cmd.send(:glob_manpage, tmpdir, "openssl", "man3")).to eq(man3_file)
    end

    it "returns nil when no match exists" do
      (tmpdir/"man1").mkpath

      expect(cmd.send(:glob_manpage, tmpdir, "nonexistent")).to be_nil
    end
  end

  describe "#escape_glob" do
    it "escapes asterisks" do
      expect(cmd.send(:escape_glob, "foo*bar")).to eq("foo\\*bar")
    end

    it "escapes question marks" do
      expect(cmd.send(:escape_glob, "foo?bar")).to eq("foo\\?bar")
    end

    it "escapes square brackets" do
      expect(cmd.send(:escape_glob, "foo[0]bar")).to eq("foo\\[0\\]bar")
    end

    it "escapes curly braces" do
      expect(cmd.send(:escape_glob, "foo{a,b}bar")).to eq("foo\\{a,b\\}bar")
    end

    it "escapes backslashes" do
      expect(cmd.send(:escape_glob, 'foo\\bar')).to eq('foo\\\\bar')
    end

    it "escapes multiple metacharacters in combination" do
      expect(cmd.send(:escape_glob, "a*b?c[d]{e}\\f")).to eq("a\\*b\\?c\\[d\\]\\{e\\}\\\\f")
    end

    it "passes through strings without metacharacters" do
      expect(cmd.send(:escape_glob, "openssl.1ssl")).to eq("openssl.1ssl")
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
