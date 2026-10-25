# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "package_check"

# The gems this repository publishes. Each packaged list matches its
# gemspec's; a new top-level path belongs in both.
PACKAGES = [
  PackageCheck::Target.new(
    name: "lota",
    dir: ".",
    packaged: %w[
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
    generated: [],
    extension: "lib/lota/native",
    smoke: <<~RUBY),
      require "lota"
      puts "lota \#{Lota::VERSION} loads, with \#{Lota::Native::RandomGenerator.cpp_class}"
    RUBY
].freeze

namespace :package do
  desc "Build each gem and load it from its package, with the compiled extensions (fast)"
  task check: :compile do
    PackageCheck.new(root: Dir.pwd, gems: PACKAGES).fast
  rescue PackageCheck::Failure => e
    abort "❌ #{e.message}"
  end

  desc "Install each gem into an empty GEM_HOME, compiling from the packaged sources (slow)"
  task :install do
    PackageCheck.new(root: Dir.pwd, gems: PACKAGES).full
  rescue PackageCheck::Failure => e
    abort "❌ #{e.message}"
  end
end
