# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "native_gem"
require_relative "package_check"

# Lota's precompiled gem, built from rake compile's bundle, which CMake
# links in ENGINE_BUILD (tasks/engine.rake), with the licensing
# ext/lota/licenses.rb records.
def native_gem
  NativeGem.new(
    root: Dir.pwd,
    gemspec: "lota.gemspec",
    bundle: "lib/lota/native.#{RbConfig::CONFIG['DLEXT']}",
    build: ENGINE_BUILD,
    licensing: Licensing.load("ext/lota/licenses.rb"),
    licenses: %w[LICENSES ext/lota/licenses]
  )
end

# A game that opens LÖVE's default window, clears it to yellow, and quits
# with a status of its own, so an exit status of 0 cannot pass by
# accident.
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

# The walking skeleton's acceptance test (Plan 001): Lövetest's
# love.graphics tests, translated in test/lovetest, run by lota run as the
# gate's test/native/lota_run_test.rb runs them, and compared with LÖVE's
# expected images in vendor/love/testing/output/expected. It quits with 0
# only when every test passed; the output rules out a run of no tests.
LOVETEST_GAME = PackageCheck::Game.new(
  name: "test/lovetest/game",
  folder: "test/lovetest/game",
  files: {},
  gems: ["minitest"],
  arguments: [],
  output: /^love\.conf$.*^[1-9]\d* runs, \d+ assertions, 0 failures, 0 errors, 0 skips$/m,
  status: 0
)

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
        README.rdoc
        CHANGELOG.md
        LICENSE
        LICENSES
        ext/lota/extconf.rb
        ext/lota/CMakeLists.txt
        ext/lota/cmake
        ext/lota/engine
        ext/lota/native
      ],
      native_packaged: [NativeGem::REUSE_TOML],
      extension: "lib/lota/native",
      native: native_gem,
      refusal: "Install Lota's precompiled gem instead, for Apple Silicon macOS",
      smoke: <<~RUBY,
        require "lota"
        puts "lota \#{Lota::VERSION} loads, with \#{Lota::Native::RandomGenerator.cpp_class}"
      RUBY
      games: [PACKAGE_GAME, LOVETEST_GAME]
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

  desc "Build the precompiled gem for #{NativeGem::PLATFORM} into pkg/"
  task native: :compile do
    puts "✅ Built #{build_native_package}"
  end
end
