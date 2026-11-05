# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

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

# Each game in test/games the workflow fuses: its identity, and the lines
# it prints that only its gems can print.
GAMES = {
  "fuse" => ["FuseCheck", []],
  "fuse_gems" => ["FuseCheckGems", ["rainbow: 3.0.0", "rainbow from the app: true", 'rainbow says: "\e[31mok\e[0m"']],
  "fuse_native" => ["FuseCheckNative", ["fast_blank: true false", "fast_blank from the app: true"]],
}.freeze

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
