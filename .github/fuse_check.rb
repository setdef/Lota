# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Checks what the app lota fuse built from test/games/fuse did when the
# fuse workflow ran it (.github/workflows/fuse.yml): that it quit with 3,
# ran fused, saved a file under its identity alone, where LÖVE's fused
# game saves (ADR 003, section 8), and played its sound.
#
#   ruby .github/fuse_check.rb STATUS OUTPUT_FILE

status = Integer(ARGV.fetch(0))
output = File.read(ARGV.fetch(1))
directory = output[/^save directory: (.*)$/, 1].to_s
checks = {
  "it quit with 3" => status == 3,
  "it ran fused" => output.include?("fused: true\n"),
  "its identity is t.identity" => output.include?("identity: FuseCheck\n"),
  "it saved a file" => output.include?("saved: true\n"),
  "it saves under its identity alone" => File.basename(directory) == "FuseCheck" &&
    !directory.split(%r{[/\\]}).include?("Lota"),
  "it played its sound" => output.match?(/^[\w ]+: 1 source playing$/),
}
checks.each { |check, passed| puts "#{passed ? 'ok' : 'FAILED'}: #{check}" }
puts "yjit: #{output[/^yjit: (.*)$/, 1]}"
exit(checks.values.all? ? 0 : 1)
