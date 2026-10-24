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

  spec.summary = "LÖVE's 2D game engine, driven by Ruby instead of Lua."
  spec.description = File.read(File.expand_path("README.rdoc", __dir__))
  spec.license = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 4.0.1"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship what an installed game loads. Listing paths keeps development files
  # (plans, tasks, tests, tool configuration, vendor/love) out without a deny
  # list that every new file has to remember. The native extension joins this
  # list in Plan 001's walking skeleton.
  packaged = %w[lib sig README.rdoc CHANGELOG.md LICENSE LICENSES]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.require_paths = ["lib"]
end
