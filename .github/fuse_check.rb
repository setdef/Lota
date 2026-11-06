# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require_relative "../lib/lota/version"

# Checks what the app lota fuse built from one of the games in GAMES did
# when the fuse workflow ran it (.github/workflows/fuse.yml): that it quit
# with 3, ran fused, saved a file under its identity alone, where LÖVE's
# fused game saves (ADR 003, section 8), played its sound, and printed
# the lines that say its gems reached the app. Given the file of what the
# app printed to stderr and the name of an OpenAL Soft backend, it also
# checks that OpenAL Soft (run with ALSOFT_LOGLEVEL=3) chose that backend
# and opened a device through it.
#
#   ruby .github/fuse_check.rb STATUS OUTPUT_FILE GAME [ERROR_FILE BACKEND]
#
# With notices first, it checks the notices lota fuse wrote into the app
# (Lota::Notices) instead, in FOLDER, the folder of the app that holds its
# app folder (NAME.app/Contents/Resources on macOS), built for PLATFORM:
# that app/NOTICES.txt is there, opens with Lota's own license statement,
# names LÖVE, credits FreeType in its license's words, names OpenAL Soft
# with its source archive, whose SHA-256 is the one it gives, holds the
# text of every license it names, and that every path it names is in the
# app, Fledge's own notices beside it.
#
#   ruby .github/fuse_check.rb notices FOLDER PLATFORM

# Each game in test/games the workflow fuses: its identity, and the lines
# it prints that only its gems can print.
GAMES = {
  "fuse" => ["FuseCheck", []],
  "fuse_gems" => ["FuseCheckGems", ["rainbow: 3.0.0", "rainbow from the app: true", 'rainbow says: "\e[31mok\e[0m"']],
  "fuse_native" => ["FuseCheckNative", ["fast_blank: true false", "fast_blank from the app: true"]],
}.freeze

# The checks of the notices in the app in +folder+, built for +platform+,
# each to whether it passed.
def notices_checks(folder, platform)
  file = File.join(folder, "app", "NOTICES.txt")
  return { "the app holds app/NOTICES.txt" => false } unless File.file?(file)

  text = File.read(file, encoding: Encoding::UTF_8)
  puts "--- app/NOTICES.txt, #{text.bytesize} bytes, up to its license texts"
  puts text[0, text.index("\nLicense texts\n") || text.size].lines.grep_v(/\A  Copyright /)
  inside = -> (path) { File.exist?(File.join(folder, path.tr("\\", "/"))) }
  paths = text.scan(/^  (?:In this app|Source): (.+)$/).flatten +
    text.scan(/^(?:Compiled into Lota's extension|A library of its own), (.+):$/).flatten
  named = text.scan(/^  License: (.+)$/).flatten.flat_map { |line| line.split(", ") }
    .flat_map { |expression| expression.delete("()").split(/\s+(?:OR|AND|WITH)\s+/) }.uniq
    .grep_v(/\s/) # Lota's own line names its license in words after its identifier.
  source = text[/^OpenAL Soft 1\.24\.3\n(?:  .*\n)*?  Source: (.+)\n/, 1].to_s
  sha256 = text[/openal-soft-1\.24\.3\.tar\.bz2, SHA-256 (\h{64}),/, 1]
  {
    "the app holds app/NOTICES.txt" => true,
    "it was written for #{platform}" => text.include?("as it built this app for #{platform}."),
    "it opens with Lota's own license statement" => text.include?(
      "\n\nLota #{Lota::VERSION}\n  Copyright 2026 Kerrick Long <me@kerricklong.com>\n" \
        "  License: AGPL-3.0-or-later, the GNU Affero General Public License, version 3 or any later version\n"
    ),
    "it holds the AGPL's text" => text.include?("\n==== AGPL-3.0-or-later ====\n\nGNU AFFERO GENERAL PUBLIC LICENSE\n"),
    "it names LÖVE" => text.match?(/^LÖVE \S+\n  License: Zlib\n/),
    "it credits FreeType in its license's words" => text.match?(
      /^  Portions of this software are copyright © 20\d\d The FreeType Project \(www\.freetype\.org\)\. All rights reserved\. This software is based in part of the work of the FreeType Team\.$/
    ),
    "it names OpenAL Soft, a library of its own" => text.match?(/^A library of its own, .+:\n\nOpenAL Soft 1\.24\.3\n  License: LGPL-2\.0-or-later/),
    "it says where OpenAL Soft's source is" => !source.empty? && inside.call(source),
    "that source is the archive it names" => !source.empty? && inside.call(source) &&
      Digest::SHA256.file(File.join(folder, source.tr("\\", "/"))).hexdigest == sha256,
    "every path it names is in the app (#{paths.size})" => paths.size >= 3 && paths.all?(inside),
    "it holds the text of every license it names (#{named.size})" => named.all? { |id| text.include?("\n==== #{id} ====\n") },
    "Fledge's notices/NOTICES.txt is beside its app folder" => File.file?(File.join(folder, "notices", "NOTICES.txt")),
  }
end

if ARGV.first == "notices"
  checks = notices_checks(ARGV.fetch(1), ARGV.fetch(2))
  checks.each { |check, passed| puts "#{passed ? 'ok' : 'FAILED'}: #{check}" }
  exit(checks.values.all? ? 0 : 1)
end

status = Integer(ARGV.fetch(0))
output = File.read(ARGV.fetch(1))
identity, lines = GAMES.fetch(ARGV.fetch(2))
directory = output[/^save directory: (.*)$/, 1].to_s
checks = {
  "it quit with 3" => status == 3,
  "it ran fused" => output.include?("fused: true\n"),
  "its identity is t.identity" => output.include?("identity: #{identity}\n"),
  "it saved a file" => output.include?("saved: true\n"),
  "it saves under its identity alone" => File.basename(directory) == identity &&
    !directory.split(%r{[/\\]}).include?("Lota"),
  "it played its sound" => output.match?(/^[\w ]+: 1 source playing$/),
}
lines.each { |line| checks["it printed #{line}"] = output.lines.include?("#{line}\n") }
if ARGV.length > 3
  errors = File.read(ARGV.fetch(3))
  backend = ARGV.fetch(4)
  checks["OpenAL Soft chose its #{backend} backend"] = errors.include?(%(Initialized backend "#{backend}"))
  checks["OpenAL Soft opened a device"] = errors.match?(/^\[ALSOFT\] \(II\) Created device \S+, "[^"]+"/)
end
checks.each { |check, passed| puts "#{passed ? 'ok' : 'FAILED'}: #{check}" }
puts "yjit: #{output[/^yjit: (.*)$/, 1]}"
exit(checks.values.all? ? 0 : 1)
