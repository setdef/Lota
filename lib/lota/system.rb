# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
  # your settings say, as LÖVE does (boot.lua's love.boot).
  #
  # Use it to copy text for the player, as Lota's error screen copies an
  # error, to ask for the operating system, the processors, the memory,
  # the battery, or the player's locales, and to open a web page or
  # vibrate a phone.
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

    # The name of the operating system the game runs on, matching
    # love.system.getOS (src/modules/system/wrap_System.cpp, w_getOS):
    # <tt>"OS X"</tt> on macOS, as LÖVE names it, or <tt>"Windows"</tt>,
    # <tt>"Linux"</tt>, <tt>"Android"</tt>, or <tt>"iOS"</tt>.
    #
    # === Example
    #
    #   Lota::System.os # => "OS X"
    def self.os
      Native::System.os
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

    # The number of logical processors, as an Integer, matching
    # love.system.getProcessorCount (src/modules/system/wrap_System.cpp,
    # w_getProcessorCount). Raises RuntimeError when the system module is
    # not open.
    #
    # === Example
    #
    #   Lota::System.processor_count # => 8
    def self.processor_count
      Native::System.processor_count
    end

    # The system's memory in megabytes, as an Integer, matching
    # love.system.getMemorySize (src/modules/system/wrap_System.cpp,
    # w_getMemorySize). Raises RuntimeError when the system module is not
    # open.
    #
    # === Example
    #
    #   Lota::System.memory_size # => 16384
    def self.memory_size
      Native::System.memory_size
    end

    # The state of the battery, matching love.system.getPowerInfo
    # (src/modules/system/wrap_System.cpp, w_getPowerInfo), as an Array of
    # three values (rule 4 of doc/contributors/design/translation.md).
    #
    # The first is the state as a Symbol: +:unknown+, +:battery+ (on
    # battery), +:nobattery+ (on mains power, with no battery),
    # +:charging+, or +:charged+. The second is the percentage left as an
    # Integer, and the third the seconds left as an Integer, each +nil+
    # when the system cannot tell. Raises RuntimeError when the system
    # module is not open.
    #
    # === Example
    #
    #   state, percent, seconds = Lota::System.power_info # => [:charging, 80, nil]
    def self.power_info
      state, percent, seconds = Native::System.power_info
      [state.to_s.to_sym, (percent if percent.is_a?(Integer)), (seconds if seconds.is_a?(Integer))]
    end

    # Opens +url+ in the player's browser or the program their system
    # opens it with, matching love.system.openURL
    # (src/modules/system/wrap_System.cpp, w_openURL).
    #
    # [url] String, such as <tt>"https://example.com"</tt>.
    #
    # Returns whether the system accepted it. Raises TypeError for a value
    # that is not a String, and RuntimeError when the system module is not
    # open.
    #
    # === Example
    #
    #   Lota::System.open_url("https://example.com")
    def self.open_url(url)
      Native::System.open_url(url)
    end

    # Makes a phone or tablet vibrate, matching love.system.vibrate
    # (src/modules/system/wrap_System.cpp, w_vibrate). A computer does
    # nothing.
    #
    # [seconds] Float or Integer, how long to vibrate; 0.5 by default.
    #
    # Returns +nil+. Raises RuntimeError when the system module is not
    # open.
    #
    # === Example
    #
    #   Lota::System.vibrate(0.2)
    def self.vibrate(seconds = 0.5)
      Native::System.vibrate(seconds)
    end

    # Whether the player is playing music of their own in the background,
    # which a game might then leave unmuted, matching
    # love.system.hasBackgroundMusic (src/modules/system/wrap_System.cpp,
    # w_hasBackgroundMusic). Raises RuntimeError when the system module is
    # not open.
    #
    # === Example
    #
    #   Lota::Audio.volume = 0 if Lota::System.background_music?
    def self.background_music?
      Native::System.background_music?
    end

    # The languages the player prefers, most preferred first, as an Array
    # of Strings such as <tt>["en-US", "de"]</tt>, matching
    # love.system.getPreferredLocales (src/modules/system/wrap_System.cpp,
    # w_getPreferredLocales). Raises RuntimeError when the system module is
    # not open.
    #
    # === Example
    #
    #   Lota::System.preferred_locales # => ["en-US"]
    def self.preferred_locales
      Native::System.preferred_locales
    end
  end
end
