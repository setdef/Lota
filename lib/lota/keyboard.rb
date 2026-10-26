# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
  # quitting.
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
    #   +:space+, +:right+, or +:lshift+; Strings work too.
    #
    # A key constant names the character a key types on the player's
    # keyboard layout, so +:a+ follows the key labeled A wherever it is.
    # A name that is not one of LÖVE's key constants counts as the key of
    # its first character, as in LÖVE 12, so +:apple+ is +:a+. With no keys
    # it returns +false+. LÖVE also takes its keys in one table, which Lota
    # binds later.
    #
    # Raises ArgumentError ("Invalid key constant: ...") for an empty name
    # or one that is not UTF-8, and RuntimeError when the keyboard module is
    # not open, as when <tt>t.modules.keyboard = false</tt>.
    #
    # === Examples
    #
    #   Lota::Keyboard.down?(:space)          # => false
    #   Lota::Keyboard.down?(:lshift, :rshift) # either shift key
    def self.down?(*keys)
      Native::Keyboard.down?(keys.map { |key| EnumName.of(key) })
    end
  end
end
