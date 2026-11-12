# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "headless"

# Before any task runs: rake run from the command line for a task that
# opens windows, on Linux, with no display to open them on, runs again in
# displays of its own and exits with that run's status (Headless). So on
# any Linux computer the checks need nothing set up for them but the
# packages tasks/apt/build.txt names.
if RUBY_PLATFORM.include?("linux")
  options = Rake.application.options
  begin
    runs = File.basename($PROGRAM_NAME) == "rake" && !(options.show_tasks || options.show_prereqs || options.dryrun)
    if runs && Headless.wanted?(env: ENV, tasks: Rake.application.top_level_tasks)
      $stdout.sync = true
      rake = File.file?($PROGRAM_NAME) ? File.expand_path($PROGRAM_NAME) : Gem.bin_path("rake", "rake")
      exit Headless::Session.new(env: ENV, root: File.expand_path("..", __dir__)).run([RbConfig.ruby, rake, *ARGV])
    end
  rescue Headless::Failure => e
    abort "❌ #{e.message}"
  end
end
