# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

desc "Build Lota's app, which plays a .lota opened with it or dropped on its screen, into OUT (dist/player), shipping the " \
  "Lota gem GEM, or the one RubyGems installed for this platform; Bundler locks only an installed gem's checksum"
task :player, %i[gem out] do |_task, arguments|
  require "lota"
  require_relative "player_app"
  gem = arguments[:gem]
  PlayerApp.new(gem && File.expand_path(gem), arguments[:out] || "dist/player").call
rescue Lota::Fuse::Error => e
  abort "rake player: #{e.message}"
end
