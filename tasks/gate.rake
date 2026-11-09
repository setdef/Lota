# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "gate"
require_relative "remote_gate"
require_relative "remote_windows"

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
# runs in front) hold the desktop input lock (the desktop_input_lock gem), so
# they wait for each other.
# test:ruby and test:parity run as their shards (tasks/test.rake), each
# parity shard in a lane of its own, since together they were the longest
# check; the generator's and the tasks' shards, and cpp, lint, and steep,
# are short enough to share a lane, and open no window.
#
# LOTA_GATE_JOBS=1 runs the same checks one after another, in the order of
# the lanes below, for finding which check a problem belongs to.
#
# LOTA_GATE_DISPLAYS lists, separated by spaces, an X display for each lane
# in the order below that opens windows, the first four, so that on Linux
# no lane's windows open over another's (tasks/gate.rb); CI's Linux gate
# starts them.
#
# LOTA_GATE_LANE_TIMEOUT is how many seconds a lane may run before the gate
# prints what it is doing and ends it, failing its check as TIMED OUT
# (Gate::LANE_TIMEOUT says why the default is 47 minutes), and
# LOTA_GATE_HEARTBEAT how many seconds pass between the lines that name the
# checks still running (60 unless set).
GATE_PREPARE = %w[lint:fix engine compile].freeze
GATE_LANES = [
  [Gate::Check.of("test:shard:rake_tasks"), Gate::Check.of("package:check"), Gate::Check.of("package:install")],
  [Gate::Check.of("test:shard:native")],
  [Gate::Check.of("test:shard:gravity_wars")],
  [Gate::Check.of("test:shard:parity")],
  [Gate::Check.of("test:shard:generator"), Gate::Check.of("test:shard:tasks")],
  [Gate::Check.of("cpp"), Gate::Check.of("lint"), Gate::Check.of("steep")],
].freeze

# The pre-push tier, bundle exec rake prepush: the gate's checks that take
# seconds, and of its slow ones a part, in lanes whose checks that open
# windows come first, as the gate's do, so each opens them on a display
# of its own (tasks/test.rake says which tests it leaves out).
# cpp:tidy, package:install, and the parity games are the gate's alone.
PREPUSH_LANES = [
  [Gate::Check.of("test:prepush:sanitized"), Gate::Check.of("package:check")],
  [Gate::Check.of("test:prepush:native")],
  [Gate::Check.of("test:prepush:parity")],
  [Gate::Check.of("test:prepush:tasks")],
  [Gate::Check.of("test:prepush:generator")],
  [Gate::Check.of("cpp:format", "cpp:no_nolint"), Gate::Check.of("lint"), Gate::Check.of("steep")],
].freeze

# Runs +lanes+ after GATE_PREPARE, as the gate does.
def run_gate(lanes)
  jobs = Integer(ENV.fetch("LOTA_GATE_JOBS", lanes.size))
  displays = ENV.fetch("LOTA_GATE_DISPLAYS", "").split
  lane_timeout = Float(ENV.fetch("LOTA_GATE_LANE_TIMEOUT", Gate::LANE_TIMEOUT))
  heartbeat = Float(ENV.fetch("LOTA_GATE_HEARTBEAT", Gate::HEARTBEAT))
  Gate.new(prepared: GATE_PREPARE, lanes:, jobs:, displays:, lane_timeout:, heartbeat:)
    .run { |name| Rake::Task[name].invoke }
rescue Gate::Failure => e
  abort "❌ #{e.message}"
end

desc "Run the gate's checks in lanes, after fixing, engine, and compile"
task(:gate) { run_gate(GATE_LANES) }

desc "Run the pre-push tier: the gate's fast checks, and a part of its slow ones, in lanes"
task(:prepush) { run_gate(PREPUSH_LANES) }

namespace :gate do
  # Leased capacity, for whoever has a gate runner (tasks/remote_gate.rb):
  # LOTA_GATE_HOST names its host for ssh, LOTA_GATE_KEY an identity file
  # for it, and LOTA_GATE_RUNNER its folder there.
  desc "Run the gate, or the rake tasks given, on the gate runner at LOTA_GATE_HOST, on this commit or working tree"
  task :remote do |_task, args|
    gate = RemoteGate.new(repository: Dir.pwd, host: ENV.fetch("LOTA_GATE_HOST", RemoteGate::HOST),
      key: ENV.fetch("LOTA_GATE_KEY", nil), runner: ENV.fetch("LOTA_GATE_RUNNER", RemoteGate::RUNNER))
    status = gate.run(args.to_a)
    exit status unless status.zero?
  rescue RemoteGate::Failure => e
    abort "❌ #{e.message}"
  end

  # Leased Windows capacity, for whoever has a Windows computer with a
  # desktop job runner (tasks/remote_windows.rb): LOTA_WINDOWS_HOST names
  # it for ssh, LOTA_WINDOWS_KEY an identity file for it, and
  # LOTA_WINDOWS_RUNNER the folder under its home that holds the clone.
  desc "Run Lota's Windows checks on the Windows computer at LOTA_WINDOWS_HOST, on this commit or working tree"
  task :windows do
    host = ENV.fetch("LOTA_WINDOWS_HOST", "")
    abort "❌ gate:windows needs LOTA_WINDOWS_HOST, the Windows computer's ssh destination" if host.empty?

    windows = RemoteWindows.new(repository: Dir.pwd, host:, key: ENV.fetch("LOTA_WINDOWS_KEY", nil),
      runner: ENV.fetch("LOTA_WINDOWS_RUNNER", RemoteWindows::RUNNER))
    status = windows.run
    exit status unless status.zero?
  rescue RemoteGate::Failure, RemoteWindows::Failure => e
    abort "❌ #{e.message}"
  end
end
