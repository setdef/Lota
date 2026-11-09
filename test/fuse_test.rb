# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "callback_helper"
require "json"
require "lota/cli"
require "open3"
require "rubygems/package"
require "tmpdir"

# lota fuse writes a Fledge project for a game folder and runs fledge
# build in it (ADR 002, section 5). Fledge comes from Git and builds an
# app for minutes, so here a fake bundle stands in for Bundler, recording
# each command it is given and running the program after exec, and a fake
# fledge on PATH records its arguments and folder and reports a path, as
# Fledge reports each file it writes. Each records the Gemfile Bundler is
# pointed at. Everything lota fuse writes is real and read back as
# written. One test locks with the real Bundler. The real build is CI's
# fuse experiment's.
#
# Each Lota gem here is a real gem file, with what lota fuse reads from
# the gem it ships, the manifest of its notices and its license texts, as
# NativeGem writes them, and a file that tells one copy from another.
class FuseTest < Minitest::Test
  include CallbackHelper

  PLATFORM = "arm64-darwin"

  ROOT = File.expand_path("..", __dir__)

  # What the manifest of each gem here names: one work compiled into the
  # extension and OpenAL Soft beside it, with its source.
  COMPONENTS = [
    {
"name" => "LÖVE",
"version" => "12.0",
"license" => ["Zlib"],
"copyright" => ["2006-2026 LOVE Development Team"],
"credit" => nil,
"file" => "lib/lota/native.bundle",
"separate" => false,
"source" => nil,
},
    {
"name" => "OpenAL Soft",
"version" => "1.24.3",
"license" => ["LGPL-2.0-or-later"],
"copyright" => ["2009 by Chris Robinson."],
"credit" => nil,
"file" => "lib/lota/frameworks/OpenAL-Soft.framework",
"separate" => true,
"source" => {
"file" => "sources/openal-soft-1.24.3.tar.bz2",
"url" => "https://openal-soft.org/x.tar.bz2",
"sha256" => "ab",
"license" => ["LGPL-2.0-or-later"],
},
},
].freeze

  # Writes a Lota gem for +platform+ at +path+, whose marker.txt holds
  # +marker+, with no manifest if +manifest+ is false.
  def lota_gem(path, marker, platform: PLATFORM, manifest: true)
    Dir.mktmpdir("lota-fuse-gem") do |dir|
      files = { "marker.txt" => marker }
      files["notices.json"] = JSON.generate("components" => COMPONENTS) if manifest
      %w[AGPL-3.0-or-later Zlib].each { |id| files["LICENSES/#{id}.txt"] = File.read(File.join(ROOT, "LICENSES/#{id}.txt")) }
      files["LICENSES/LGPL-2.0-or-later.txt"] = File.read(File.join(ROOT, "ext/lota/licenses/LICENSE-LGPL-2.0-or-later.txt"))
      files.each do |name, content|
        FileUtils.mkdir_p(File.dirname(File.join(dir, name)))
        File.write(File.join(dir, name), content)
      end
      spec = Gem::Specification.new do |gem|
        gem.name = "lota"
        gem.version = Lota::VERSION
        gem.platform = Gem::Platform.new(platform)
        gem.summary = "A Lota gem for lota fuse's tests"
        gem.authors = ["Lota's tests"]
        gem.files = files.keys
      end
      FileUtils.mkdir_p(File.dirname(path))
      Dir.chdir(dir) { Gem::Package.build(spec, true, false, path) }
    end
    path
  end

  # The marker.txt of the Lota gem at +path+.
  def marker(path)
    Dir.mktmpdir("lota-fuse-marker") do |dir|
      Gem::Package.new(path).extract_files(dir, "marker.txt")
      File.read(File.join(dir, "marker.txt"))
    end
  end

  def setup
    super
    skip "the fake bundle and fledge are shell scripts" if Gem.win_platform?
    @root = Dir.mktmpdir("lota-fuse-test")
    @game = File.join(@root, "sample.game")
    @bin = File.join(@root, "bin")
    @log = File.join(@root, "log")
    FileUtils.mkdir_p([@game, @bin])
    write("main.rb", "def Lota.load(_arguments) = nil\n")
    @gem = lota_gem(File.join(@root, "lota-#{Lota::VERSION}-arm64-darwin.gem"), "not really Lota")
    fake("bundle", <<~SH)
      echo "bundle $* with $BUNDLE_GEMFILE" >> "#{@log}"
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

  def tools(*names)
    File.join(@root, "dist", "fuse-tools", *names)
  end

  # The Gemfile lota fuse runs Fledge from, holding Fledge at +ref+.
  def tools_gemfile(ref = Lota::Fuse::FLEDGE_REF)
    <<~RUBY
      # frozen_string_literal: true

      # Written by lota fuse, which writes it again on every build. Fledge
      # runs from this bundle, apart from the project's, so that Bundler
      # installs none of the game's gems and Fledge is none of the app's.
      gem "fledge", git: "https://github.com/setdef/Fledge", ref: "#{ref}"
    RUBY
  end

  def test_a_game_with_no_conf_is_named_and_saved_for_its_folder
    paths = nil
    stdout, = capture_io { paths = fuse.call }

    dist = File.join(@root, "dist")
    assert_equal ["#{dist}/Sample Game-arm64-darwin.app"], paths
    assert_equal "#{dist}/Sample Game-arm64-darwin.app\n", stdout
    assert_equal <<~LOG, File.read(@log)
      bundle lock --add-checksums with #{project('Gemfile')}
      bundle install with #{tools('Gemfile')}
      bundle exec fledge build --out #{dist} with #{tools('Gemfile')}
      fledge build --out #{dist} in #{File.realpath(project)} with #{tools('Gemfile')}
    LOG
    assert_equal tools_gemfile, File.read(tools("Gemfile"))
    assert_equal ["Gemfile"], Dir.children(tools)
    assert_equal <<~YAML, read("fledge.yml")
      # Written by lota fuse, which writes it again on every build.
      ---
      name: sample.game
      kind: windowed
      identifier: com.example.sample
    YAML
    assert_equal "def Lota.load(_arguments) = nil\n", read("game", "sample", "main.rb")
    assert_includes read("main.rb"), %(exit Lota::Boot.new(File.join(__dir__, "game", "sample"), ARGV, fused: true).call)
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
    RUBY
    assert_equal <<~RUBY, read("main.rb")
      # frozen_string_literal: true

      # Written by lota fuse, which writes it again on every build. Starts
      # the game in game/SampleGame as a fused game, as a shipped game starts,
      # which starts again when it restarts, by running this app's program
      # again with the same arguments (Lota::Boot#call).
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
    assert_equal "not really Lota", marker(project("vendor", "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem"))
    files = Dir.glob("**/*", File::FNM_DOTMATCH, base: project).reject { |name| File.basename(name) == "." }
    assert_equal %W[
      Gemfile
      NOTICES.txt
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
    lota_gem(File.join(@game, "vendor/cache/lota-#{Lota::VERSION}-arm64-darwin.gem"), "the game's own Lota")
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
    RUBY
    assert_equal LOCKFILE, read("Gemfile.lock")
    assert_equal read("game", "sample", "Gemfile"), File.read(File.join(@game, "Gemfile"))
    assert_equal <<~LOG, File.read(@log).lines.first(3).join
      bundle lock --remove-platform x86_64-linux-gnu with #{project('Gemfile')}
      bundle lock --add-platform arm64-darwin --add-checksums with #{project('Gemfile')}
      bundle install with #{tools('Gemfile')}
    LOG
    assert_equal ["lota-#{Lota::VERSION}-arm64-darwin.gem", "my_gem-1.0.0.gem", "my_git_gem-abc123"],
      Dir.children(project("vendor", "cache")).sort
    assert_equal "the game's own Lota", marker(project("vendor", "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem"))
    assert_equal "a git gem bundle cache --all keeps", read("vendor", "cache", "my_git_gem-abc123", "my_git_gem.gemspec")
    refute_path_exists project("game", "sample", "vendor", "cache")
  end

  def test_a_game_whose_gemfile_does_not_ask_for_lota_gets_it_from_the_project
    lockfile = LOCKFILE.gsub(/^ +lota .*\n/, "").sub("x86_64-linux-gnu\n", "ruby\n")
    write("Gemfile", %(source "https://rubygems.org"\ngem "rainbow"\n))
    write("Gemfile.lock", lockfile)

    capture_io { fuse.call }

    assert read("Gemfile").end_with?(%(eval_gemfile "game/sample/Gemfile"\n\ngem "lota", "#{Lota::VERSION}"\n))
    assert_equal [
      "bundle lock --add-platform arm64-darwin --add-checksums with #{project('Gemfile')}\n",
      "bundle install with #{tools('Gemfile')}\n",
], File.read(@log).lines.first(2)
    assert_equal ["lota-#{Lota::VERSION}-arm64-darwin.gem"], Dir.children(project("vendor", "cache"))
    assert_equal "not really Lota", marker(project("vendor", "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem"))
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

  # Fledge compiles a gem the app ships that has a C extension, for the
  # app's Ruby, so a failed build of a game with gems says what a compiler
  # needs.
  def test_a_failed_build_of_a_game_with_gems_says_what_a_compiler_needs
    write_bundle
    fake("fledge", "exit 1\n")

    error = assert_raises(Lota::Fuse::Error) { capture_io { fuse.call } }

    assert_equal "fledge build failed (exit status 1). Fledge says above why. A gem with a C extension compiles on this " \
      "computer, which needs a C compiler: on macOS, Xcode's command line tools (xcode-select --install); on Linux, a C " \
      "compiler and make (sudo apt install build-essential on Debian and Ubuntu); on Windows, RubyInstaller's MSYS2 tools " \
      "(ridk install).", error.message
  end

  # A gem with a C extension whose extconf.rb only fails, after it writes
  # +marker+, so that the marker shows whether anything compiled it, as a
  # .gem file at +path+.
  def broken_gem(path, marker)
    Dir.mktmpdir("lota-fuse-broken") do |dir|
      extconf = "ext/broken/extconf.rb"
      FileUtils.mkdir_p(File.join(dir, File.dirname(extconf)))
      File.write(File.join(dir, extconf), "File.write(#{marker.inspect}, 'compiled')\nabort 'broken never compiles'\n")
      spec = Gem::Specification.new do |gem|
        gem.name = "broken"
        gem.version = "1.0.0"
        gem.summary = "A gem lota fuse's tests never compile"
        gem.authors = ["Lota's tests"]
        gem.files = [extconf]
        gem.extensions = [extconf]
      end
      Dir.chdir(dir) { Gem::Package.build(spec, true, false, path) }
    end
    path
  end

  # Runs this Ruby's own Bundler with +arguments+ for +gemfile+, outside
  # the bundle these tests run in, as a developer runs it in a terminal.
  def real_bundle(*, gemfile:)
    env = ENV.keys.grep(/\ABUNDLER?_/).to_h { |key| [key, nil] }.merge("BUNDLE_GEMFILE" => gemfile, "RUBYOPT" => nil)
    output, status = Open3.capture2e(env, RbConfig.ruby, Gem.bin_path("bundler", "bundle"), *,
      chdir: File.dirname(gemfile))

    assert status.success?, output
  end

  # Fledge leaves a game's development and test groups out of the app
  # (Fledge::Bundle::WITHOUT), so compiling them gives the player nothing.
  # Here the real Bundler locks the game, as its developer would, and
  # locks the project, with no gem server to reach: lota fuse then builds
  # with a development gem whose extension can only fail, and nothing ever
  # compiles it.
  def test_a_development_gem_with_an_extension_is_never_compiled
    platform = Lota::Fuse.platform_name(Lota::Fuse.this_platform)
    skip "Lota has no gem for #{Lota::Fuse.this_platform}" unless platform
    marker = File.join(@root, "compiled")
    gem = lota_gem(File.join(@root, "lota-#{Lota::VERSION}-#{platform}.gem"), "the installed Lota", platform:)
    FileUtils.mkdir_p(File.join(@game, "vendor/cache"))
    FileUtils.cp(gem, File.join(@game, "vendor/cache"))
    broken_gem(File.join(@game, "vendor/cache/broken-1.0.0.gem"), marker)
    write("Gemfile", %(gem "lota", "#{Lota::VERSION}"\n\ngroup :development do\n  gem "broken"\nend\n))
    real_bundle("lock", gemfile: File.join(@game, "Gemfile"))
    fake("bundle", <<~SH)
      echo "bundle $* with $BUNDLE_GEMFILE" >> "#{@log}"
      if [ "$BUNDLE_GEMFILE" = "#{project('Gemfile')}" ]; then
        exec "#{RbConfig.ruby}" "#{Gem.bin_path('bundler', 'bundle')}" "$@" >> "#{@log}" 2>&1
      fi
      if [ "$1" = exec ]; then shift; exec "$@"; fi
    SH

    paths = nil
    capture_io { paths = fuse(platform: Lota::Fuse.this_platform, gem_file: gem).call }

    refute_path_exists marker
    assert_equal ["#{File.join(@root, 'dist')}/Sample Game-arm64-darwin.app"], paths
    assert_includes read("Gemfile.lock"), "\n    broken (1.0.0)\n"
    refute_includes File.read(@log), "bundle install with #{project('Gemfile')}"
    assert_includes File.read(@log), "bundle install with #{tools('Gemfile')}"
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

  # The arguments the fake fledge was given, one to an element.
  def fledge_arguments
    File.read(@log).lines.filter_map { |line| line.chomp.delete_prefix("argument: ") if line.start_with?("argument: ") }
  end

  def fake_fledge_listing_arguments
    fake("fledge", <<~SH)
      for argument in "$@"; do echo "argument: $argument" >> "#{@log}"; done
      echo "FLEDGE_SIGN_COMMAND=$FLEDGE_SIGN_COMMAND" >> "#{@log}"
      echo "$3/Sample Game-arm64-darwin.app"
    SH
  end

  def test_notarize_reaches_fledge_with_the_identity_it_notarizes
    fake_fledge_listing_arguments
    options = Lota::Fuse.options(out: File.join(@root, "dist"), sign: "Developer ID Application: Me (TEAM)",
      notarize: "sample-profile")

    capture_io { fuse(options).call }

    signing = ["--sign", "Developer ID Application: Me (TEAM)", "--notarize", "sample-profile"]
    assert_equal ["build", "--out", File.join(@root, "dist"), *signing], fledge_arguments
  end

  def test_a_sign_command_reaches_fledge_as_one_argument
    fake_fledge_listing_arguments
    command = 'signtool sign /fd sha256 /tr "http://timestamp.example.com" %1'

    capture_io { fuse(Lota::Fuse.options(out: File.join(@root, "dist"), sign_command: command)).call }

    assert_equal ["build", "--out", File.join(@root, "dist"), "--sign-command", command], fledge_arguments
  end

  def test_fledge_reads_its_sign_command_from_the_environment_lota_fuse_passes_on
    fake_fledge_listing_arguments
    ENV["FLEDGE_SIGN_COMMAND"] = "sign-it %1"

    capture_io { fuse.call }

    assert_includes File.read(@log).lines, "FLEDGE_SIGN_COMMAND=sign-it %1\n"
    assert_equal ["build", "--out", File.join(@root, "dist")], fledge_arguments
  ensure
    ENV.delete("FLEDGE_SIGN_COMMAND")
  end

  def test_signing_options_fledge_refuses_together_are_refused_before_anything_is_written
    notarize = "--notarize needs --sign IDENTITY, the Developer ID Application identity Apple notarizes"
    [
      [{ sign: "-", sign_command: "sign-it %1" }, "--sign and --sign-command each sign the app; give one of them"],
      [{ notarize: "sample-profile" }, notarize],
      [{ notarize: "sample-profile", sign_command: "sign-it %1" }, notarize],
    ].each do |given, message|
      error = assert_raises(Lota::Fuse::Error) { fuse(Lota::Fuse.options(out: File.join(@root, "dist"), **given)).call }

      assert_equal message, error.message
    end
    refute_path_exists @log
    refute_path_exists project
  end

  def test_the_command_takes_notarize_and_sign_command
    assert_equal ["game", { sign: "Me (T)", notarize: "sample-profile", sign_command: "sign-it /a %1" }],
      Lota::CLI::Commands::Fuse.parse(["game", "--sign", "Me (T)", "--notarize", "sample-profile", "--sign-command=sign-it /a %1"])
    %w[--notarize --sign-command].each do |option|
      error = assert_raises(Lota::Fuse::Error) { Lota::CLI::Commands::Fuse.parse([option]) }

      assert_includes error.message, "#{option} needs a value"
    end
  end

  def test_the_command_exits_with_status_1_for_signing_options_it_refuses
    _stdout, stderr = capture_io do
      error = assert_raises(SystemExit) { Lota::CLI.call(["fuse", @game, "--notarize", "sample-profile"]) }

      assert_equal 1, error.status
    end

    assert_equal "lota fuse: --notarize needs --sign IDENTITY, the Developer ID Application identity Apple notarizes\n", stderr
  end

  def test_the_fledge_ref_can_be_named_in_the_environment
    assert_equal Lota::Fuse::FLEDGE_REF, Lota::Fuse.fledge_ref({})
    assert_equal Lota::Fuse::FLEDGE_REF, Lota::Fuse.fledge_ref({ "LOTA_FLEDGE_REF" => " " })
    assert_equal "v0.5.0", Lota::Fuse.fledge_ref({ "LOTA_FLEDGE_REF" => "v0.5.0" })

    ENV["LOTA_FLEDGE_REF"] = "v0.5.0"
    capture_io { fuse.call }

    assert_equal tools_gemfile("v0.5.0"), File.read(tools("Gemfile"))
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

  # lota fuse writes its project and Fledge's Gemfile anew on every build,
  # so a game in either folder would be lost.
  def test_a_game_inside_the_folders_lota_fuse_writes_is_refused
    %w[fuse-project fuse-tools].each do |folder|
      inside = File.join(@root, "dist", folder, "game")
      FileUtils.mkdir_p(inside)
      File.write(File.join(inside, "main.rb"), "")

      error = assert_raises(Lota::Fuse::Error) { Lota::Fuse.new(inside, Lota::Fuse.options(out: File.join(@root, "dist"))).call }

      assert_includes error.message, "--out can't be the game's own folder"
      assert_path_exists File.join(inside, "main.rb")
    end
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
      lota_gem(cached, "the installed gem")
      File.write(File.join(home, "cache", "lota-#{Lota::VERSION}-x64-mingw-ucrt.gem"), "another platform's")

      assert_equal cached, Lota::Fuse.installed_gem("arm64-darwin-24")
      capture_io { fuse(gem_file: nil).call }

      assert_equal "the installed gem", marker(project("vendor", "cache", "lota-#{Lota::VERSION}-arm64-darwin.gem"))
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

  # The app's notices come from the Lota gem it ships, and name where
  # Fledge puts that gem: in the runtime's gem folder for this Ruby's ABI.
  def test_the_project_holds_the_notices_of_the_lota_gem_it_ships
    capture_io { fuse.call }

    notices = read("NOTICES.txt")
    gem = "lib/ruby/gems/#{RbConfig::CONFIG['ruby_version']}/gems/lota-#{Lota::VERSION}-arm64-darwin"
    assert notices.start_with?("Notices for Lota #{Lota::VERSION} and the libraries it ships\n\n" \
      "lota fuse wrote this file as it built this app for arm64-darwin.")
    assert_includes notices, "Lota #{Lota::VERSION}\n  Copyright 2026 setdef <kerrick@setdef.com>\n" \
      "  License: AGPL-3.0-or-later, the GNU Affero General Public License, version 3 or any later version\n"
    assert_includes notices, "  In this app: #{gem}\n"
    assert_includes notices, "Compiled into Lota's extension, #{gem}/lib/lota/native.bundle:\n\nLÖVE 12.0\n"
    assert_includes notices, "  Source: #{gem}/sources/openal-soft-1.24.3.tar.bz2\n"
    assert_includes notices, "\n==== LGPL-2.0-or-later ====\n"
  end

  # On Windows Fledge's runtime keeps its gems in its ruby folder.
  def test_a_windows_apps_notices_name_the_gem_in_the_runtimes_ruby_folder
    gem = lota_gem(File.join(@root, "lota-#{Lota::VERSION}-x64-mingw-ucrt.gem"), "Windows", platform: "x64-mingw-ucrt")

    capture_io { fuse(platform: "x64-mingw-ucrt", gem_file: gem).call }

    assert_includes read("NOTICES.txt"), "  In this app: ruby\\lib\\ruby\\gems\\#{RbConfig::CONFIG['ruby_version']}\\gems\\" \
      "lota-#{Lota::VERSION}-x64-mingw-ucrt\n"
  end

  # A Lota gem without the manifest gives the app no notices, so lota
  # fuse builds nothing with it.
  def test_a_lota_gem_without_its_notices_is_refused_before_the_build
    lota_gem(@gem, "an older Lota", manifest: false)

    error = assert_raises(Lota::Fuse::Error) { capture_io { fuse.call } }

    assert_equal "lota fuse writes the app's NOTICES.txt from the Lota gem it ships, and lota-#{Lota::VERSION}-arm64-darwin.gem " \
      "cannot give them: the gem has no notices.json. Fuse with a Lota gem that carries its notices.", error.message
    refute_includes File.read(@log), "fledge build"
  end

  def test_no_git_is_refused_before_anything_is_written
    ENV["PATH"] = File.join(@root, "empty")

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_includes error.message, "found no git on PATH"
    refute_path_exists project
  end

  def test_a_failed_install_of_fledge_says_it_needs_the_network
    write_bundle
    fake("bundle", %(echo "bundle $*" >> "#{@log}"; [ "$1" != install ]\n))

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_equal "Installing Fledge failed (bundle install in #{tools}). lota fuse needs the network, to fetch Fledge from " \
      "https://github.com/setdef/Fledge at #{Lota::Fuse::FLEDGE_REF}.", error.message
  end

  # bundle exec names Bundler's setup in RUBYOPT by its full path, and a
  # Bundler command that loads it sets up the Gemfile it names before it
  # can lock or install it.
  def test_the_bundle_lota_fuse_runs_in_stays_out_of_bundlers_commands
    fake("bundle", %(echo "bundle $1 with RUBYOPT=$RUBYOPT" >> "#{@log}"\n))
    previous = ENV.fetch("RUBYOPT", nil)
    ENV["RUBYOPT"] = "-W0 -r/gems/bundler-4.0.22/lib/bundler/setup -rbundler/setup"

    capture_io { fuse.call }

    assert_equal ["bundle lock with RUBYOPT=-W0\n", "bundle install with RUBYOPT=-W0\n", "bundle exec with RUBYOPT=-W0\n"],
      File.read(@log).lines
  ensure
    ENV["RUBYOPT"] = previous
  end

  def test_a_failed_lock_says_bundler_needs_the_gem_servers
    fake("bundle", %(echo "bundle $*" >> "#{@log}"; [ "$1" != lock ]\n))

    error = assert_raises(Lota::Fuse::Error) { fuse.call }

    assert_equal "Locking the project's gems failed (bundle lock --add-checksums in #{project}). Bundler says above why. It " \
      "asks the gem servers the Gemfile names for each gem's checksum, which needs the network.", error.message
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

  def game_files
    Dir.glob("**/*", File::FNM_DOTMATCH, base: project("game", "sample")).select { |name| File.file?(project("game", "sample", name)) }.sort
  end

  def test_exclude_leaves_out_a_folder_whole_and_only_where_it_is_named
    write("server/app.rb", "")
    write("server/deep/more.rb", "")
    write("doc/readme.txt", "")
    write("lib/server/keep.rb", "")

    capture_io { fuse(Lota::Fuse.options(out: File.join(@root, "dist"), exclude: ["server", "doc/"])).call }

    assert_equal %w[lib/server/keep.rb main.rb], game_files
  end

  def test_exclude_with_a_trailing_slash_names_folders_only
    write("doc", "a file named doc")

    capture_io { fuse(Lota::Fuse.options(out: File.join(@root, "dist"), exclude: ["doc/"])).call }

    assert_equal %w[doc main.rb], game_files
  end

  def test_exclude_leaves_out_a_file_and_takes_braces
    write("notes.txt", "")
    write("a.psd", "")
    write("b.xcf", "")
    write("art/c.png", "")

    capture_io { fuse(Lota::Fuse.options(out: File.join(@root, "dist"), exclude: ["notes.txt", "*.{psd,xcf}"])).call }

    assert_equal %w[art/c.png main.rb], game_files
  end

  def test_exclude_reads_double_star_as_fnmatch_does
    write("test/a.rb", "")
    write("test/deep/b.rb", "")
    write("art/raw/c.psd", "")
    write("d.psd", "")
    write("art/e.png", "")

    options = Lota::Fuse.options(out: File.join(@root, "dist"), exclude: ["test/**", "**/*.psd"])
    capture_io { fuse(options).call }

    assert_equal %w[art/e.png main.rb], game_files
    assert_path_exists project("game", "sample", "test")
  end

  def test_exclude_matches_dotfiles_with_a_star
    write(".DS_Store", "")
    write("assets/.hidden", "")
    write("assets/x.png", "")
    write("keep/.kept", "")

    options = Lota::Fuse.options(out: File.join(@root, "dist"), exclude: [".DS_Store", "assets/*"])
    capture_io { fuse(options).call }

    assert_equal %w[keep/.kept main.rb], game_files
  end

  def test_exclude_says_what_it_left_out
    write("server/a.rb", "")
    write("notes.txt", "")

    stdout, stderr = capture_io { fuse(Lota::Fuse.options(out: File.join(@root, "dist"), exclude: %w[server notes.txt])).call }

    assert_empty stderr
    assert_includes stdout, "Left out 2 paths of the game: notes.txt, server\n"
  end

  def test_exclude_says_nothing_when_it_is_not_given
    stdout, = capture_io { fuse.call }

    refute_includes stdout, "Left out"
  end

  def test_exclude_warns_of_a_pattern_that_matches_nothing_and_builds_anyway
    write("server/a.rb", "")

    stdout, stderr = capture_io { fuse(Lota::Fuse.options(out: File.join(@root, "dist"), exclude: %w[server sevrer])).call }

    assert_equal "lota fuse: --exclude sevrer matched nothing in the game's folder.\n", stderr
    assert_includes stdout, "Left out 1 path of the game: server\n"
    assert_equal %w[main.rb], game_files
    assert_includes File.read(@log), "fledge build"
  end

  def test_exclude_that_would_leave_out_a_file_the_game_starts_from_is_refused
    write("conf.rb", "")
    ["conf.rb", "*.rb", "{main,x}.rb", "**/main.rb", "co*"].each do |pattern|
      error = assert_raises(Lota::Fuse::Error) do
        fuse(Lota::Fuse.options(out: File.join(@root, "dist"), exclude: [pattern])).call
      end

      assert_match(/\A--exclude #{Regexp.escape(pattern)} would leave out (conf|main)\.rb, which the game needs to start\z/, error.message)
    end
    refute_path_exists @log
    refute_path_exists project
  end

  def test_exclude_may_name_a_folder_that_holds_neither_required_file
    write("conf.rb", "")
    write("a/conf.rb", "")

    capture_io { fuse(Lota::Fuse.options(out: File.join(@root, "dist"), exclude: ["a"])).call }

    assert_equal %w[conf.rb main.rb], game_files
  end

  def test_the_command_takes_exclude_as_often_as_it_is_given
    assert_equal [".", { exclude: %w[server test/**] }],
      Lota::CLI::Commands::Fuse.parse(["--exclude", "server", "--exclude=test/**"])
    error = assert_raises(Lota::Fuse::Error) { Lota::CLI::Commands::Fuse.parse(["--exclude"]) }

    assert_includes error.message, "--exclude needs a value"
  end

  def test_the_command_exits_with_status_1_for_an_exclude_it_refuses
    _stdout, stderr = capture_io do
      error = assert_raises(SystemExit) { Lota::CLI.call(["fuse", @game, "--exclude", "main.rb"]) }

      assert_equal 1, error.status
    end

    assert_equal "lota fuse: --exclude main.rb would leave out main.rb, which the game needs to start\n", stderr
  end

  def test_the_command_prints_its_help
    stdout, = capture_io { assert_raises(SystemExit) { Lota::CLI.call(%w[fuse --help]) } }

    assert_includes stdout, "Usage: lota fuse [path] [options]"
    assert_includes stdout, "replace it before you ship"
    assert_includes stdout, "--exclude PATTERN"
    assert_includes stdout, "--notarize PROFILE"
    assert_includes stdout, "--sign-command COMMAND"
    assert_includes Lota::CLI.usage, "fuse [path] [options]"
  end
end
