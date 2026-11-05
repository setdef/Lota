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

  PLATFORM = "arm64-darwin"

  def setup
    super
    skip "the fake bundle and fledge are shell scripts" if Gem.win_platform?
    @root = Dir.mktmpdir("lota-fuse-test")
    @game = File.join(@root, "sample.game")
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
      echo "$3/Sample Game-arm64-darwin.app"
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

  def fuse(options = Lota::Fuse.options(out: File.join(@root, "dist")), platform: PLATFORM, gem_file: @gem)
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
    assert_equal ["#{dist}/Sample Game-arm64-darwin.app"], paths
    assert_equal "#{dist}/Sample Game-arm64-darwin.app\n", stdout
    assert_equal <<~LOG, File.read(@log)
      bundle lock --add-checksums
      bundle install
      bundle exec fledge build --out #{dist}
      fledge build --out #{dist} in #{File.realpath(project)} with #{project('Gemfile')}
    LOG
    assert_equal <<~YAML, read("fledge.yml")
      # Written by lota fuse, which writes it again on every build.
      ---
      name: sample.game
      kind: windowed
      identifier: com.example.sample
    YAML
    assert_equal "def Lota.load(_arguments) = nil\n", read("game", "sample", "main.rb")
    assert_includes read("main.rb"), %(Lota::Boot.new(File.join(__dir__, "game", "sample"), ARGV, fused: true).call)
  end

  def test_the_project_holds_the_gemfile_entry_script_gem_and_game
    write("conf.rb", <<~RUBY)
      require "colors"
      def Lota.conf(t)
        t.title = "Ignored for the window's"
        t.window.title = COLORS
        t.identity = "SampleGame"
        t.version = "12.0"
      end
    RUBY
    write("colors.rb", "COLORS = 'Sample Game'\n")
    write("art/dot.png", "png")
    write(".git/HEAD", "ref")
    write(".bundle/config", "BUNDLE_FROZEN: true")
    write("vendor/cache/lota-0.1.2-x64-mingw-ucrt.gem", "a gem for Bundler")
    write("vendor/bundle/gems/x.rb", "a gem Bundler installed")
    write("vendor/sound.ogg", "the game's own")

    _stdout, stderr = capture_io { fuse(Lota::Fuse.options(out: File.join(@root, "dist"), app_version: "1.2.3", icon: "art/icon")).call }

    assert_empty stderr

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
      # the game in game/SampleGame as a fused game, as a shipped game starts.
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
      require "lota"
      exit Lota::Boot.new(File.join(__dir__, "game", "SampleGame"), ARGV, fused: true).call
    RUBY
    assert_equal <<~YAML, read("fledge.yml")
      # Written by lota fuse, which writes it again on every build.
      ---
      name: Sample Game
      kind: windowed
      identifier: com.example.SampleGame
      version: 1.2.3
      icon: game/SampleGame/art/icon
    YAML
    assert_equal "not really a gem", read("vendor", "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem")
    files = Dir.glob("**/*", File::FNM_DOTMATCH, base: project).reject { |name| File.basename(name) == "." }
    assert_equal %W[
      Gemfile
      fledge.yml
      game
      game/SampleGame
      game/SampleGame/art
      game/SampleGame/art/dot.png
      game/SampleGame/colors.rb
      game/SampleGame/conf.rb
      game/SampleGame/main.rb
      game/SampleGame/vendor
      game/SampleGame/vendor/sound.ogg
      main.rb
      vendor
      vendor/cache
      vendor/cache/lota-#{Lota::VERSION}-arm64-darwin.gem
], files.sort
  end

  # A Gemfile.lock as Bundler writes one, for a game that asks for Lota,
  # rainbow (pure Ruby), and fast_blank (a C extension), with Lota from
  # the game's vendor/cache for two platforms.
  LOCKFILE = <<~LOCK
    GEM
      remote: https://rubygems.org/
      specs:
        fast_blank (1.0.1)
        lota (#{Lota::VERSION}-arm64-darwin)
        lota (#{Lota::VERSION}-x86_64-linux-gnu)
        rainbow (3.0.0)

    PLATFORMS
      arm64-darwin
      x86_64-linux-gnu

    DEPENDENCIES
      fast_blank
      lota (= #{Lota::VERSION})
      rainbow (~> 3.0)

    CHECKSUMS
      fast_blank (1.0.1) sha256=269fc30414fed4e6403bc4a49081e1ea539f8b9226e59276ed1efaefabaa17ea
      lota (#{Lota::VERSION}-arm64-darwin)
      lota (#{Lota::VERSION}-x86_64-linux-gnu)
      rainbow (3.0.0) sha256=0000000000000000000000000000000000000000000000000000000000000000

    BUNDLED WITH
      4.0.20
  LOCK

  def write_bundle(lockfile = LOCKFILE)
    write("Gemfile", %(source "https://rubygems.org"\ngem "lota", "#{Lota::VERSION}"\ngem "rainbow", "~> 3.0"\ngem "fast_blank"\n))
    write("Gemfile.lock", lockfile)
    write("vendor/cache/lota-#{Lota::VERSION}-arm64-darwin.gem", "the game's own Lota")
    write("vendor/cache/lota-#{Lota::VERSION}-x86_64-linux-gnu.gem", "Lota for another platform")
    write("vendor/cache/my_gem-1.0.0.gem", "a gem only vendor/cache holds")
    write("vendor/cache/my_git_gem-abc123/my_git_gem.gemspec", "a git gem bundle cache --all keeps")
  end

  def test_a_game_with_a_gemfile_takes_its_gems_and_lockfile_to_the_app
    write_bundle

    _stdout, stderr = capture_io { fuse.call }

    assert_empty stderr
    assert_equal <<~RUBY, read("Gemfile")
      # frozen_string_literal: true

      # Written by lota fuse, which writes it again on every build.
      eval_gemfile "game/sample/Gemfile"

      group :development do
        gem "fledge", git: "https://github.com/setdef/Fledge", ref: "#{Lota::Fuse::FLEDGE_REF}"
      end
    RUBY
    assert_equal LOCKFILE, read("Gemfile.lock")
    assert_equal read("game", "sample", "Gemfile"), File.read(File.join(@game, "Gemfile"))
    assert_equal <<~LOG, File.read(@log).lines.first(3).join
      bundle lock --remove-platform x86_64-linux-gnu
      bundle lock --add-platform arm64-darwin --add-checksums
      bundle install
    LOG
    assert_equal ["lota-#{Lota::VERSION}-arm64-darwin.gem", "my_gem-1.0.0.gem", "my_git_gem-abc123"],
      Dir.children(project("vendor", "cache")).sort
    assert_equal "the game's own Lota", read("vendor", "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem")
    assert_equal "a git gem bundle cache --all keeps", read("vendor", "cache", "my_git_gem-abc123", "my_git_gem.gemspec")
    refute_path_exists project("game", "sample", "vendor", "cache")
  end

  def test_a_game_whose_gemfile_does_not_ask_for_lota_gets_it_from_the_project
    lockfile = LOCKFILE.gsub(/^ +lota .*\n/, "").sub("x86_64-linux-gnu\n", "ruby\n")
    write("Gemfile", %(source "https://rubygems.org"\ngem "rainbow"\n))
    write("Gemfile.lock", lockfile)

    capture_io { fuse.call }

    assert_includes read("Gemfile"), %(eval_gemfile "game/sample/Gemfile"\n\ngem "lota", "#{Lota::VERSION}"\n\ngroup :development do\n)
    assert_equal ["bundle lock --add-platform arm64-darwin --add-checksums\n", "bundle install\n"], File.read(@log).lines.first(2)
    assert_equal ["lota-#{Lota::VERSION}-arm64-darwin.gem"], Dir.children(project("vendor", "cache"))
    assert_equal "not really a gem", read("vendor", "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem")
  end

  def test_a_gemfile_without_a_lockfile_is_refused
    write("Gemfile", "gem 'rainbow'\n")

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_equal "#{File.join(@game, 'Gemfile')} has no Gemfile.lock beside it, so lota fuse can't tell which versions of its " \
      "gems the game runs with. Run bundle install in #{@game}, then fuse again.", error.message
    refute_path_exists project
  end

  def test_a_lockfile_without_this_platform_is_refused
    write_bundle

    error = assert_raises(Lota::Fuse::Error) { fuse(platform: "x64-mingw-ucrt").call }

    assert_equal "#{File.join(@game, 'Gemfile.lock')} locks no gems for x64-mingw-ucrt, the platform this app is built for. " \
      "Run bundle lock --add-platform x64-mingw-ucrt in #{@game}, with each gem that platform needs in its vendor/cache, " \
      "then fuse again.", error.message
    refute_path_exists project
  end

  def test_a_lockfile_with_another_lota_is_refused
    write_bundle(LOCKFILE.gsub("lota (#{Lota::VERSION}", "lota (0.0.9"))

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_equal "#{File.join(@game, 'Gemfile.lock')} locks lota 0.0.9, and this is lota fuse #{Lota::VERSION}. Fuse the game " \
      "with the Lota it locks, or move it to #{Lota::VERSION}: put lota-#{Lota::VERSION}-arm64-darwin.gem in its vendor/cache " \
      "and run bundle update lota in #{@game}.", error.message
    refute_path_exists project
  end

  def test_a_failed_install_of_the_games_gems_says_what_a_compiler_needs
    write_bundle
    fake("bundle", %(echo "bundle $*" >> "#{@log}"; [ "$1" != install ]\n))

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_equal "Installing the game's gems and Fledge failed (bundle install in #{project}). Bundler says above which gem " \
      "and why. A gem with a C extension compiles on this computer, which needs a C compiler: on macOS, Xcode's command line " \
      "tools (xcode-select --install); on Linux, a C compiler and make (sudo apt install build-essential on Debian and Ubuntu); " \
      "on Windows, RubyInstaller's MSYS2 tools (ridk install). lota fuse also needs the network, to fetch Fledge from " \
      "https://github.com/setdef/Fledge at #{Lota::Fuse::FLEDGE_REF}.", error.message
  end

  def test_a_lockfile_is_read_as_bundler_writes_it
    locked = Lota::Fuse::Lockfile.parse(LOCKFILE.sub("  fast_blank\n", "  fast_blank!\n"))

    assert_equal %w[arm64-darwin x86_64-linux-gnu], locked.platforms
    assert_equal %w[fast_blank lota rainbow], locked.dependencies
    assert_equal [Lota::VERSION], locked.versions("lota")
    assert_equal ["3.0.0"], locked.versions("rainbow")
    assert_empty locked.versions("fledge")
    assert locked.depends_on?("lota")
    refute locked.depends_on?("fledge")
    assert locked.covers?("arm64-darwin")
    refute locked.covers?("aarch64-linux-gnu")
    assert_equal ["x86_64-linux-gnu"], locked.other_platforms("arm64-darwin")
    assert_equal ["lota-#{Lota::VERSION}-x86_64-linux-gnu.gem"], locked.other_builds("arm64-darwin")
    assert_equal ["lota-#{Lota::VERSION}-arm64-darwin.gem"], locked.other_builds("x86_64-linux-gnu")
  end

  def test_a_lockfile_covers_a_platform_by_any_name_rubygems_matches_and_by_ruby
    versioned = Lota::Fuse::Lockfile.parse("PLATFORMS\n  arm64-darwin-24\n  x86_64-linux\n  java\n")

    assert versioned.covers?("arm64-darwin")
    assert versioned.covers?("x86_64-linux-gnu")
    refute versioned.covers?("x64-mingw-ucrt")
    assert_equal %w[x86_64-linux java], versioned.other_platforms("arm64-darwin")
    assert Lota::Fuse::Lockfile.parse("PLATFORMS\n  ruby\n").covers?("x64-mingw-ucrt")
    assert_empty Lota::Fuse::Lockfile.parse("PLATFORMS\n  ruby\n  x64-mingw-ucrt").other_platforms("x64-mingw-ucrt")
  end

  def test_options_reach_fledge_and_fledge_yml
    options = Lota::Fuse.options(out: File.join(@root, "dist"), sign: "Developer ID Application: Me (TEAM)",
      identifier: "com.example.SampleGame")

    capture_io { fuse(options).call }

    assert_includes File.read(@log), "fledge build --out #{File.join(@root, 'dist')} --sign Developer ID Application: Me (TEAM) in"
    assert_includes read("fledge.yml"), "identifier: com.example.SampleGame\n"
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
    options = Lota::Fuse.options(out: File.join(@game, "dist"))
    write("dist/old.zip", "an earlier build")

    capture_io { fuse(options).call }

    copied = File.join(@game, "dist", "fuse-project", "game", "sample")
    assert_equal ["main.rb"], Dir.children(copied)
    assert_path_exists File.join(@game, "dist", "old.zip")
  end

  def test_identities_become_folder_names_every_system_takes
    assert_equal "SampleGame", Lota::Fuse.folder_name("SampleGame")
    assert_equal "Sample Game_ Deluxe_2", Lota::Fuse.folder_name("Sample Game: Deluxe/2")
    assert_equal "a_b_c_d_e_f_g_h", Lota::Fuse.folder_name("a<b>c\"d\\e|f?g*h")
    assert_equal "tab_", Lota::Fuse.folder_name("tab\t")
    assert_equal "game", Lota::Fuse.folder_name("game. .")
    assert_equal "CON_", Lota::Fuse.folder_name("CON")
    assert_equal "lpt1.txt_", Lota::Fuse.folder_name("lpt1.txt")
    assert_equal "lotagame", Lota::Fuse.folder_name("...")
    assert_equal "app", Lota::Fuse.folder_name("app")
  end

  def test_an_unsafe_identity_saves_under_itself_from_a_safe_folder
    write("conf.rb", "def Lota.conf(t) = (t.identity = 'Sample/Game')\n")

    capture_io { fuse.call }

    assert_path_exists project("game", "Sample_Game", "main.rb")
    assert_includes read("fledge.yml"), "identifier: com.example.Sample-Game\n"
  end

  def test_placeholder_identifiers_are_identifiers_fledge_takes
    assert_equal "com.example.sample-game", Lota::Fuse.placeholder_identifier("sample_game")
    assert_equal "com.example.Sample-Game-2", Lota::Fuse.placeholder_identifier("--Sample Game! 2--")
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
    error = assert_raises(Lota::Fuse::Error) { fuse(Lota::Fuse.options(out: @game)).call }

    assert_includes error.message, "--out can't be the game's own folder"
  end

  def test_a_platform_is_named_as_lota_names_its_gem
    assert_equal "arm64-darwin", Lota::Fuse.platform_name("arm64-darwin-24")
    assert_equal "x86_64-linux-gnu", Lota::Fuse.platform_name("x86_64-linux")
    assert_equal "aarch64-linux-gnu", Lota::Fuse.platform_name("aarch64-linux-gnu")
    assert_equal "x64-mingw-ucrt", Lota::Fuse.platform_name("x64-mingw-ucrt")
    assert_nil Lota::Fuse.platform_name("x86_64-linux-musl")
    assert_nil Lota::Fuse.platform_name("x86_64-darwin-24")
    assert_equal Gem::Platform.local.to_s, Lota::Fuse.this_platform
  end

  def test_a_platform_lota_has_no_gem_for_is_refused
    %w[x86_64-darwin x86_64-linux-musl x86-mingw32].each do |name|
      error = assert_raises(Lota::Fuse::Error) { fuse(platform: name).call }

      assert_includes error.message, "Lota has no gem for #{name}"
    end
    refute_path_exists @log
  end

  # RubyGems keeps each gem file it installs in the cache folder of the
  # folder it installed it in, which is where lota fuse takes Lota's from.
  def test_the_installed_gem_comes_from_rubygems_cache
    with_gem_path do |home|
      error = assert_raises(Lota::Fuse::Error) { fuse(gem_file: nil).call }
      assert_includes error.message, "found no installed lota-#{Lota::VERSION} gem for arm64-darwin"

      cached = File.join(home, "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem")
      FileUtils.mkdir_p(File.dirname(cached))
      File.write(cached, "the installed gem")
      File.write(File.join(home, "cache", "lota-#{Lota::VERSION}-x64-mingw-ucrt.gem"), "another platform's")

      assert_equal cached, Lota::Fuse.installed_gem("arm64-darwin-24")
      capture_io { fuse(gem_file: nil).call }

      assert_equal "the installed gem", read("vendor", "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem")
    end
  end

  def with_gem_path
    home = File.join(@root, "gems")
    previous = { "GEM_HOME" => Gem.dir, "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR) }
    Gem.paths = { "GEM_HOME" => home, "GEM_PATH" => home }
    yield home
  ensure
    Gem.paths = previous if previous
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
    assert_equal ["game", { out: "b", sign: "Me (T)", identifier: "com.example.G", app_version: "1.0", icon: "icons/icon" }],
      Lota::CLI::Commands::Fuse.parse([
        "game",
        "-o",
        "b",
        "--sign=Me (T)",
        "--identifier",
        "com.example.G",
        "--app-version=1.0",
        "--icon",
        "icons/icon",
])
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
