# frozen_string_literal: true

# Runs the spike's app in a new iPad Simulator (and then an iPhone), as
# Fledge's tasks/mobile_parity/ios.rb runs its apps: creates and boots
# one, installs and launches the app, reads its os_log, takes screenshots
# once it has drawn, and keeps everything in OUT.
#
#   ruby simulator.rb APP_BUNDLE IDENTIFIER NAME OUT
require "fileutils"
require "json"
require "open3"

bundle, identifier, name, out = ARGV
FileUtils.mkdir_p(out)
$stdout.sync = true

def capture(*command)
  output, status = Open3.capture2(*command)
  raise "#{command.join(' ')} failed" unless status.success?

  output
end

def newest(family)
  runtimes = JSON.parse(capture("xcrun", "simctl", "list", "runtimes", "-j")).fetch("runtimes")
  runtime = runtimes.select { |candidate| candidate["platform"] == "iOS" && candidate["isAvailable"] }
    .max_by { |candidate| Gem::Version.new(candidate.fetch("version")) } or raise "no iOS Simulator runtime"
  id = runtime.fetch("identifier")
  devices = JSON.parse(capture("xcrun", "simctl", "list", "devices", "available", "-j")).fetch("devices").fetch(id, [])
  set_up = devices.map { |device| device.fetch("deviceTypeIdentifier") }
  types = runtime.fetch("supportedDeviceTypes").select { |candidate| candidate["productFamily"] == family }
  type = types.find { |candidate| set_up.include?(candidate.fetch("identifier")) } || types.last or raise "no #{family}"
  [id, type.fetch("identifier")]
end

def messages(udid, since, pid, identifier, log)
  system("xcrun", "simctl", "spawn", udid, "log", "show", "--start", since, "--style", "ndjson", "--info", "--debug",
    "--predicate", "subsystem == \"#{identifier}\"", out: log, err: File::NULL)
  File.readlines(log).filter_map do |line|
    entry = JSON.parse(line)
    entry["eventMessage"] if entry.is_a?(Hash) && entry["processID"] == pid
  rescue JSON::ParserError
    nil
  end
end

passed = %w[iPad iPhone].map do |family|
  runtime, type = newest(family)
  puts "== #{family}: #{type} on #{runtime}"
  udid = capture("xcrun", "simctl", "create", "lota-spike-#{family}", type, runtime).strip
  begin
    system("xcrun", "simctl", "bootstatus", udid, "-b", out: File::NULL, exception: true)
    system("xcrun", "simctl", "install", udid, bundle, exception: true)
    since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
    launched = capture("xcrun", "simctl", "launch", udid, identifier)
    pid = Integer(launched[/: (\d+)\s*\z/, 1])
    puts "launched #{identifier} as process #{pid}"
    log = File.join(out, "#{family}.ndjson")
    deadline = Time.now + 180
    shots = 0
    lines = []
    loop do
      sleep 3
      lines = messages(udid, since, pid, identifier, log)
      if shots < 2 && lines.any? { |line| line.include?("LotaSpike drew frame") }
        shots += 1
        system("xcrun", "simctl", "io", udid, "screenshot", File.join(out, "#{family}-#{shots}.png"))
      end
      break if lines.any? { |line| line.include?("exited with status") }
      break if Time.now > deadline
    end
    puts lines.map { |line| "  #{line}" }
    File.write(File.join(out, "#{family}-process.log"), Open3.capture2e("xcrun", "simctl", "spawn", udid, "log", "show",
      "--start", since, "--style", "compact", "--predicate", "process == \"#{name}\"").first)
    Dir.glob(File.join(Dir.home, "Library/Logs/DiagnosticReports/#{name}*")).each { |crash| FileUtils.cp(crash, out) }
    lines.any? { |line| line.include?("LotaSpike drew frame 60") }
  ensure
    system("xcrun", "simctl", "shutdown", udid, out: File::NULL, err: File::NULL)
    system("xcrun", "simctl", "delete", udid, out: File::NULL, err: File::NULL)
  end
end
puts "drew 60 frames on: #{%w[iPad iPhone].zip(passed).map { |family, ok| "#{family} #{ok}" }.join(', ')}"
exit(passed.all? ? 0 : 1)
