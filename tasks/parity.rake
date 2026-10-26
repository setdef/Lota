# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "reference_love"

# The love executable the parity harness compares Lota with
# (tasks/reference_love.rb), built from vendor/love as LÖVE's own macOS CI
# builds it.
REFERENCE_LOVE = ReferenceLove.new(love: "vendor/love", dependencies: "vendor/love-apple-dependencies",
  root: "tmp/reference")

namespace :reference do
  desc "Build the reference love from vendor/love, as LÖVE's macOS CI does, into tmp/reference"
  task :love do
    ENV["LOTA_REFERENCE_LOVE"] = REFERENCE_LOVE.build
  rescue ReferenceLove::Failure => e
    abort "❌ #{e.message}"
  end
end
