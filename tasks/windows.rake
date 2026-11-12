# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "windows_affected"

namespace :windows do
  desc "Exit 0, saying why, when the commits of RANGE (default: the unpushed ones) can change Lota on Windows, " \
    "and 1 when they cannot"
  task :affected, [:range] do |_task, args|
    range = args[:range] || "origin/trunk..HEAD"
    exit WindowsAffected.answer(WindowsAffected.verdict(WindowsAffected.changes(Dir.pwd, range)), range)
  rescue WindowsAffected::Failure => e
    abort "❌ #{e.message}"
  end
end
