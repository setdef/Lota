# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "callback_helper"
require "lota/cli"
require "tmpdir"

# lota fuse writes a Fledge project for a game folder and runs fledge
# build in it (ADR 002, section 5). Fledge comes from Git and builds an
# app for minutes, so here a fake bundle stands in for Bundler, recording
# each command it is given and running the program after exec, and a fake
# fledge on PATH records its arguments and folder and reports a path, as
# Fledge reports each file it writes. Everything lota fuse writes is real
# and read back as written. The real build is CI's fuse experiment's.
class FuseTest < Minitest::Test
  include CallbackHelper

  PLATFORM = Gem::Platform.new("arm64-darwin")

  def setup
    super
    skip "the fake bundle and fledge are shell scripts" if Gem.win_platform?
    @root = Dir.mktmpdir("lota-fuse-test")
    @game = File.join(@root, "dot.popper")
    @bin = File.join(@root, "bin")
    @log = File.join(@root, "log")
    FileUtils.mkdir_p([@game, @bin])
    write("main.rb", "def Lota.load(_arguments) = nil\n")
    @gem = File.join(@root, "lota-#{Lota::VERSION}-arm64-darwin.gem")
    File.write(@gem, "not really a gem")
    fake("bundle", <<~SH)
      echo "bundle $*" >> "#{@log}"
      if [ "$1" = exec ]; then shift; exec "$@"; fi
    SH
    fake("fledge", <<~SH)
      echo "fledge $* in $(pwd) with $BUNDLE_GEMFILE" >> "#{@log}"
      echo "$3/Dot Popper-arm64-darwin.app"
    SH
    fake("git", "exit 0\n")
    @path = ENV.fetch("PATH", nil)
    ENV["PATH"] = "#{@bin}#{File::PATH_SEPARATOR}#{@path}"
  end

  def teardown
    ENV["PATH"] = @path if @path
    FileUtils.remove_entry(@root) if @root
    super
  end

  def write(name, source)
    path = File.join(@game, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  def fake(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/sh\n#{body}")
    File.chmod(0o755, path)
  end

  def fuse(options = Lota::Fuse::Options.given(out: File.join(@root, "dist")), platform: PLATFORM, gem_file: @gem)
    Lota::Fuse.new(@game, options, platform:, gem_file:, bundle: [File.join(@bin, "bundle")])
  end

  def project(*names)
    File.join(@root, "dist", "fuse-project", *names)
  end

  def read(*names)
    File.read(project(*names))
  end

  def test_a_game_with_no_conf_is_named_and_saved_for_its_folder
    paths = nil
    stdout, = capture_io { paths = fuse.call }

    dist = File.join(@root, "dist")
    assert_equal ["#{dist}/Dot Popper-arm64-darwin.app"], paths
    assert_equal "#{dist}/Dot Popper-arm64-darwin.app\n", stdout
    assert_equal <<~LOG, File.read(@log)
      bundle lock --add-checksums
      bundle install
      bundle exec fledge build --out #{dist}
      fledge build --out #{dist} in #{File.realpath(project)} with #{project('Gemfile')}
    LOG
    assert_equal <<~YAML, read("fledge.yml")
      # Written by lota fuse, which writes it again on every build.
      ---
      name: dot.popper
      kind: windowed
      identifier: com.example.dot
    YAML
    assert_equal "def Lota.load(_arguments) = nil\n", read("game", "dot", "main.rb")
    assert_includes read("main.rb"), %(Lota::Boot.new(File.join(__dir__, "game", "dot"), ARGV, fused: true).call)
  end

  def test_the_project_holds_the_gemfile_entry_script_gem_and_game
    write("conf.rb", <<~RUBY)
      require "colors"
      def Lota.conf(t)
        t.title = "Ignored for the window's"
        t.window.title = COLORS
        t.identity = "DotPopper"
        t.version = "12.0"
      end
    RUBY
    write("colors.rb", "COLORS = 'Dot Popper'\n")
    write("art/dot.png", "png")
    write(".git/HEAD", "ref")
    write(".bundle/config", "BUNDLE_FROZEN: true")
    write("vendor/cache/lota-0.1.2-x64-mingw-ucrt.gem", "a gem for Bundler")
    write("vendor/bundle/gems/x.rb", "a gem Bundler installed")
    write("vendor/sound.ogg", "the game's own")
    write("Gemfile", "gem 'lota'")

    _stdout, stderr = capture_io { fuse(Lota::Fuse::Options.given(out: File.join(@root, "dist"), app_version: "1.2.3", icon: "art/icon")).call }

    assert_equal "lota fuse: the app ships Lota's gem alone; the gems #{File.join(@game, 'Gemfile')} asks for do not reach it.\n",
      stderr

    assert_equal <<~RUBY, read("Gemfile")
      # frozen_string_literal: true

      # Written by lota fuse, which writes it again on every build.
      source "https://rubygems.org"

      gem "lota", "#{Lota::VERSION}"

      group :development do
        gem "fledge", git: "https://github.com/setdef/Fledge", ref: "#{Lota::Fuse::FLEDGE_REF}"
      end
    RUBY
    assert_equal <<~RUBY, read("main.rb")
      # frozen_string_literal: true

      # Written by lota fuse, which writes it again on every build. Starts
      # the game in game/DotPopper as a fused game, as a shipped game starts.
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
      require "lota"
      exit Lota::Boot.new(File.join(__dir__, "game", "DotPopper"), ARGV, fused: true).call
    RUBY
    assert_equal <<~YAML, read("fledge.yml")
      # Written by lota fuse, which writes it again on every build.
      ---
      name: Dot Popper
      kind: windowed
      identifier: com.example.DotPopper
      version: 1.2.3
      icon: game/DotPopper/art/icon
    YAML
    assert_equal "not really a gem", read("vendor", "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem")
    files = Dir.glob("**/*", File::FNM_DOTMATCH, base: project).reject { |name| File.basename(name) == "." }
    assert_equal %W[
      Gemfile
      fledge.yml
      game
      game/DotPopper
      game/DotPopper/Gemfile
      game/DotPopper/art
      game/DotPopper/art/dot.png
      game/DotPopper/colors.rb
      game/DotPopper/conf.rb
      game/DotPopper/main.rb
      game/DotPopper/vendor
      game/DotPopper/vendor/sound.ogg
      main.rb
      vendor
      vendor/cache
      vendor/cache/lota-#{Lota::VERSION}-arm64-darwin.gem
], files.sort
  end

  def test_options_reach_fledge_and_fledge_yml
    options = Lota::Fuse::Options.given(out: File.join(@root, "dist"), sign: "Developer ID Application: Me (TEAM)",
      identifier: "com.me.DotPopper")

    capture_io { fuse(options).call }

    assert_includes File.read(@log), "fledge build --out #{File.join(@root, 'dist')} --sign Developer ID Application: Me (TEAM) in"
    assert_includes read("fledge.yml"), "identifier: com.me.DotPopper\n"
  end

  def test_the_fledge_ref_can_be_named_in_the_environment
    assert_equal Lota::Fuse::FLEDGE_REF, Lota::Fuse.fledge_ref({})
    assert_equal Lota::Fuse::FLEDGE_REF, Lota::Fuse.fledge_ref({ "LOTA_FLEDGE_REF" => " " })
    assert_equal "v0.5.0", Lota::Fuse.fledge_ref({ "LOTA_FLEDGE_REF" => "v0.5.0" })

    ENV["LOTA_FLEDGE_REF"] = "v0.5.0"
    capture_io { fuse.call }

    assert_includes read("Gemfile"), %(ref: "v0.5.0")
  ensure
    ENV.delete("LOTA_FLEDGE_REF")
  end

  def test_an_output_folder_inside_the_game_is_not_copied_into_it
    options = Lota::Fuse::Options.given(out: File.join(@game, "dist"))
    write("dist/old.zip", "an earlier build")

    capture_io { fuse(options).call }

    copied = File.join(@game, "dist", "fuse-project", "game", "dot")
    assert_equal ["main.rb"], Dir.children(copied)
    assert_path_exists File.join(@game, "dist", "old.zip")
  end

  def test_identities_become_folder_names_every_system_takes
    assert_equal "DotPopper", Lota::Fuse.folder_name("DotPopper")
    assert_equal "Dot Popper_ Deluxe_2", Lota::Fuse.folder_name("Dot Popper: Deluxe/2")
    assert_equal "a_b_c_d_e_f_g_h", Lota::Fuse.folder_name("a<b>c\"d\\e|f?g*h")
    assert_equal "tab_", Lota::Fuse.folder_name("tab\t")
    assert_equal "game", Lota::Fuse.folder_name("game. .")
    assert_equal "CON_", Lota::Fuse.folder_name("CON")
    assert_equal "lpt1.txt_", Lota::Fuse.folder_name("lpt1.txt")
    assert_equal "lotagame", Lota::Fuse.folder_name("...")
    assert_equal "app", Lota::Fuse.folder_name("app")
  end

  def test_an_unsafe_identity_saves_under_itself_from_a_safe_folder
    write("conf.rb", "def Lota.conf(t) = (t.identity = 'Dot/Popper')\n")

    capture_io { fuse.call }

    assert_path_exists project("game", "Dot_Popper", "main.rb")
    assert_includes read("fledge.yml"), "identifier: com.example.Dot-Popper\n"
  end

  def test_placeholder_identifiers_are_identifiers_fledge_takes
    assert_equal "com.example.dot-popper", Lota::Fuse.placeholder_identifier("dot_popper")
    assert_equal "com.example.Dot-Popper-2", Lota::Fuse.placeholder_identifier("--Dot Popper! 2--")
    assert_equal "com.example.lotagame", Lota::Fuse.placeholder_identifier("ドット")
    assert_equal 112, Lota::Fuse.placeholder_identifier("a" * 200).length
  end

  def test_a_game_without_main_rb_is_refused
    File.delete(File.join(@game, "main.rb"))

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_equal "#{@game} has no main.rb, so there is no game to fuse.", error.message
    refute_path_exists @log
  end

  def test_a_folder_that_is_not_there_is_refused
    FileUtils.remove_entry(@game)

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_equal "found no game folder at #{@game}.", error.message
  end

  def test_the_game_folder_as_the_output_folder_is_refused
    error = assert_raises(Lota::Fuse::Error) { fuse(Lota::Fuse::Options.given(out: @game)).call }

    assert_includes error.message, "--out can't be the game's own folder"
  end

  def test_a_platform_is_named_as_lota_names_its_gem
    assert_equal "arm64-darwin", Lota::Fuse.platform_name(Gem::Platform.new("arm64-darwin-24"))
    assert_equal "x86_64-linux-gnu", Lota::Fuse.platform_name(Gem::Platform.new("x86_64-linux"))
    assert_equal "x64-mingw-ucrt", Lota::Fuse.platform_name(Gem::Platform.new("x64-mingw-ucrt"))
    assert_nil Lota::Fuse.platform_name(Gem::Platform.new("x86_64-linux-musl"))
  end

  def test_a_platform_lota_has_no_gem_for_is_refused
    %w[x86_64-darwin x86_64-linux-musl x86-mingw32].each do |name|
      error = assert_raises(Lota::Fuse::Error) { fuse(platform: Gem::Platform.new(name)).call }

      assert_includes error.message, "Lota has no gem for #{name}"
    end
    refute_path_exists @log
  end

  def test_no_installed_gem_for_the_platform_is_refused
    platform = Gem::Platform.new("aarch64-mingw-ucrt")
    skip "a Lota gem for #{platform} is installed" unless Gem::Specification.find_all_by_name("lota").none? { |s| s.platform.to_s == platform.to_s }

    error = assert_raises(Lota::Fuse::Error) { fuse(platform:, gem_file: nil).call }

    assert_includes error.message, "found no installed lota-#{Lota::VERSION} gem for aarch64-mingw-ucrt"
  end

  def test_no_git_is_refused_before_anything_is_written
    ENV["PATH"] = File.join(@root, "empty")

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_includes error.message, "found no git on PATH"
    refute_path_exists project
  end

  def test_a_failed_install_of_fledge_says_it_needs_the_network
    fake("bundle", %(echo "bundle $*" >> "#{@log}"; [ "$1" != install ]\n))

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_includes error.message, "Installing Fledge failed (bundle install in #{project})"
    assert_includes error.message, "needs the network"
  end

  def test_a_failed_fledge_build_is_reported
    fake("fledge", "exit 4\n")

    error = assert_raises(Lota::Fuse::Error) { capture_io { fuse.call } }

    assert_equal "fledge build failed (exit status 4).", error.message
  end

  def test_an_error_in_conf_rb_is_reported
    write("conf.rb", "raise 'broken conf'\n")

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_equal "#{File.join(@game, 'conf.rb')} raised RuntimeError: broken conf", error.message
  end

  def test_the_command_reports_refusals_and_takes_its_options
    _stdout, stderr = capture_io do
      assert_raises(SystemExit) { Lota::CLI.call(["fuse", File.join(@root, "missing")]) }
    end
    assert_equal "lota fuse: found no game folder at #{File.join(@root, 'missing')}.\n", stderr

    assert_equal [".", {}], Lota::CLI::Commands::Fuse.parse([])
    assert_equal ["game", { out: "b", sign: "Me (T)", identifier: "com.me.G", app_version: "1.0", icon: "icons/icon" }],
      Lota::CLI::Commands::Fuse.parse(["game", "-o", "b", "--sign=Me (T)", "--identifier", "com.me.G", "--app-version=1.0",
        "--icon", "icons/icon"])
    [
      [["ios"], "cannot build for ios yet"],
      [["--out"], "--out needs a value"],
      [["--bogus"], "unrecognized option '--bogus'"],
      [%w[a b], "takes one game folder, but got a and b"],
].each do |argv, message|
      error = assert_raises(Lota::Fuse::Error) { Lota::CLI::Commands::Fuse.parse(argv) }

      assert_includes error.message, message
    end
  end

  def test_the_command_prints_its_help
    stdout, = capture_io { assert_raises(SystemExit) { Lota::CLI.call(%w[fuse --help]) } }

    assert_includes stdout, "Usage: lota fuse [path] [options]"
    assert_includes stdout, "replace it before you ship"
    assert_includes Lota::CLI.usage, "fuse [path] [options]"
  end
end
