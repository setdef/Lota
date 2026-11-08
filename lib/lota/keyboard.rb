# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The keyboard, translated from love.keyboard.
  #
  # A game that moves a paddle while an arrow key is held cannot wait for
  # a key press event: the press arrives once, and the paddle must keep
  # moving every frame until the key comes up.
  #
  # Lota::Keyboard answers whether a key is down right now, from the same
  # keyboard state LÖVE reads, which Lota's loop brings up to date each
  # frame when it handles events. Unlike Lota::Graphics, it answers on
  # any thread.
  #
  # Use it in your update callback for movement and other held keys. Use
  # the +keypressed+ callback for one-time actions, such as jumping or
  # quitting. It also turns key repeat and text input on and off, and
  # translates between the key a player's layout types and the physical
  # key it sits on.
  #
  # === Example
  #
  #   def Lota.update(dt)
  #     @x += 300 * dt if Lota::Keyboard.down?(:right)
  #     @x -= 300 * dt if Lota::Keyboard.down?(:left)
  #   end
  module Keyboard
    # Whether any of +keys+ is down, matching love.keyboard.isDown
    # (src/modules/keyboard/wrap_Keyboard.cpp, w_isDown).
    #
    # [keys] Symbols naming keys by LÖVE's key constants, such as +:a+,
    #   +:space+, +:right+, or +:lshift+; Strings work too. LÖVE's table of
    #   keys is one Array.
    #
    # A key constant names the character a key types on the player's
    # keyboard layout, so +:a+ follows the key labeled A wherever it is.
    # A name that is not one of LÖVE's key constants counts as the key of
    # its first character, as in LÖVE 12, so +:apple+ is +:a+. With no keys
    # it returns +false+.
    #
    # Raises ArgumentError ("Invalid key constant: ...") for an empty name
    # or one that is not UTF-8, and RuntimeError when the keyboard module is
    # not open, as when <tt>t.modules.keyboard = false</tt>.
    #
    # === Examples
    #
    #   Lota::Keyboard.down?(:space)          # => false
    #   Lota::Keyboard.down?(:lshift, :rshift) # either shift key
    #   Lota::Keyboard.down?([:lshift, :rshift])
    def self.down?(*keys)
      Native::Keyboard.down?(names(keys))
    end

    # Whether any of +scancodes+ is down, matching
    # love.keyboard.isScancodeDown (src/modules/keyboard/
    # wrap_Keyboard.cpp, w_isScancodeDown).
    #
    # [scancodes] Symbols naming physical keys by LÖVE's scancode
    #   constants, such as +:a+, +:space+, or +:lshift+; Strings work too.
    #   LÖVE's table of scancodes is one Array.
    #
    # A scancode names a key by where it sits on the keyboard, whatever
    # character the player's layout types there, so +:w+ is the key above
    # +:s+ even on a layout that types another letter on it. Use it for
    # movement keys that must keep their shape on every layout. With no
    # scancodes it returns +false+.
    #
    # Raises ArgumentError ("Invalid scancode: ...") for a name that is not
    # a scancode constant, and RuntimeError when the keyboard module is not
    # open.
    #
    # === Example
    #
    #   Lota::Keyboard.scancode_down?(:w) # => false
    def self.scancode_down?(*scancodes)
      Native::Keyboard.scancode_down?(names(scancodes))
    end

    # Turns key repeat on or off, matching love.keyboard.setKeyRepeat
    # (src/modules/keyboard/wrap_Keyboard.cpp, w_setKeyRepeat).
    #
    # [enable] +true+ to send +keypressed+ again for a key the player holds
    #   down, +false+ (the default) to send it once.
    #
    # Raises RuntimeError when the keyboard module is not open.
    #
    # === Example
    #
    #   Lota::Keyboard.key_repeat = true
    def self.key_repeat=(enable)
      Native::Keyboard.set_key_repeat(enable)
    end

    # Whether key repeat is on, matching love.keyboard.hasKeyRepeat
    # (src/modules/keyboard/wrap_Keyboard.cpp, w_hasKeyRepeat).
    #
    # Raises RuntimeError when the keyboard module is not open.
    #
    # === Example
    #
    #   Lota::Keyboard.key_repeat? # => false
    def self.key_repeat?
      Native::Keyboard.key_repeat?
    end

    # Turns text input on or off, matching love.keyboard.setTextInput
    # (src/modules/keyboard/wrap_Keyboard.cpp, w_setTextInput), which
    # ADR 001's rule 6 makes a writer for its form with a rectangle.
    #
    # [enable] +true+ to receive the +textinput+ callback for the text the
    #   player types, or +false+ to stop. Or an Array of +enable+ and the
    #   +x+, +y+, +width+, and +height+ of the rectangle in which the text
    #   appears, in the window's coordinates, which tells an on-screen
    #   keyboard or an input method where to show itself.
    #
    # Text input starts off, on a computer as on a phone, so a game that
    # wants the +textinput+ callback turns it on, in its +load+ or when a
    # text field gains focus. LÖVE turns it on only when a game asks
    # (src/modules/keyboard/sdl/Keyboard.cpp, Keyboard::setTextInput),
    # and SDL 3, unlike SDL 2, no longer turns it on for a new window
    # (SDL 3.4.10, docs/README-migration.md, SDL_keyboard.h), so a game
    # written for LÖVE 11 that never asks receives no text, though
    # +keypressed+ still arrives. Turning it on may show an on-screen
    # keyboard or an input method. It changes nothing while no window is
    # open. Raises ArgumentError for a
    # rectangle of fewer than four numbers, and RuntimeError when the
    # keyboard module is not open.
    #
    # === Examples
    #
    #   Lota::Keyboard.text_input = true
    #   Lota::Keyboard.text_input = true, 10, 200, 300, 24
    def self.text_input=(enable)
      if enable.is_a?(Array)
        flag, x, y, width, height = enable
        Native::Keyboard.set_text_input(flag, x, y, width, height)
      else
        Native::Keyboard.set_text_input(enable)
      end
    end

    # Whether text input is on, matching love.keyboard.hasTextInput
    # (src/modules/keyboard/wrap_Keyboard.cpp, w_hasTextInput). It is
    # +false+ while no window is open, and +false+ when a window opens,
    # until the game turns it on with text_input=.
    #
    # Raises RuntimeError when the keyboard module is not open.
    #
    # === Example
    #
    #   Lota::Keyboard.text_input? # => false
    def self.text_input?
      Native::Keyboard.text_input?
    end

    # Whether the system has an on-screen keyboard, matching
    # love.keyboard.hasScreenKeyboard (src/modules/keyboard/
    # wrap_Keyboard.cpp, w_hasScreenKeyboard): true on a phone or tablet,
    # and usually false on a computer.
    #
    # Raises RuntimeError when the keyboard module is not open.
    #
    # === Example
    #
    #   Lota::Keyboard.screen_keyboard? # => false
    def self.screen_keyboard?
      Native::Keyboard.screen_keyboard?
    end

    # Whether the on-screen keyboard is showing, matching
    # love.keyboard.isScreenKeyboardVisible (src/modules/keyboard/
    # wrap_Keyboard.cpp, w_isScreenKeyboardVisible). It is +false+ while
    # no window is open.
    #
    # Raises RuntimeError when the keyboard module is not open.
    #
    # === Example
    #
    #   Lota::Keyboard.screen_keyboard_visible? # => false
    def self.screen_keyboard_visible?
      Native::Keyboard.screen_keyboard_visible?
    end

    # The scancode of the physical key that types +key+ on the player's
    # layout, matching love.keyboard.getScancodeFromKey
    # (src/modules/keyboard/wrap_Keyboard.cpp, w_getScancodeFromKey), as a
    # Symbol.
    #
    # [key] Symbol (or String) naming the key by LÖVE's key constants.
    #
    # Raises ArgumentError ("Invalid key constant: ...") for a name that is
    # no key constant, RuntimeError ("Unknown scancode.") for a key with
    # no scancode, and RuntimeError when the keyboard module is not open.
    #
    # === Example
    #
    #   Lota::Keyboard.scancode_from_key(:z) # => :z (:y on a German layout)
    def self.scancode_from_key(key)
      Native::Keyboard.scancode_from_key(EnumName.of(key)).to_sym
    end

    # The key that the physical key +scancode+ types on the player's
    # layout, matching love.keyboard.getKeyFromScancode
    # (src/modules/keyboard/wrap_Keyboard.cpp, w_getKeyFromScancode), as a
    # Symbol.
    #
    # [scancode] Symbol (or String) naming the physical key by LÖVE's
    #   scancode constants.
    #
    # Raises ArgumentError ("Invalid scancode: ...") for a name that is no
    # scancode, RuntimeError ("Unknown key constant") for a scancode that
    # types no key, and RuntimeError when the keyboard module is not open.
    #
    # === Example
    #
    #   Lota::Keyboard.key_from_scancode(:y) # => :z on a German layout
    def self.key_from_scancode(scancode)
      Native::Keyboard.key_from_scancode(EnumName.of(scancode)).to_sym
    end

    # Whether the modifier +key+ is active, matching
    # love.keyboard.isModifierActive (src/modules/keyboard/
    # wrap_Keyboard.cpp, w_isModifierActive): a lock that is switched on,
    # not a key that is held.
    #
    # [key] +:numlock+, +:capslock+, +:scrolllock+, or +:mode+.
    #
    # Raises ArgumentError ("Invalid modifier keys: ...") for any other
    # name, and RuntimeError when the keyboard module is not open.
    #
    # === Example
    #
    #   Lota::Keyboard.modifier_active?(:capslock) # => false
    def self.modifier_active?(key)
      Native::Keyboard.modifier_active?(EnumName.of(key))
    end

    # The names of +keys+, which are LÖVE's list of arguments, or its one
    # table of them as an Array. :nodoc:
    private_class_method def self.names(keys)
      first = keys.first
      (first.is_a?(Array) ? first : keys).map { |key| EnumName.of(key) }
    end
  end
end
