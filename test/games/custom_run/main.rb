# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Replaces Lota's game loop with its own, as a LÖVE game can replace
# love.run, for test/native/lota_run_test.rb. Its first frame drops
# canvases and collects them on another thread, which queues their
# releases for the main thread (ADR 001, section 5); its second frame
# reports whether Lota drained the queue between frames, then quits with
# status 5.
$stdout.sync = true

def Lota.run
  puts "run"
  frames = 0
  lambda do
    frames += 1
    puts "frame #{frames}"
    return 5 if frames == 3

    if frames == 1
      GC.disable
      Fiber.new { 100.times { Lota::Graphics::Canvas.new(4, 4) } }.resume
      Thread.new { GC.start(full_mark: true, immediate_sweep: true) }.join
      GC.enable
    end
    puts "queued #{Lota::Native.queued_releases.positive? ? 'some' : 'none'}"
    nil
  end
end
