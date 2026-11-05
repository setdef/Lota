# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs Dot Popper in new iPad Simulators, as the iOS spike's simulator.rb
# ran its game: creates and boots each iPad, installs and launches the
# app with the game's autoplay settings (SIMCTL_CHILD_ variables, which
# simctl passes to the app without the prefix), takes Simulator
# screenshots every few seconds, reads the app's os_log, and copies the
# app's data container (its save folder, the game's own shot-N.png files,
# rounds.csv) and any crash report into OUT. Plain Ruby 2.6, so the
# runner's own /usr/bin/ruby runs it with nothing installed.
#
#   ruby simulator.rb APP_BUNDLE IDENTIFIER EXECUTABLE OUT [DEVICE_TYPE_NAME ...]
require "fileutils"
require "json"
require "open3"

bundle, identifier, executable, out, *wanted = ARGV
FileUtils.mkdir_p(out)
$stdout.sync = true

GAME_ENV = {
  "DOT_POPPER_AUTOPLAY" => "1",
  "DOT_POPPER_QUIT_AFTER" => "45",
  "DOT_POPPER_SEED" => "7",
  "DOT_POPPER_SHOTS" => "3,12,25,38"
}.freeze
SHOT_SECONDS = [6, 12, 18, 26, 34, 42, 48].freeze
DEADLINE = 240

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

results = {}
os = runtime
puts "== runtime #{os['name']} (#{os['identifier']})"
ipad_types(os, wanted).each do |type|
  name = type.fetch("name")
  slug = name.gsub(/[^A-Za-z0-9]+/, "-").sub(/-\z/, "")
  dir = File.join(out, slug)
  FileUtils.mkdir_p(dir)
  puts "== #{name} (#{type['identifier']})"
  udid = capture("xcrun", "simctl", "create", "dot-popper-#{slug}", type.fetch("identifier"), os.fetch("identifier")).strip
  begin
    system("xcrun", "simctl", "bootstatus", udid, "-b", out: File::NULL, exception: true)
    system("xcrun", "simctl", "install", udid, bundle, exception: true)
    since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
    env = GAME_ENV.map { |key, value| ["SIMCTL_CHILD_#{key}", value] }.to_h
    launched, status = Open3.capture2(env, "xcrun", "simctl", "launch", udid, identifier)
    raise "simctl launch failed: #{launched}" unless status.success?

    pid = Integer(launched[/: (\d+)\s*\z/, 1])
    started = Time.now
    puts "launched #{identifier} as process #{pid} with #{GAME_ENV.map { |key, value| "#{key}=#{value}" }.join(' ')}"
    log = File.join(dir, "subsystem.ndjson")
    shots = SHOT_SECONDS.dup
    lines = []
    loop do
      sleep 1
      elapsed = Time.now - started
      if shots.first && elapsed >= shots.first
        second = shots.shift
        system("xcrun", "simctl", "io", udid, "screenshot", File.join(dir, format("simulator-%02ds.png", second)),
          out: File::NULL, err: File::NULL)
      end
      next unless (elapsed.to_i % 3).zero?

      lines = messages(udid, since, identifier, log)
      break if lines.any? { |line| line.include?("exited with status") } && shots.empty?
      break if elapsed > DEADLINE
    end
    sleep 2
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
      Dir.glob("**/*", base: File.join(dir, "data-container")).sort.each { |path| puts "    #{path}" }
    end
    Dir.glob(File.join(Dir.home, "Library/Logs/DiagnosticReports/#{executable}*")).each { |crash| FileUtils.cp(crash, dir) }
    exited = lines.grep(/exited with status (\d+)/).last
    game_shots = lines.count { |line| line.include?("Dot Popper: screenshot") }
    results[name] = { "exit" => exited, "game_shots" => game_shots,
                      "ok" => !exited.nil? && exited.end_with?("status 0") && game_shots == 4 }
  ensure
    system("xcrun", "simctl", "shutdown", udid, out: File::NULL, err: File::NULL)
    system("xcrun", "simctl", "delete", udid, out: File::NULL, err: File::NULL)
  end
end
File.write(File.join(out, "results.json"), JSON.pretty_generate(results))
puts JSON.pretty_generate(results)
exit(results.values.all? { |result| result["ok"] } ? 0 : 1)
