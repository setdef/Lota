# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Loaded with ruby -r into lota run by test/native/lota_run_test.rb, for a
# game that raises: wraps Lota's error handler, as a game may with prepend
# (ADR 003, section 2), so that once the error screen is up a quit waits
# in the event queue, and the screen's first frame ends the program, as a
# player closing the window would.
require "lota"

# The wrapper around Lota.errorhandler.
module QuitOnError
  # Shows the error screen as Lota's handler does, then queues a quit.
  def errorhandler(msg)
    frame = super
    puts "error screen #{frame ? 'shown' : 'not shown'}"
    Lota::Event.quit if Lota.event
    frame
  end
end

Lota.singleton_class.prepend(QuitOnError)
