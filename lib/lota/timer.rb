# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # Time between frames, translated from love.timer.
  #
  # A game moves things by how much time has passed, not by how many
  # frames have, or it runs faster on a faster machine. Something has to
  # measure each frame and hand the difference to the game.
  #
  # Lota::Timer is that clock. Lota's game loop steps it once a frame and
  # passes the result to your update callback as +dt+, and sleeps a
  # millisecond a frame with it, as LÖVE's loop does.
  #
  # Use it to measure frames yourself, or to sleep, when you write a game
  # loop of your own.
  #
  # === Examples
  #
  #   def Lota.update(dt)
  #     @x += 100 * dt # 100 pixels a second, however fast the frames
  #   end
  #
  #   dt = Lota::Timer.step
  #   Lota::Timer.sleep(0.001)
  module Timer
    # Measures the time since the last step, in seconds, and starts the
    # next measurement, matching love.timer.step
    # (src/modules/timer/wrap_Timer.cpp, w_step).
    #
    # Lota's loop steps the timer once before the first frame and once
    # each frame, so stepping it yourself inside a callback shortens the
    # +dt+ the next update receives. Raises RuntimeError when the timer
    # module is not open, as when <tt>t.modules.timer = false</tt>.
    #
    # === Example
    #
    #   dt = Lota::Timer.step # => 0.0166...
    def self.step
      Native::Timer.step
    end

    # Pauses the program for +seconds+, matching love.timer.sleep
    # (src/modules/timer/wrap_Timer.cpp, w_sleep).
    #
    # [seconds] Float or Integer, how long to sleep.
    #
    # The operating system decides how precisely it wakes the program, so
    # a short sleep can last longer than asked. Raises RuntimeError when
    # the timer module is not open.
    #
    # === Example
    #
    #   Lota::Timer.sleep(0.001)
    def self.sleep(seconds)
      Native::Timer.sleep(seconds)
    end
  end
end
