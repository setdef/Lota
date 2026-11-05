# frozen_string_literal: true

# Assembles the phone kit in OUT from the build's artifact (APKS) and the
# emulator's (EMULATOR): the APKs, their SHA256SUMS, README.txt, and
# android-results.txt with its header filled in from BUILD-INFO.txt and a
# summary of what the emulator's Dot Popper runs printed.
#
#   ruby kit.rb APKS EMULATOR OUT
require "digest"
require "fileutils"

apks, emulator, out = ARGV
here = __dir__
FileUtils.mkdir_p(out)
info = File.readlines(File.join(apks, "BUILD-INFO.txt"), chomp: true).to_h { it.split("=", 2) }
%w[DotPopper-debug.apk LotaSpike-debug.apk].each { FileUtils.cp(File.join(apks, it), out) }
File.write(File.join(out, "SHA256SUMS"),
  %w[DotPopper-debug.apk LotaSpike-debug.apk].map { "#{Digest::SHA256.file(File.join(out, it)).hexdigest}  #{it}\n" }.join)
FileUtils.cp(File.join(here, "README.txt"), out)

wanted = /starts Ruby|LotaSpike loaded on|another thread|renderer|kit probe: frame 60|touchpressed|keypressed|focus|visible|Popped|screenshot|exited with status|audio/
summary = Dir[File.join(emulator, "*", "app.txt")].sort.flat_map do |path|
  run = File.basename(File.dirname(path))
  lines = File.readlines(path, chomp: true).grep(wanted).uniq.first(25)
  device = File.read(File.join(File.dirname(path), "device.txt")).lines.first(4).map(&:strip).join("; ")
  ["  #{run} (#{device}):", *lines.map { "    #{it}" }]
end
results = File.read(File.join(here, "android-results.txt"))
  .gsub("@@DOT_POPPER_REF@@", info.fetch("DOT_POPPER_REF")).gsub("@@DOT_POPPER_SHA@@", info.fetch("DOT_POPPER_SHA"))
  .gsub("@@LOTA_SHA@@", info.fetch("LOTA_SHA")).gsub("@@FLEDGE_REF@@", info.fetch("FLEDGE_REF"))
  .gsub("@@RUN_URL@@", info.fetch("RUN_URL"))
  .gsub("@@APK_SHA256@@", Digest::SHA256.file(File.join(out, "DotPopper-debug.apk")).hexdigest)
  .gsub("@@EMULATOR_SUMMARY@@", summary.join("\n"))
File.write(File.join(out, "android-results.txt"), results)
FileUtils.mkdir_p(File.join(out, "emulator"))
Dir[File.join(emulator, "*", "{app.txt,device.txt,*.png}")].each do |path|
  FileUtils.cp(path, File.join(out, "emulator", "#{File.basename(File.dirname(path))}-#{File.basename(path)}"))
end
puts results
