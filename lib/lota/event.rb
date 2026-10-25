# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The queue of things that happened to the game, translated from
  # love.event.
  #
  # Keys go down, the window gains focus, the player clicks the close
  # button. The operating system reports each of these whenever it likes,
  # while a game wants to hear about them at one point in each frame.
  #
  # Lota::Event keeps them in a queue. Lota's game loop pumps the queue
  # once a frame and calls your callbacks for what it finds, such as
  # +keypressed+ or +quit+.
  #
  # Use it to end the game, or to pump the queue yourself.
  #
  # === Examples
  #
  #   def Lota.keypressed(key)
  #     Lota::Event.quit if key == :escape
  #   end
  #
  #   # Quit with a status for the shell.
  #   Lota::Event.quit(2)
  module Event
    # Gathers what the operating system has reported into the queue,
    # matching love.event.pump (src/modules/event/wrap_Event.cpp, w_pump).
    #
    # [wait_timeout] Float or Integer, the seconds to wait for the first
    #   event when none has arrived; 0, the default, does not wait, and a
    #   negative or infinite timeout waits for good.
    #
    # Lota's loop pumps once a frame. Pumping while a canvas is the target
    # raises RuntimeError, because some systems draw the window during the
    # pump. Raises RuntimeError when the event module is not open.
    #
    # === Example
    #
    #   Lota::Event.pump
    def self.pump(wait_timeout = 0)
      Native::Event.pump(wait_timeout)
    end

    # Asks the game to quit, matching love.event.quit
    # (src/modules/event/wrap_Event.cpp, w_quit).
    #
    # [exit_status] Integer the program exits with; 0 when +nil+ or left
    #   out.
    #
    # The request joins the queue. On the next frame the loop calls your
    # +quit+ callback, which can return a truthy value to keep the game
    # running, as LÖVE's love.quit can. Returns +true+. LÖVE also takes
    # <tt>"restart"</tt> to start the game again; Lota does not restart
    # games yet.
    #
    # === Example
    #
    #   Lota::Event.quit     # exits with 0
    #   Lota::Event.quit(1)  # exits with 1
    def self.quit(exit_status = nil)
      Native::Event.quit(exit_status&.to_f)
    end
  end
end
