# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "native_gem"
require_relative "package_check"
require_relative "../test/lovetest/unseen_desktop"
require_relative "../test/lovetest/lovetest_skips"

# What the bundle compiles against from LÖVE's dependencies but does not
# carry as code of its own, on each platform (NativeGem): their headers,
# beside the frameworks or shared libraries the gem carries on their own.
# On Windows, where every library but OpenAL Soft is linked into the
# bundle and recorded with it (ext/lota/licenses.rb), that is the headers
# and OpenAL Soft's import library alone.
NATIVE_DEPENDENCIES = {
  "macos" => "vendor/love-apple-dependencies",
  "linux" => "tmp/dependencies/installdir",
  "windows" => %w[tmp/dependencies/installdir/include tmp/dependencies/installdir/lib/libOpenAL32.dll.a],
}.freeze

# Lota's precompiled gem, built from rake compile's bundle, which CMake
# links in ENGINE_BUILD (tasks/engine.rake), against LÖVE's dependencies,
# with the licensing ext/lota/licenses.rb records.
def native_gem
  NativeGem.new(
    root: Dir.pwd,
    gemspec: "lota.gemspec",
    bundle: "lib/lota/native.#{RbConfig::CONFIG['DLEXT']}",
    build: ENGINE_BUILD,
    licensing: Licensing.load("ext/lota/licenses.rb"),
    licenses: %w[LICENSES ext/lota/licenses],
    dependencies: NATIVE_DEPENDENCIES.fetch(ENGINE_PLATFORM)
  )
end

# A game that opens LÖVE's default window, clears it to yellow, and quits
# with a status of its own, so an exit status of 0 cannot pass by
# accident. It opens the audio module through the gem's OpenAL Soft, which
# plays through its null backend and asks for no real-time priority in the
# check (PackageCheck::SILENT, tasks/alsoft.conf), so it prints nothing
# about it.
PACKAGE_GAME = PackageCheck::Game.new(
  name: "a window",
  folder: nil,
  files: { "main.rb" => <<~RUBY },
    def Lota.load
      puts "window \#{Lota::Graphics.dimensions.join('x')}"
    end

    def Lota.draw
      Lota::Graphics.clear(1, 1, 0, 1)
      Lota::Event.quit(3)
    end
  RUBY
  gems: [],
  arguments: [],
  output: /\Awindow 800x600\n\z/,
  status: 3
)

# The installed gem's acceptance test: Lövetest's
# love.graphics tests, translated in test/lovetest, run by lota run as the
# gate's test/native/lota_run_test.rb runs them, and compared with LÖVE's
# expected images in vendor/love/testing/output/expected. It quits with 0
# only when every test passed; the output rules out a run of no tests.
LOVETEST_SKIPS = UnseenDesktop.skips(LovetestSkips.expected)

LOVETEST_GAME = PackageCheck::Game.new(
  name: "test/lovetest/game",
  folder: "test/lovetest/game",
  files: {},
  gems: ["minitest"],
  arguments: [],
  # Its skips, counted from the tests (test/lovetest/lovetest_skips.rb),
  # are Lövetest's discard, requestAttention, showMessageBox, openURL,
  # vibrate, pump, wait, getSource, and setSource tests, which Lövetest
  # skips everywhere (test/lovetest/tests/graphics.rb, window.rb,
  # system.rb, event.rb, and filesystem.rb), and its RecordingDevice
  # test, which skips where OpenAL Soft cannot record, as through the null
  # driver here (SILENT, test/lovetest/tests/audio.rb), and, on a GitHub
  # runner on Linux, the window tests xvfb cannot pass (window.rb), and,
  # on a desktop macOS does not draw,
  # the isOccluded test (test/lovetest/unseen_desktop.rb). Its isEnabled,
  # getName, and getData sensor tests skip together where the machine has
  # neither an accelerometer nor a gyroscope (test/lovetest/tests/
  # sensor.rb), which only the game itself asks, so either count passes.
  output: /^love\.conf$.*^[1-9]\d* runs, \d+ assertions, 0 failures, 0 errors, (?:#{LOVETEST_SKIPS}|#{LOVETEST_SKIPS + 3}) skips$/m,
  status: 0,
  # Lövetest's love.mouse.setGrabbed test passes only for a window with
  # keyboard focus, for which SDL grabs the mouse (SDL 3.4.10,
  # src/video/SDL_video.c, SDL_UpdateWindowGrab), so this game's window
  # comes to the front, as a player's would.
  background: false
)

# A game for Windows, whose CI runners have no GPU and no OpenGL that
# LÖVE's renderer can use, so no game opens a window there: it opens no
# window and no graphics, as test/games/restart does, and plays a sound
# it makes through the gem's OpenAL32.dll, whose null backend plays
# nothing (SILENT), then quits with a status of its own.
WINDOWLESS_GAME = PackageCheck::Game.new(
  name: "a sound without a window",
  folder: nil,
  files: {
    "conf.rb" => <<~RUBY,
      def Lota.conf(t)
        %i[window graphics image font keyboard mouse].each { |name| t.modules.public_send(:"\#{name}=", false) }
      end
    RUBY
    "main.rb" => <<~RUBY,
      def Lota.load
        Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1)).play
        puts "\#{Lota::System.os}: \#{Lota::Audio.active_source_count} source playing"
        Lota::Event.quit(3)
      end
    RUBY
  },
  gems: [],
  arguments: [],
  output: /\AWindows: 1 source playing\n\z/,
  status: 3
)

# The games delivery runs from the installed gem: on Windows, only the one
# that opens no window.
def package_games
  (ENGINE_PLATFORM == "windows") ? [WINDOWLESS_GAME] : [PACKAGE_GAME, LOVETEST_GAME]
end

# The gems this repository publishes. Each packaged list matches its
# gemspec's; a new top-level path belongs in both.
def packages
  [
    PackageCheck::Target.new(
      name: "lota",
      dir: ".",
      packaged: %w[
        exe
        lib
        sig
        skills
        README.rdoc
        CHANGELOG.md
        LICENSE
        LICENSES
        ext/lota/extconf.rb
        ext/lota/CMakeLists.txt
        ext/lota/cmake
        ext/lota/engine
        ext/lota/native
        ext/lota/phone
        ext/lota/preload
      ],
      native_packaged: [NativeGem::REUSE_TOML, Licensing::SOURCES, Licensing::NOTICES],
      extension: "lib/lota/native",
      native: native_gem,
      refusal: "Install Lota's precompiled gem instead, which RubyGems chooses",
      smoke: <<~RUBY,
        require "lota"
        puts "lota \#{Lota::VERSION} loads, with \#{Lota::Native::RandomGenerator.cpp_class}"
      RUBY
      games: package_games
    ),
  ]
end

# Builds the precompiled gem into tmp/native_gem, copies it into pkg/, and
# returns the copy's path.
def build_native_package
  package = native_gem.build(File.expand_path("tmp/native_gem"))
  FileUtils.mkdir_p("pkg")
  FileUtils.cp(package, "pkg")
  File.join("pkg", File.basename(package))
end

# Installs the precompiled gems in +files+ and runs lota from them, as CI's
# delivery job does.
def deliver_packages(files)
  PackageCheck.new(root: Dir.pwd, gems: packages).deliver(files)
rescue PackageCheck::Failure => e
  abort "❌ #{e.message}"
end

namespace :package do
  desc "Check each source gem stops at install, and load each precompiled gem from its package (fast)"
  task check: :compile do
    PackageCheck.new(root: Dir.pwd, gems: packages).fast
  rescue PackageCheck::Failure => e
    abort "❌ #{e.message}"
  end

  desc "Build each precompiled gem, then deliver it as CI does: install it and run a game from it (slow)"
  task install: :compile do
    deliver_packages([build_native_package])
  end

  # Builds nothing, so it runs on a runner that has only the repository's
  # tasks and the gems built on another, as CI's delivery job does.
  desc "Install the precompiled gems given, already built, into an empty GEM_HOME, then run lota and a game from them"
  task :deliver do |_task, args|
    deliver_packages(args.extras)
  end

  desc "Build the precompiled gem for this platform (#{NativeFormat.host.platform}) into pkg/"
  task native: :compile do
    puts "✅ Built #{build_native_package}"
  end
end
