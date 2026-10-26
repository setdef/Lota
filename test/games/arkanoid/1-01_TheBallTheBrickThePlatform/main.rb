# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2016 noooway
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from the arkanoid tutorial's first snapshot,
# test/fixtures/love2d_arkanoid_tutorial/1-01_TheBallTheBrickThePlatform/
# main.lua (lines 1-57), by ADR 001's rules: love.keyboard.isDown becomes
# Lota::Keyboard.down? (rule 8), the draw modes and key names symbols (rule
# 9), and each function love.x a method Lota.x (ADR 003). Lua's local
# tables become Structs, held in constants so the callbacks can reach
# them, as Lua's callbacks reach the file's locals. The snapshot has no
# conf.lua, so this game has no conf.rb.

Ball = Struct.new(:position_x, :position_y, :speed_x, :speed_y, :radius)
Platform = Struct.new(:position_x, :position_y, :speed_x, :width, :height)
Brick = Struct.new(:position_x, :position_y, :width, :height)

BALL = Ball.new(
  position_x: 300,
  position_y: 300,
  speed_x: 300,
  speed_y: 300,
  radius: 10,
)

PLATFORM = Platform.new(
  position_x: 500,
  position_y: 500,
  speed_x: 300,
  width: 70,
  height: 20,
)

BRICK = Brick.new(
  position_x: 100,
  position_y: 100,
  width: 50,
  height: 30,
)

def Lota.load
end

def Lota.update(dt)
  BALL.position_x = BALL.position_x + (BALL.speed_x * dt)
  BALL.position_y = BALL.position_y + (BALL.speed_y * dt)

  if Lota::Keyboard.down?(:right)
    PLATFORM.position_x = PLATFORM.position_x + (PLATFORM.speed_x * dt)
  end
  if Lota::Keyboard.down?(:left)
    PLATFORM.position_x = PLATFORM.position_x - (PLATFORM.speed_x * dt)
  end
end

def Lota.draw
  segments_in_circle = 16
  Lota::Graphics.circle(:line,
    BALL.position_x,
    BALL.position_y,
    BALL.radius,
    segments_in_circle)
  Lota::Graphics.rectangle(:line,
    PLATFORM.position_x,
    PLATFORM.position_y,
    PLATFORM.width,
    PLATFORM.height)
  Lota::Graphics.rectangle(:line,
    BRICK.position_x,
    BRICK.position_y,
    BRICK.width,
    BRICK.height)
end

def Lota.quit
  puts("Thanks for playing! Come back soon!")
end
# SPDX-SnippetEnd
