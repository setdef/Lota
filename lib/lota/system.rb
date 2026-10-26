# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The computer the game runs on, translated from love.system.
  #
  # Some of what a game needs belongs to the operating system rather than
  # to the game's window: the clipboard the player copies text with is
  # one.
  #
  # Lota opens LÖVE's system module before your conf.rb runs, whatever
  # your settings say, as LÖVE does (boot.lua's love.boot). Lota binds its
  # clipboard so far; LÖVE's system module also names the operating
  # system, counts processors, and reports the battery, which Lota binds
  # later.
  #
  # Use it to copy text for the player, as Lota's error screen copies an
  # error.
  #
  # === Example
  #
  #   Lota::System.clipboard_text = "Score: #{@score}"
  module System
    # Puts +text+ on the system's clipboard, matching
    # love.system.setClipboardText (src/modules/system/wrap_System.cpp,
    # w_setClipboardText).
    #
    # [text] String to copy.
    #
    # Raises RuntimeError when no window is open, as SDL needs one for the
    # clipboard (<tt>"A window must be created in order for
    # setClipboardText to function properly."</tt>), or when the system
    # module is not open.
    #
    # === Example
    #
    #   Lota::System.clipboard_text = "helloworld"
    def self.clipboard_text=(text)
      Native::System.set_clipboard_text(text)
    end

    # The text on the system's clipboard, matching
    # love.system.getClipboardText (src/modules/system/wrap_System.cpp,
    # w_getClipboardText), or an empty String when it holds none.
    #
    # Raises RuntimeError when no window is open, or when the system module
    # is not open.
    #
    # === Example
    #
    #   Lota::System.clipboard_text # => "helloworld"
    def self.clipboard_text
      Native::System.clipboard_text
    end
  end
end
