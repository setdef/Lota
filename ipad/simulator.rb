# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs Dot Popper in new iPad Simulators, as the iOS spike's simulator.rb
# ran its game: creates and boots each iPad, installs and launches the
# app with the game's autoplay settings (SIMCTL_CHILD_ variables, which
# simctl passes to the app without the prefix), takes Simulator
# screenshots every few seconds, reads the app's os_log, and copies the
# app's data container (its save folder, the game's own shot-N.png files,
# rounds.csv) and any crash report into OUT. Each iPad runs REPEATS
# autoplay launches with DOT_POPPER_PERF=1, one autoplay launch with
# DOT_POPPER_FAKE_TILT=0.6,0 (a steady sideways tilt, so the Game Over
# pile rolls to one side), shot every 3 s around its Game Over, and one
# idle launch. The Simulator has no accelerometer, so every Game Over of
# the plain autoplay launches must say "tilt from none", and the game
# must go on after it. Plain Ruby 2.6, so the runner's own /usr/bin/ruby
# runs it with nothing installed.
#
#   ruby simulator.rb APP_BUNDLE IDENTIFIER EXECUTABLE OUT [DEVICE_TYPE_NAME ...]
require "fileutils"
require "json"
require "open3"
require "time"

bundle, identifier, executable, out, *wanted = ARGV
FileUtils.mkdir_p(out)
$stdout.sync = true

AUTOPLAY_ENV = {
  "DOT_POPPER_AUTOPLAY" => "1",
  "DOT_POPPER_QUIT_AFTER" => "60",
  "DOT_POPPER_SEED" => "7",
  "DOT_POPPER_SHOTS" => "3,12,25,38",
  "DOT_POPPER_KIT_PROBE" => "1",
  "DOT_POPPER_PERF" => "1"
}.freeze
# The autoplay bot reaches its first Game Over 35 to 40 s into a launch
# with seed 7 and leaves it a few seconds later: in the tilted launch the
# Simulator's screenshots come every 3 s from 21 s, and the game's own
# every 2 s from 28 s of game time.
TILT_SHOT_SECONDS = (21..57).step(3).to_a.freeze
TILT_GAME_SHOTS = (28..50).step(2).to_a.freeze
TILT_ENV = AUTOPLAY_ENV.reject { |key, _| key == "DOT_POPPER_PERF" }
  .merge("DOT_POPPER_SHOTS" => TILT_GAME_SHOTS.join(","), "DOT_POPPER_FAKE_TILT" => "0.6,0").freeze
# A launch nobody plays, left on the title screen for IDLE_SECONDS and then
# terminated, as a player who walks away leaves it.
IDLE_ENV = { "DOT_POPPER_SEED" => "7", "DOT_POPPER_KIT_PROBE" => "1" }.freeze
IDLE_SECONDS = 65
SHOT_SECONDS = [6, 15, 30, 45, 58].freeze
DEADLINE = 240
REPEATS = Integer(ENV.fetch("KIT_REPEATS", "3"))
# Each iPad runs REPEATS autoplay launches, one tilted one, then one idle
# launch.
MODES = ([:autoplay] * REPEATS + [:tilt, :idle]).freeze
GAME_ENV = { autoplay: AUTOPLAY_ENV, tilt: TILT_ENV, idle: IDLE_ENV }.freeze
SHOTS = { autoplay: SHOT_SECONDS, tilt: TILT_SHOT_SECONDS, idle: SHOT_SECONDS }.freeze
GAME_SHOTS = { autoplay: 4, tilt: TILT_GAME_SHOTS.size, idle: 0 }.freeze

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

def ipad_types(runtime, wanted)
  types = runtime.fetch("supportedDeviceTypes").select { |candidate| candidate["productFamily"] == "iPad" }
  puts "iPad types on #{runtime['name']}: #{types.map { |type| type['name'] }.join(', ')}"
  chosen = wanted.map { |name| types.find { |type| type["name"] == name } }.compact
  chosen = [types.last] if chosen.empty?
  chosen
end

# The app's process ID, as the Simulator's launchd lists it, or nil when
# it is not running. A Dot Popper whose Ruby program has returned stays
# running: SDL_RunApp keeps UIKit's loop going, so a relaunch would only
# bring the old process forward.
def app_pid(udid, identifier)
  listing, = Open3.capture2("xcrun", "simctl", "spawn", udid, "launchctl", "list")
  line = listing.lines.find { |entry| entry.include?("UIKitApplication:#{identifier}") } or return nil
  pid = line.split.first
  pid =~ /\A\d+\z/ ? Integer(pid) : nil
end

def shooter_done?(pid)
  @finished ||= {}
  return true if @finished[pid]

  @finished[pid] = !Process.waitpid(pid, Process::WNOHANG).nil?
end

def messages(udid, since, identifier, log)
  system("xcrun", "simctl", "spawn", udid, "log", "show", "--start", since, "--style", "ndjson", "--info", "--debug",
    "--predicate", "subsystem == \"#{identifier}\"", out: log, err: File::NULL)
  File.readlines(log).map do |line|
    begin
      entry = JSON.parse(line)
      entry.is_a?(Hash) && entry["eventMessage"] ? "#{entry['timestamp']} [#{entry['category']}] #{entry['eventMessage']}" : nil
    rescue JSON::ParserError
      nil
    end
  end.compact
end

# The seconds from +started+ to a log line's timestamp.
def seconds_after(started, line)
  (Time.parse(line[0, 31]) - started).round(1)
rescue ArgumentError
  nil
end

def message(line)
  line.sub(/\A\S+ \S+ \[\w+\] /, "")
end

results = {}
os = runtime
puts "== runtime #{os['name']} (#{os['identifier']})"
ipad_types(os, wanted).each do |type|
  name = type.fetch("name")
  slug = name.gsub(/[^A-Za-z0-9]+/, "-").sub(/-\z/, "")
  device_dir = File.join(out, slug)
  puts "== #{name} (#{type['identifier']})"
  udid = capture("xcrun", "simctl", "create", "dot-popper-#{slug}", type.fetch("identifier"), os.fetch("identifier")).strip
  begin
    system("xcrun", "simctl", "bootstatus", udid, "-b", out: File::NULL, exception: true)
    system("xcrun", "simctl", "install", udid, bundle, exception: true)
    previous_pids = []
    MODES.each.with_index(1) do |mode, attempt|
      game_env = GAME_ENV.fetch(mode)
      shot_seconds = SHOTS.fetch(mode)
      dir = File.join(device_dir, "run-#{attempt}-#{mode}")
      FileUtils.mkdir_p(dir)
      since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
      env = game_env.map { |key, value| ["SIMCTL_CHILD_#{key}", value] }.to_h
      launched, status = Open3.capture2(env, "xcrun", "simctl", "launch", udid, identifier)
      raise "simctl launch failed: #{launched}" unless status.success?

      pid = Integer(launched[/: (\d+)\s*\z/, 1])
      raise "launch #{attempt} reused process #{pid}" if previous_pids.include?(pid)

      previous_pids << pid
      started = Time.now
      puts "launched #{identifier} as process #{pid} with #{game_env.map { |key, value| "#{key}=#{value}" }.join(' ')}"
      log = File.join(dir, "subsystem.ndjson")
      puts "  launch #{attempt} of #{MODES.size}: #{mode}"
      # Screenshots from a process of their own, on the wall clock since
      # launch, so a slow log query never delays one (a Ruby thread did
      # wait for them); each file names the second it was taken at.
      script = shot_seconds.each_cons(2).inject("sleep #{shot_seconds.first}; shot #{shot_seconds.first}") do |text, (a, b)|
        "#{text}; sleep #{b - a}; shot #{b}"
      end
      shooter = Process.spawn("/bin/sh", "-c",
        "shot() { xcrun simctl io #{udid} screenshot \"#{dir}/simulator-$(printf %02d $1)s.png\" >/dev/null 2>&1; }; #{script}")
      lines = []
      loop do
        sleep 5
        lines = messages(udid, since, identifier, log)
        break if lines.any? { |line| line.include?("exited with status") } && shooter_done?(shooter)
        break if mode == :idle && Time.now - started > IDLE_SECONDS && shooter_done?(shooter)
        break if Time.now - started > DEADLINE
        crashes = Dir.glob(File.join(Dir.home, "Library/Logs/DiagnosticReports/#{executable}*"))
        break if crashes.any? { |crash| File.mtime(crash) >= started - 5 } && shooter_done?(shooter)
      end
      Process.wait(shooter) unless shooter_done?(shooter)
      sleep 2
      # Still running after IDLE_SECONDS is the idle launch's pass. Every
      # launch ends here, so the next one starts a new process.
      alive = app_pid(udid, identifier) == pid
      system("xcrun", "simctl", "terminate", udid, identifier, out: File::NULL, err: File::NULL)
      sleep 3
      lines = messages(udid, since, identifier, log)
      File.write(File.join(dir, "subsystem.log"), lines.join("\n") + "\n")
      puts lines.map { |line| "  #{line}" }
      File.write(File.join(dir, "process.log"), Open3.capture2e("xcrun", "simctl", "spawn", udid, "log", "show",
        "--start", since, "--style", "compact", "--info", "--predicate", "process == \"#{executable}\"").first)
      data, = Open3.capture2("xcrun", "simctl", "get_app_container", udid, identifier, "data")
      data = data.strip
      unless data.empty?
        FileUtils.cp_r(data, File.join(dir, "data-container"))
        puts "  data container files:"
        Dir.glob("Library/Application Support/**/*", base: File.join(dir, "data-container")).sort.each { |path| puts "    #{path}" }
      end
      Dir.glob(File.join(Dir.home, "Library/Logs/DiagnosticReports/#{executable}*")).each do |crash|
        FileUtils.cp(crash, dir) if File.mtime(crash) >= started - 5
      end
      crashed = !Dir.glob(File.join(dir, "*.ips")).empty?
      exited = lines.grep(/exited with status (\d+)/).last
      game_shots = lines.count { |line| line.include?("Dot Popper: screenshot") }
      bugs = lines.grep(/\[BUG\]/)
      tilts = lines.grep(/Dot Popper: tilt from /)
      perf = lines.grep(/Dot Popper: \d+ frames a second/)
      sensor = lines.map { |line| line[/kit probe: Sensor\.sensor\?\(:accelerometer\) (.*)\z/, 1] }.compact.first
      # What the game logged after its first Game Over, but for the host's
      # exit line: proof that it went on past it.
      after_game_over = tilts.empty? ? [] : lines.select { |line| line > tilts.first && !line.include?("exited with status") }
      clean = !crashed && bugs.empty?
      finished = !exited.nil? && exited.end_with?("status 0") && game_shots == GAME_SHOTS.fetch(mode)
      ok = case mode
      when :idle
        clean && exited.nil? && alive
      when :autoplay
        clean && finished && !tilts.empty? && tilts.all? { |line| line.end_with?("Dot Popper: tilt from none") } &&
          !perf.empty? && !after_game_over.empty?
      else
        clean && finished && !tilts.empty? &&
          tilts.all? { |line| line.include?("Dot Popper: tilt from a fake reading (DOT_POPPER_FAKE_TILT=") }
      end
      results["#{name} ##{attempt} #{mode}"] = { "pid" => pid, "exit" => exited, "running_at_end" => alive, "game_shots" => game_shots,
        "crash_report" => crashed, "bug_lines" => bugs, "sensor_accelerometer" => sensor,
        "tilt" => tilts.map { |line| "#{message(line)} (#{seconds_after(started, line)} s after launch)" },
        "lines_after_game_over" => after_game_over.size, "perf" => perf.map { |line| message(line) }, "ok" => ok }
    end
  ensure
    system("xcrun", "simctl", "shutdown", udid, out: File::NULL, err: File::NULL)
    system("xcrun", "simctl", "delete", udid, out: File::NULL, err: File::NULL)
  end
end
File.write(File.join(out, "results.json"), JSON.pretty_generate(results))
puts JSON.pretty_generate(results)
exit(results.values.all? { |result| result["ok"] } ? 0 : 1)
