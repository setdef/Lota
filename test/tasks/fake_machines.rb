# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"
require "rbconfig"

# A machines command for the tasks' tests: a real program on a PATH of
# the test's, which records each call's arguments and answers as the real
# one does, with its output, a RUN_EXIT line, and an exit status, as the
# test configures it for each operating system it is asked to run on.
module FakeMachines
  PROGRAM = <<~RUBY
    #!#{RbConfig.ruby}
    require "json"
    dir = File.dirname(__FILE__)
    config = JSON.parse(File.read(File.join(dir, "config.json")))
    os = ARGV[1]
    File.open(File.join(dir, "calls.jsonl"), "a") do |log|
      log.flock(File::LOCK_EX)
      log.puts(JSON.generate(ARGV))
    end
    File.open(File.join(dir, "env.jsonl"), "a") do |log|
      log.flock(File::LOCK_EX)
      log.puts(JSON.generate(ENV.to_h.select { |name, _| name.start_with?("GIT_") }))
    end
    # Runs that must run at once each wait for the others to start, and
    # fail when they do not, as they would one after another.
    together = config.fetch("together", [])
    if together.include?(os)
      File.write(File.join(dir, "\#{os}.started"), "")
      started = -> { together.all? { |name| File.exist?(File.join(dir, "\#{name}.started")) } }
      deadline = Time.now + 10
      sleep 0.02 until started.call || Time.now > deadline
      unless started.call
        puts "RUN_EXIT=9 id=fake machine=fake queued=0s ran=0s"
        exit 9
      end
    end
    answer = config.fetch(os, {})
    answer.fetch("lines", ["hello from \#{os}"]).each { |line| puts line }
    $stdout.flush
    warn "machines: \#{answer['why']}" if answer["why"]
    # Output cut off mid-line, as when the connection drops.
    print answer["partial"] if answer["partial"]
    exit answer["machines"] if answer["machines"]

    code = answer.fetch("code", 0)
    puts "RUN_EXIT=\#{code} id=fake-\#{os} machine=fake queued=0s ran=1s"
    exit code
  RUBY

  # Puts the fake machines in +dir+, answering as +config+ says: for each
  # operating system, "lines" to print, a note on standard error ("why"),
  # the command's "code", or "machines", an exit status of machines' own
  # with no RUN_EXIT, after a "partial" last line without a newline; and
  # "together", the systems whose runs
  # must overlap. Returns its path.
  def fake_machines(dir, config = {})
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "config.json"), JSON.generate(config))
    path = File.join(dir, "machines")
    File.write(path, PROGRAM)
    File.chmod(0o755, path)
    path
  end

  # The arguments of each call the fake machines in +dir+ took.
  def machines_calls(dir)
    log = File.join(dir, "calls.jsonl")
    File.exist?(log) ? File.readlines(log).map { |line| JSON.parse(line) } : []
  end

  # The GIT_ variables each call the fake machines in +dir+ took had in
  # its environment.
  def machines_git_env(dir)
    log = File.join(dir, "env.jsonl")
    File.exist?(log) ? File.readlines(log).map { |line| JSON.parse(line) } : []
  end
end
