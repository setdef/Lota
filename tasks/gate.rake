# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "gate"

# The gate, bundle exec rake, in two parts. The first, run in order in this
# process, changes files (RuboCop's autocorrection) and builds what the
# checks load. The checks (tasks/gate.rb) then run in lanes: the checks in
# one lane share something only one can use at a time, so run one after
# another, and the lanes run at the same time.
#
# Every check reads the build and writes only its own files: each test
# process has a home and an audio file of its own (test/test_home.rb), and
# its windows stay in the background. The tests that take keyboard focus or
# move the pointer (Lövetest's mouse tests, and the game package:install
# runs in front) hold the desktop input lock (tasks/desktop_input.rb), so
# they wait for each other.
# test:ruby runs as its shards (tasks/test.rake), and cpp, lint, and steep
# are short enough to share a lane.
#
# LOTA_GATE_JOBS=1 runs the same checks one after another, in the order of
# the lanes below, for finding which check a problem belongs to.
#
# LOTA_GATE_DISPLAYS lists, separated by spaces, an X display for each lane
# in the order below, so that on Linux no lane's windows open over
# another's (tasks/gate.rb); CI's Linux gate starts them.
GATE_PREPARE = %w[lint:fix engine compile].freeze
GATE_LANES = [
  [Gate::Check.of("test:shard:rake_tasks"), Gate::Check.of("package:check"), Gate::Check.of("package:install")],
  [Gate::Check.of("test:shard:native")],
  [Gate::Check.of("test:shard:generator"), Gate::Check.of("test:shard:tasks")],
  [Gate::Check.of("test:parity")],
  [Gate::Check.of("cpp"), Gate::Check.of("lint"), Gate::Check.of("steep")],
].freeze

desc "Run the gate's checks in lanes, after fixing, engine, and compile"
task :gate do
  jobs = Integer(ENV.fetch("LOTA_GATE_JOBS", GATE_LANES.size))
  displays = ENV.fetch("LOTA_GATE_DISPLAYS", "").split
  Gate.new(prepared: GATE_PREPARE, lanes: GATE_LANES, jobs:, displays:).run { |name| Rake::Task[name].invoke }
rescue Gate::Failure => e
  abort "❌ #{e.message}"
end
