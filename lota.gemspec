# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lib/lota/version"

Gem::Specification.new do |spec|
  spec.name = "lota"
  spec.version = Lota::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["me@kerricklong.com"]

  spec.summary = "An independent Ruby library for 2D games, built on a modified version of LÖVE's engine."
  spec.description = File.read(File.expand_path("README.rdoc", __dir__))
  spec.homepage = "https://github.com/setdef/lota"
  spec.license = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 4.0.1"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/trunk/CHANGELOG.md"

  # Ship what an installed game loads, and the sources of the extension,
  # which the precompiled gem also carries compiled (tasks/native_gem.rb).
  # Listing paths keeps development files (plans, tasks, tests, tool
  # configuration, vendor/love, and the test-only extension in
  # ext/lota/native_test) out without a deny list that every new file has
  # to remember. tasks/package.rake lists the same paths.
  packaged = %w[
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
  ]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.bindir = "exe"
  spec.executables = ["lota"]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/lota/extconf.rb"]

  # Rice is header-only, and only building the extension reads it. The
  # precompiled gem compiles nothing at install, and the source gem cannot
  # build once installed (ext/lota/extconf.rb), so Rice is a development
  # dependency, which Bundler installs for rake compile in a clone. Pinned exactly, because ext/lota/native/binding.hpp
  # specializes Rice::detail::Wrapper.
  spec.add_development_dependency "rice", "4.12.0"
end
