# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2016 noooway
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from the arkanoid tutorial's second snapshot,
# test/fixtures/love2d_arkanoid_tutorial/1-02_GameObjectsAsLuaTables/
# main.lua (lines 1-117), by ADR 001's rules, as the first snapshot is
# (test/games/arkanoid/1-01_TheBallTheBrickThePlatform/main.rb). Each Lua
# table that holds an object's fields and the functions that act on them
# becomes a Struct with those fields and methods, and the local that held
# the table a constant that holds the one Struct, so that function
# ball.update becomes Ball#update, called as BALL.update. A brick, which
# bricks.new_brick returns as a table of fields alone, is a Struct with no
# methods. The snapshot has no conf.lua, so this game has no conf.rb.

# Ball (lines 1-21)
Ball = Struct.new(:position_x, :position_y, :speed_x, :speed_y, :radius) do
  def update(dt)
    self.position_x = position_x + (speed_x * dt)
    self.position_y = position_y + (speed_y * dt)
  end

  def draw
    segments_in_circle = 16
    Lota::Graphics.circle(:line,
      position_x,
      position_y,
      radius,
      segments_in_circle)
  end
end

BALL = Ball.new(
  position_x: 300,
  position_y: 300,
  speed_x: 300,
  speed_y: 300,
  radius: 10,
)

# Platform (lines 24-47)
Platform = Struct.new(:position_x, :position_y, :speed_x, :width, :height) do
  def update(dt)
    if Lota::Keyboard.down?(:right)
      self.position_x = position_x + (speed_x * dt)
    end
    if Lota::Keyboard.down?(:left)
      self.position_x = position_x - (speed_x * dt)
    end
  end

  def draw
    Lota::Graphics.rectangle(:line,
      position_x,
      position_y,
      width,
      height)
  end
end

PLATFORM = Platform.new(
  position_x: 500,
  position_y: 500,
  speed_x: 300,
  width: 70,
  height: 20,
)

# Bricks (lines 49-87)
Brick = Struct.new(:position_x, :position_y, :width, :height)

Bricks = Struct.new(:brick_width, :brick_height, :current_level_bricks) do
  def new_brick(position_x, position_y, width = nil, height = nil)
    Brick.new(position_x:,
      position_y:,
      width: width || brick_width,
      height: height || brick_height)
  end

  def add_to_current_level_bricks(brick)
    current_level_bricks.push(brick)
  end

  def update_brick(single_brick)
  end

  def draw_brick(single_brick)
    Lota::Graphics.rectangle(:line,
      single_brick.position_x,
      single_brick.position_y,
      single_brick.width,
      single_brick.height)
  end

  def update(dt)
    current_level_bricks.each do |brick|
      update_brick(brick)
    end
  end

  def draw
    current_level_bricks.each do |brick|
      draw_brick(brick)
    end
  end
end

BRICKS = Bricks.new(
  brick_width: 50,
  brick_height: 30,
  current_level_bricks: [],
)

# Lines 90-117.
def Lota.load
  BRICKS.add_to_current_level_bricks(
    BRICKS.new_brick(100, 100))
  BRICKS.add_to_current_level_bricks(
    BRICKS.new_brick(160, 100))
  BRICKS.add_to_current_level_bricks(
    BRICKS.new_brick(220, 100))
  BRICKS.add_to_current_level_bricks(
    BRICKS.new_brick(280, 145))
  BRICKS.add_to_current_level_bricks(
    BRICKS.new_brick(340, 145))
end

def Lota.update(dt)
  BALL.update(dt)
  PLATFORM.update(dt)
  BRICKS.update(dt)
end

def Lota.draw
  BALL.draw
  PLATFORM.draw
  BRICKS.draw
end

def Lota.quit
  puts("Thanks for playing! Come back soon!")
end
# SPDX-SnippetEnd
