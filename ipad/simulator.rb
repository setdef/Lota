# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runs the iOS kit's app in new iPhone and iPad Simulators, for any game,
# as the iOS spike's simulator.rb ran its game. For each device it creates
# and boots a Simulator, installs the app, and launches it with simctl:
# KIT_NORMAL_LAUNCHES launches with the game's smoke settings (KIT_SMOKE_ENV,
# NAME=VALUE pairs, which simctl passes to the app as SIMCTL_CHILD_
# variables), each for up to KIT_SMOKE_SECONDS, then one idle launch with
# no settings at all. It takes Simulator screenshots on the wall clock,
# reads the app's os_log, and copies the app's data container and any
# crash report into OUT.
#
# A launch passes when no crash report appears, no line holds [BUG] (Ruby's
# report of a crash in itself), and the app either exits with status 0 or
# is still running when its time is up; a normal launch's output must also
# match KIT_SMOKE_EXPECT, a regular expression, when one is given. A game
# that quits by itself must quit with 0; one that runs on passes by not
# crashing.
#
# ORIENTATION is portrait or landscape. simctl cannot turn a device, so for
# landscape a UI test (uitests/KitHold.m, from the xctestrun file
# KIT_XCTESTRUN) turns it and holds it turned while the launches run.
# With KIT_XCTESTRUN, devices whose names start with one of KIT_TOUCH_DEVICES
# (comma-separated) also run uitests/TouchTest.m against a launch with
# KIT_SMOKE_ENV and KIT_TOUCH_ENV, and the lines the game logged then are
# kept.
#
# Each DEVICE is a list of Simulator names separated by |, the first one
# the runtime has winning; one that starts with ? may be missing. Plain
# Ruby 2.6, so a runner's own /usr/bin/ruby runs it with nothing installed.
#
#   ruby simulator.rb APP_BUNDLE IDENTIFIER EXECUTABLE OUT ORIENTATION DEVICE...
require "fileutils"
require "json"
require "open3"
require "time"

bundle, identifier, executable, out, orientation, *wanted = ARGV
abort "usage: simulator.rb APP IDENTIFIER EXECUTABLE OUT portrait|landscape DEVICE..." unless %w[portrait landscape].include?(orientation)
FileUtils.mkdir_p(out)
$stdout.sync = true

def pairs(text)
  text.to_s.split(/\s+/).reject(&:empty?).to_h do |pair|
    name, value = pair.split("=", 2)
    abort "#{pair.inspect} is not NAME=VALUE" if value.nil? || name !~ /\A[A-Za-z_][A-Za-z0-9_]*\z/
    abort "OS_ACTIVITY_DT_MODE freezes the app's log (Host/main.m), so the kit never sets it" if name == "OS_ACTIVITY_DT_MODE"
    [name, value]
  end
end

SMOKE_ENV = pairs(ENV["KIT_SMOKE_ENV"]).freeze
TOUCH_ENV = SMOKE_ENV.merge(pairs(ENV["KIT_TOUCH_ENV"])).freeze
EXPECT = ENV["KIT_SMOKE_EXPECT"].to_s.empty? ? nil : Regexp.new(ENV["KIT_SMOKE_EXPECT"])
SMOKE_SECONDS = Integer(ENV.fetch("KIT_SMOKE_SECONDS", "40"))
IDLE_SECONDS = Integer(ENV.fetch("KIT_IDLE_SECONDS", [SMOKE_SECONDS, 30].max.to_s))
NORMAL_LAUNCHES = Integer(ENV.fetch("KIT_NORMAL_LAUNCHES", "2"))
XCTESTRUN = ENV["KIT_XCTESTRUN"].to_s.empty? ? nil : ENV["KIT_XCTESTRUN"]
UITESTS = ENV.fetch("KIT_UITESTS_TARGET", "#{executable}UITests")
TOUCH_DEVICES = ENV["KIT_TOUCH_DEVICES"].to_s.split(",").map(&:strip).reject(&:empty?)
# KIT_EXTRA_LAUNCHES: more launches after those, separated by ;, each with
# its own NAME=VALUE pairs (not KIT_SMOKE_ENV's), for up to
# KIT_SMOKE_SECONDS, passing as an idle launch passes.
EXTRA_ENVS = ENV["KIT_EXTRA_LAUNCHES"].to_s.split(";").map(&:strip).reject(&:empty?).map { |text| pairs(text).freeze }.freeze
MODES = (([:normal] * NORMAL_LAUNCHES) + [:idle] + ([:extra] * EXTRA_ENVS.size)).freeze
abort "landscape needs KIT_XCTESTRUN, the UI tests that turn the device" if orientation == "landscape" && XCTESTRUN.nil?

def capture(*command)
  output, status = Open3.capture2(*command)
  raise "#{command.join(' ')} failed" unless status.success?

  output
end

def runtime
  runtimes = JSON.parse(capture("xcrun", "simctl", "list", "runtimes", "-j")).fetch("runtimes")
  runtimes.select { |candidate| candidate["platform"] == "iOS" && candidate["isAvailable"] }
    .max_by { |candidate| Gem::Version.new(candidate.fetch("version")) } or raise "no iOS Simulator runtime"
end

def device_types(runtime, wanted)
  types = runtime.fetch("supportedDeviceTypes")
  %w[iPhone iPad].each do |family|
    puts "#{family} types on #{runtime['name']}: #{types.select { |type| type['productFamily'] == family }.map { |type| type['name'] }.join(', ')}"
  end
  wanted.map do |group|
    optional = group.start_with?("?")
    names = group.sub(/\A\?/, "").split("|")
    found = names.map { |name| types.find { |type| type["name"] == name } }.compact.first
    raise "the runtime has none of #{names.join(', ')}" if found.nil? && !optional

    puts "no #{names.join(' or ')} on this runtime; skipped" if found.nil?
    found
  end.compact
end

# Whether the process +pid+ simctl launched still runs. A Simulator's apps
# are processes of the Mac's, so the Mac's own kill(2) answers; the
# Simulator's launchctl list, which an earlier harness read, sometimes
# left out an app that was still printing, while a UI test held the
# device turned. An app whose Ruby program has returned stays running:
# SDL_RunApp keeps UIKit's loop going.
def running?(pid)
  Process.kill(0, pid)
  true
rescue Errno::ESRCH
  false
rescue Errno::EPERM
  true
end

# Whether the child process +pid+ has ended; its status is then in
# @statuses.
def done?(pid)
  @statuses ||= {}
  return true if @statuses[pid]

  return false if Process.waitpid(pid, Process::WNOHANG).nil?

  @statuses[pid] = $?
  true
end

# The app's log entries since +since+, as [category, message] pairs.
def messages(udid, since, identifier, log)
  system("xcrun", "simctl", "spawn", udid, "log", "show", "--start", since, "--style", "ndjson", "--info", "--debug",
    "--predicate", "subsystem == \"#{identifier}\"", out: log, err: File::NULL)
  File.readlines(log).map do |line|
    entry = JSON.parse(line)
    (entry.is_a?(Hash) && entry["eventMessage"]) ? [entry["timestamp"], entry["category"], entry["eventMessage"]] : nil
  rescue JSON::ParserError
    nil
  end.compact
end

def shot_times(seconds)
  ([2, 5, 9, seconds / 2, seconds - 1].select { |time| time >= 1 && time < seconds }).uniq.sort
end

# Takes screenshots from a process of its own, on the wall clock since
# launch, so a slow log query never delays one; each file names the
# second it was taken at.
def shooter(udid, dir, times)
  script = times.each_cons(2).inject("sleep #{times.first}; shot #{times.first}") { |text, (a, b)| "#{text}; sleep #{b - a}; shot #{b}" }
  Process.spawn("/bin/sh", "-c",
    "shot() { xcrun simctl io #{udid} screenshot \"#{dir}/simulator-$(printf %02d $1)s.png\" >/dev/null 2>&1; }; #{script}")
end

def crashes(executable, since)
  Dir.glob(File.join(Dir.home, "Library/Logs/DiagnosticReports/#{executable}*")).select { |crash| File.mtime(crash) >= since - 5 }
end

def launch(udid, identifier, env)
  child = env.to_h { |key, value| ["SIMCTL_CHILD_#{key}", value] }
  launched, status = Open3.capture2(child, "xcrun", "simctl", "launch", udid, identifier)
  raise "simctl launch failed: #{launched}" unless status.success?

  pid = Integer(launched[/: (\d+)\s*\z/, 1])
  puts "  launched #{identifier} as process #{pid}#{env.empty? ? ' with no settings' : " with #{env.map { |key, value| "#{key}=#{value}" }.join(' ')}"}"
  pid
end

# Ends a launch: terminates the app, and keeps its log, its process's
# log, its data container, and its crash reports in +dir+. Returns the
# app's log entries and whether the app was still running.
def collect(udid, identifier, executable, dir, since, started, pid)
  alive = running?(pid)
  system("xcrun", "simctl", "terminate", udid, identifier, out: File::NULL, err: File::NULL)
  sleep 3
  entries = messages(udid, since, identifier, File.join(dir, "subsystem.ndjson"))
  File.write(File.join(dir, "subsystem.log"), "#{entries.map { |time, category, text| "#{time} [#{category}] #{text}" }.join("\n")}\n")
  entries.each { |time, category, text| puts "    #{time[11, 12]} [#{category}] #{text}" }
  File.write(File.join(dir, "process.log"), Open3.capture2e("xcrun", "simctl", "spawn", udid, "log", "show",
    "--start", since, "--style", "compact", "--info", "--predicate", "process == \"#{executable}\"").first)
  data, = Open3.capture2("xcrun", "simctl", "get_app_container", udid, identifier, "data")
  FileUtils.cp_r(data.strip, File.join(dir, "data-container")) unless data.strip.empty?
  crashes(executable, started).each { |crash| FileUtils.cp(crash, dir) }
  [entries, alive]
end

def verdict(entries, alive, dir)
  exits = entries.select { |_, category, _| category == "app" }.map { |_, _, text| text[/exited with status (-?\d+)/, 1] }.compact
  bugs = entries.map(&:last).grep(/\[BUG\]/)
  crashed = !Dir.glob(File.join(dir, "*.ips")).empty?
  exit_status = exits.last
  ended = exit_status ? (exit_status == "0") : alive
  {
"exit" => exit_status,
"running_at_end" => alive,
"crash_report" => crashed,
"bug_lines" => bugs,
"ruby_lines" => entries.count { |_, category, _| category == "ruby" },
"clean" => !crashed && bugs.empty? && ended,
}
end

def start_test(udid, test, dir, env)
  log = File.join(dir, "xcodebuild-#{test.split('/').last}.log")
  runner = env.to_h { |key, value| ["TEST_RUNNER_#{key}", value] }
  Process.spawn(runner, "xcodebuild", "test-without-building", "-xctestrun", XCTESTRUN, "-destination", "id=#{udid}",
    "-only-testing:#{UITESTS}/#{test}", "-resultBundlePath", File.join(dir, "#{test.split('/').first}.xcresult"),
    out: log, err: [:child, :out])
end

def wait_for(file, pid, seconds)
  deadline = Time.now + seconds
  until File.exist?(file)
    return false if done?(pid) || Time.now > deadline

    sleep 1
  end
  true
end

def wait_test(pid, seconds)
  deadline = Time.now + seconds
  until done?(pid)
    if Time.now > deadline
      Process.kill("TERM", pid)
      Process.wait(pid)
      return false
    end
    sleep 2
  end
  @statuses.fetch(pid).success?
end

results = {}
os = runtime
puts "== runtime #{os['name']} (#{os['identifier']}), #{orientation}"
device_types(os, wanted).each do |type|
  name = type.fetch("name")
  slug = name.gsub(/[^A-Za-z0-9]+/, "-").sub(/-\z/, "")
  device_dir = File.join(out, "#{slug}-#{orientation}")
  FileUtils.mkdir_p(device_dir)
  puts "== #{name} (#{type['identifier']}), #{orientation}"
  udid = capture("xcrun", "simctl", "create", "kit-#{slug}", type.fetch("identifier"), os.fetch("identifier")).strip
  begin
    system("xcrun", "simctl", "bootstatus", udid, "-b", out: File::NULL, exception: true)
    system("xcrun", "simctl", "install", udid, bundle, exception: true)
    hold = nil
    if orientation == "landscape"
      ready = File.join(device_dir, "hold-ready")
      hold = start_test(udid, "KitHold/testHold", device_dir,
        "KIT_ORIENTATION" => "landscape", "KIT_READY" => ready, "KIT_DONE" => File.join(device_dir, "hold-done"))
      raise "#{name}: the UI test never turned the device (#{device_dir}/xcodebuild-testHold.log)" unless wait_for(ready, hold, 420)

      system("xcrun", "simctl", "io", udid, "screenshot", File.join(device_dir, "turned.png"), out: File::NULL, err: File::NULL)
    end
    pids = []
    MODES.each.with_index(1) do |mode, attempt|
      env = { normal: SMOKE_ENV, idle: {}, extra: EXTRA_ENVS[attempt - NORMAL_LAUNCHES - 2] }.fetch(mode)
      seconds = (mode == :idle) ? IDLE_SECONDS : SMOKE_SECONDS
      dir = File.join(device_dir, "run-#{attempt}-#{mode}")
      FileUtils.mkdir_p(dir)
      puts "  launch #{attempt} of #{MODES.size}: #{mode}, #{seconds} s"
      since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
      pid = launch(udid, identifier, env)
      raise "launch #{attempt} reused process #{pid}" if pids.include?(pid)

      pids << pid
      started = Time.now
      shots = shooter(udid, dir, shot_times(seconds))
      loop do
        sleep 3
        exited = messages(udid, since, identifier, File.join(dir, "subsystem.ndjson")).any? { |_, category, text| category == "app" && text.include?("exited with status") }
        break if (exited || Time.now - started > seconds || !crashes(executable, started).empty?) && done?(shots)
      end
      entries, alive = collect(udid, identifier, executable, dir, since, started, pid)
      result = verdict(entries, alive, dir)
      ruby = entries.select { |_, category, _| category == "ruby" }.map(&:last).join("\n")
      result["expect_matched"] = (mode == :normal && EXPECT) ? !EXPECT.match(ruby).nil? : nil
      result["ok"] = result["clean"] && result["expect_matched"] != false
      result["env"] = env.map { |key, value| "#{key}=#{value}" }.join(" ") if mode == :extra
      result["output"] = entries.select { |_, category, _| category == "ruby" }.map(&:last).first(60) if mode == :extra
      results["#{name} #{orientation} ##{attempt} #{mode}"] = result
      puts "  => #{result['ok'] ? 'ok' : 'FAILED'} #{result.dup.tap { |shown| shown.delete('ok') }.to_json}"
    end
    if hold
      FileUtils.touch(File.join(device_dir, "hold-done"))
      results["#{name} #{orientation} hold"] = { "ok" => wait_test(hold, 180) }
    end
    if XCTESTRUN && TOUCH_DEVICES.any? { |prefix| name.start_with?(prefix) }
      dir = File.join(device_dir, "touch")
      FileUtils.mkdir_p(dir)
      puts "  touch and rotation test"
      ready = File.join(dir, "touch-ready")
      test = start_test(udid, "TouchTest/testTouchAndRotation", dir,
        "KIT_READY" => ready, "KIT_APP" => identifier, "KIT_SHOTS" => dir)
      if wait_for(ready, test, 420)
        since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
        started = Time.now
        pid = launch(udid, identifier, TOUCH_ENV)
        passed = wait_test(test, 600)
        entries, alive = collect(udid, identifier, executable, dir, since, started, pid)
        result = verdict(entries, alive, dir)
        result["test_passed"] = passed
        result["probe"] = entries.map(&:last).grep(/probe:|touch|resize/i).first(40)
        result["ok"] = passed && result["clean"]
      else
        result = { "ok" => false, "error" => "the touch test never became ready (#{dir}/xcodebuild-testTouchAndRotation.log)" }
      end
      results["#{name} touch"] = result
      puts "  => #{result['ok'] ? 'ok' : 'FAILED'} #{result.dup.tap { |shown| shown.delete('ok') }.to_json}"
    end
  rescue => e
    puts "::error::#{name}: #{e.message}"
    results["#{name} #{orientation} error"] = { "ok" => false, "error" => e.message }
  ensure
    system("xcrun", "simctl", "shutdown", udid, out: File::NULL, err: File::NULL)
    system("xcrun", "simctl", "delete", udid, out: File::NULL, err: File::NULL)
  end
end
File.write(File.join(out, "results-#{orientation}.json"), JSON.pretty_generate(results))
puts JSON.pretty_generate(results)
exit((!results.empty? && results.values.all? { |result| result["ok"] }) ? 0 : 1)
