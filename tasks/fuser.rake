# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

desc "Build the fuser app, which makes a .lota dropped on it into an app, shipping the Lota gem GEM, into OUT (dist/fuser)"
task :fuser, %i[gem out] do |_task, arguments|
  gem = arguments[:gem] or abort "rake fuser needs the Lota gem it ships: rake \"fuser[pkg/lota-VERSION-PLATFORM.gem]\""
  require_relative "fuser_app"
  FuserApp.new(File.expand_path(gem), arguments[:out] || "dist/fuser").call
rescue Lota::Fuse::Error => e
  abort "rake fuser: #{e.message}"
end
