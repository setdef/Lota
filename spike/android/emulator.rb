# frozen_string_literal: true

# Runs an app Fledge built on the Android emulator adb sees, and keeps
# what it did: installs the APK, starts its activity with environment
# variables as intent extras (MainActivity's lota.env.NAME), reads what
# the app prints from logcat, under its package name, takes screenshots
# and taps the screen on a schedule counted from the first line that
# matches --ready, and stops when the app says it exited or after
# --timeout seconds. Everything goes in OUT: logcat.txt (all of it),
# app.txt (the app's lines), device.txt, and shot-*.png.
#
#   ruby emulator.rb APK PACKAGE OUT [--env NAME=VALUE]... [--shot SECONDS]...
#     [--tap SECONDS:XFRACTION:YFRACTION]... [--pop] [--ready REGEX] [--timeout SECONDS]
#     [--expect REGEX]... [--pull REGEX]
#
# --pop taps where the app last printed "kit probe: dot at X, Y in WxH"
# (graphics units in a window W by H), until it prints "kit probe: event
# Popped", at most five times. --pull copies, with run-as, every file the
# app names in a line the REGEX's first group captures. It exits 1 unless
# every --expect matches a line of the app's.

require "fileutils"
require "open3"

apk, package, out, *rest = ARGV
abort "usage: emulator.rb APK PACKAGE OUT [options]" unless apk && package && out
envs = []
shots = []
taps = []
expects = []
commands = []
pop = false
ready = /loaded/
timeout = 240.0
pull = nil
until rest.empty?
  option = rest.shift
  case option
  when "--env" then envs << rest.shift.split("=", 2)
  when "--shot" then shots << Float(rest.shift)
  when "--tap" then taps << rest.shift.split(":").map { Float(it) }
  when "--shell"
    seconds, command = rest.shift.split(":", 2)
    commands << [Float(seconds), command.gsub("PACKAGE", package).split]
  when "--pop" then pop = true
  when "--ready" then ready = Regexp.new(rest.shift)
  when "--timeout" then timeout = Float(rest.shift)
  when "--expect" then expects << Regexp.new(rest.shift)
  when "--pull" then pull = Regexp.new(rest.shift)
  else abort "emulator.rb: unknown option #{option}"
  end
end
FileUtils.mkdir_p(out)

def adb(*arguments, allow_failure: false)
  output, status = Open3.capture2e("adb", *arguments)
  abort "adb #{arguments.join(' ')} failed:\n#{output}" unless status.success? || allow_failure
  output
end

def say(message)
  puts "#{Time.now.utc.strftime('%H:%M:%S.%L')} #{message}"
  $stdout.flush
end

adb("wait-for-device")
device = {
  "abi" => adb("shell", "getprop", "ro.product.cpu.abi").strip,
  "sdk" => adb("shell", "getprop", "ro.build.version.sdk").strip,
  "release" => adb("shell", "getprop", "ro.build.version.release").strip,
  "page size" => adb("shell", "getconf", "PAGE_SIZE").strip,
  "screen" => adb("shell", "wm", "size").strip,
  "density" => adb("shell", "wm", "density").strip,
  "ro.opengles.version" => adb("shell", "getprop", "ro.opengles.version").strip,
  "ro.hardware.egl" => adb("shell", "getprop", "ro.hardware.egl").strip,
  "ro.hardware.vulkan" => adb("shell", "getprop", "ro.hardware.vulkan").strip,
  "GLES" => adb("shell", "dumpsys", "SurfaceFlinger", allow_failure: true).lines.grep(/GLES|EGL/).first(4).join.strip,
}
File.write(File.join(out, "device.txt"), device.map { |key, value| "#{key}: #{value}" }.join("\n") + "\n")
device.each { |key, value| say "device #{key}: #{value}" }
width, height = device.fetch("screen")[/(\d+)x(\d+)\s*\z/].split("x").map(&:to_i)

# Android's one-time notice for an app that hides the system bars would
# take the first tap (Fledge's ADR 025, section 6).
adb("shell", "settings", "put", "secure", "immersive_mode_confirmations", "confirmed")
adb("logcat", "-G", "16M", allow_failure: true)
say adb("install", "-r", "-g", apk).lines.last.to_s.strip
adb("logcat", "-c")
extras = envs.flat_map { |name, value| ["--es", "lota.env.#{name}", value] }
say adb("shell", "am", "start", "-W", "-n", "#{package}/org.setdef.fledge.host.MainActivity", *extras).strip

def app_lines(package)
  adb("logcat", "-d", "-v", "raw", "-s", "#{package}:V").lines.map(&:chomp).reject { it.start_with?("--------- ") }
end

started = Time.now
seen = 0
origin = nil
pops = 0
last_tap = nil
pending_shots = shots.sort
pending_taps = taps.sort_by(&:first)
commands.sort_by!(&:first)
shot_number = 0
loop do
  lines = app_lines(package)
  lines.drop(seen).each { |line| say "app: #{line}" }
  seen = lines.size
  origin ||= Time.now if lines.any? { ready.match?(it) }
  elapsed = origin && (Time.now - origin)
  while elapsed && pending_shots.first && elapsed >= pending_shots.first
    pending_shots.shift
    shot_number += 1
    path = File.join(out, "shot-#{shot_number}.png")
    File.binwrite(path, Open3.capture2("adb", "exec-out", "screencap", "-p", binmode: true).first)
    say "screenshot #{path} at #{elapsed.round(1)} s, #{File.size(path)} bytes"
  end
  while elapsed && pending_taps.first && elapsed >= pending_taps.first.first
    _, x, y = pending_taps.shift
    px = (x * width).round
    py = (y * height).round
    adb("shell", "input", "tap", px.to_s, py.to_s)
    say "tapped #{px}, #{py} at #{elapsed.round(1)} s"
  end
  while elapsed && commands.first && elapsed >= commands.first.first
    _, command = commands.shift
    say "adb shell #{command.join(' ')} at #{elapsed.round(1)} s: #{adb('shell', *command, allow_failure: true).strip}"
  end
  if pop && pops < 5 && lines.none? { it.include?("kit probe: event Popped") }
    probe = lines.reverse.find { it.include?("kit probe: dot at") }
    match = probe&.match(/dot at ([\d.]+), ([\d.]+) in ([\d.]+)x([\d.]+)/)
    if match && probe != last_tap
      last_tap = probe
      x, y, w, h = match.captures.map { Float(it) }
      px = (x / w * width).round
      py = (y / h * height).round
      adb("shell", "input", "tap", px.to_s, py.to_s)
      pops += 1
      say "tapped the dot at #{x.round}, #{y.round} of #{w.round}x#{h.round}: #{px}, #{py} on the screen"
    end
  end
  break if lines.any? { it.include?("exited with status") }

  if Time.now - started > 20 && adb("shell", "pidof", package, allow_failure: true).strip.empty?
    say "the app's process is gone"
    break
  end
  if Time.now - started > timeout
    say "timed out after #{timeout} s"
    break
  end
  sleep 0.25
end

File.write(File.join(out, "logcat.txt"), adb("logcat", "-d", "-v", "threadtime"))
lines = app_lines(package)
File.write(File.join(out, "app.txt"), lines.join("\n") + "\n")
if pull
  lines.filter_map { it[pull, 1] }.uniq.each do |path|
    copy = File.join(out, "game-#{File.basename(path)}")
    data, status = Open3.capture2("adb", "exec-out", "run-as", package, "cat", path, binmode: true)
    if status.success?
      File.binwrite(copy, data)
      say "pulled #{path}: #{data.bytesize} bytes"
    else
      say "could not pull #{path}"
    end
  end
end
crashes = File.read(File.join(out, "logcat.txt")).lines.grep(/FATAL|Fatal signal|AndroidRuntime|DEBUG\s*:|libc\s*:/)
say "crash lines:\n#{crashes.first(80).join}" unless crashes.empty?
missing = expects.reject { |pattern| lines.any? { pattern.match?(it) } }
missing.each { say "missing: #{it.source}" }
exit(missing.empty? ? 0 : 1)
