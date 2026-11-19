# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "provenance"
require_relative "push_check"

desc "Check that each commit of RANGE (default: the unpushed ones) says its provenance in a trailer git reads"
task :provenance, [:range] do |_task, args|
  refusal = Provenance.refusal(Provenance.read(Dir.pwd, args[:range] || red_before_green_range))
  next puts("provenance: every commit says its provenance in a trailer") unless refusal

  abort "provenance: #{refusal}"
end

# Runs +step+ of PushCheck in this process, and answers whether it passed.
# RuboCop runs as its rake task does, through its CLI, which takes every
# file it is given whatever their number, and which its rake task loads
# only when it runs; a rake task that fails aborts or raises, and that is
# its failure.
def push_check_step(step)
  if step.name == "rubocop"
    require "rubocop"
    return RuboCop::CLI.new.run(["--force-exclusion", *step.files]).zero?
  end

  Rake.application.invoke_task(step.name)
  true
rescue SystemExit => e
  e.success?
rescue => e
  warn "#{step.name}: #{e.message}"
  false
end

desc "Run the pre-push hook's checks over the commits of RANGE (default: the unpushed ones), building nothing"
task :push_check, [:range] do |_task, args|
  range = args[:range] || red_before_green_range
  root = Dir.pwd
  check = PushCheck.new(range:, changed: PushCheck.changes(root, range), known: PushCheck.known(root))
  clock = Enumerator.new { |times| loop { times << Process.clock_gettime(Process::CLOCK_MONOTONIC) } }
  next puts("push_check: every check passed") if check.run(out: $stdout, clock:) { |step| push_check_step(step) }

  abort "❌ push_check failed; the check that failed says why"
end
