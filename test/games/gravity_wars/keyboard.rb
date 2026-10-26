# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2020 Boris
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from Gravity Wars' keyboard.lua
# (test/fixtures/gravity_wars/keyboard.lua, lines 1-52), as globals.rb
# describes: love.keypressed and keyreleased become Lota.keypressed and
# keyreleased (ADR 003), whose key is a symbol (ADR 001, rule 9), which
# Ruby's puts prints as Lua's print prints the name. Lua's os.exit ends
# the program at once, with status 0, as Ruby's exit does.

#--------------------------------------------------------------------------------------------------
# Code related to keyboard interactions
#--------------------------------------------------------------------------------------------------
def Lota.keypressed(key)
  puts(key)

  if key == :right
    GLOBALS.key_right = true
  end

  if key == :left
    GLOBALS.key_left = true
  end

  if key == :up
    GLOBALS.key_up = true

    GLOBALS.player1.force = GLOBALS.player1.force * 1.01
  end

  if key == :down
    GLOBALS.key_down = true
  end

  if key == :x
    explode(400, 300)
  end

  if key == :n
    new_game
  end

  if key == :space
    player_pressed_shoot_button
  end

  if key == :escape
    exit
  end
end

def Lota.keyreleased(_key)
  GLOBALS.key_right = false
  GLOBALS.key_left = false
  GLOBALS.key_up = false
  GLOBALS.key_down = false
end
# SPDX-SnippetEnd
