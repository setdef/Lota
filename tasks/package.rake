# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "native_gem"
require_relative "package_check"

# Lota's precompiled gem, built from rake compile's bundle. Rice's notice
# comes from the rice gem Bundler installed, whose headers the bundle
# compiled in; LÖVE's license.txt covers the engine and the libraries
# LÖVE bundles (vendor/love/license.txt:1-176).
def native_gem
  NativeGem.new(
    root: Dir.pwd,
    gemspec: "lota.gemspec",
    bundle: "lib/lota/native.#{RbConfig::CONFIG['DLEXT']}",
    notices: {
      "NOTICES/love.txt" => "vendor/love/license.txt",
      "NOTICES/rice.txt" => File.join(Gem.loaded_specs.fetch("rice").full_gem_path, "COPYING"),
    },
    framework_notices: { "SDL3.framework" => "#{NativeGem::VERSION}/Resources/License.txt" }
  )
end

# A game that opens LÖVE's default window, clears it to yellow, and quits
# with a status of its own, so an exit status of 0 cannot pass by
# accident.
PACKAGE_GAME = PackageCheck::Game.new(
  files: { "main.rb" => <<~RUBY },
    def Lota.load
      puts "window \#{Lota::Graphics.dimensions.join('x')}"
    end

    def Lota.draw
      Lota::Graphics.clear(1, 1, 0, 1)
      Lota::Event.quit(3)
    end
  RUBY
  arguments: [],
  output: "window 800x600\n",
  status: 3
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
      native_packaged: %w[NOTICES],
      extension: "lib/lota/native",
      native: native_gem,
      refusal: "Install Lota's precompiled gem instead, for Apple Silicon macOS",
      smoke: <<~RUBY,
        require "lota"
        puts "lota \#{Lota::VERSION} loads, with \#{Lota::Native::RandomGenerator.cpp_class}"
      RUBY
      game: PACKAGE_GAME
    ),
  ]
end

namespace :package do
  desc "Check each source gem stops at install, and load each precompiled gem from its package (fast)"
  task check: :compile do
    PackageCheck.new(root: Dir.pwd, gems: packages).fast
  rescue PackageCheck::Failure => e
    abort "❌ #{e.message}"
  end

  desc "Install each precompiled gem into an empty GEM_HOME, then run lota and a game from it (slow)"
  task install: :compile do
    PackageCheck.new(root: Dir.pwd, gems: packages).full
  rescue PackageCheck::Failure => e
    abort "❌ #{e.message}"
  end

  desc "Build the precompiled gem for #{NativeGem::PLATFORM} into pkg/"
  task native: :compile do
    package = native_gem.build(File.expand_path("tmp/native_gem"))
    FileUtils.mkdir_p("pkg")
    FileUtils.cp(package, "pkg")
    puts "✅ Built pkg/#{File.basename(package)}"
  end
end
