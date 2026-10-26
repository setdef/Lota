# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2016 noooway
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from the arkanoid tutorial's fourth snapshot,
# test/fixtures/love2d_arkanoid_tutorial/1-04_DetectingCollisions/main.lua
# (lines 1-290), by ADR 001's rules and as the third snapshot is
# (test/games/arkanoid/1-03_BricksAndWalls/main.rb). The collisions table
# holds functions alone, so it becomes a module of them, and the
# rectangles it builds as tables of fields a Struct. Its
# platform_walls_collision declares no parameters, though it is called
# with two, which Lua drops; Ruby would raise, so it takes and ignores any.
# love.keyreleased becomes Lota.keyreleased, whose key arrives as a
# symbol, and love.event.quit Lota::Event.quit (rule 9; ADR 003). Lua's
# pairs visits the walls in an order Lua leaves unspecified, and a Ruby
# Hash in the order they were added; each wall's collision only prints the
# same line, so no frame or line depends on the order. The snapshot has no
# conf.lua, so this game has no conf.rb.

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

# Bricks (lines 50-110)
Brick = Struct.new(:position_x, :position_y, :width, :height)

Bricks = Struct.new(:rows, :columns, :top_left_position_x, :top_left_position_y, :brick_width, :brick_height,
  :horizontal_distance, :vertical_distance, :current_level_bricks) do
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

  def construct_level
    (1..rows).each do |row|
      (1..columns).each do |col|
        new_brick_position_x = top_left_position_x +
          ((col - 1) *
          (brick_width + horizontal_distance))
        new_brick_position_y = top_left_position_y +
          ((row - 1) *
          (brick_height + vertical_distance))
        new_brick = new_brick(new_brick_position_x,
          new_brick_position_y)
        add_to_current_level_bricks(new_brick)
      end
    end
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
  rows: 8,
  columns: 11,
  top_left_position_x: 70,
  top_left_position_y: 50,
  brick_width: 50,
  brick_height: 30,
  horizontal_distance: 10,
  vertical_distance: 15,
  current_level_bricks: [],
)

# Walls (lines 113-177)
Wall = Struct.new(:position_x, :position_y, :width, :height)

Walls = Struct.new(:wall_thickness, :current_level_walls) do
  def new_wall(position_x, position_y, width, height)
    Wall.new(position_x:,
      position_y:,
      width:,
      height:)
  end

  def update_wall(single_wall)
  end

  def draw_wall(single_wall)
    Lota::Graphics.rectangle(:line,
      single_wall.position_x,
      single_wall.position_y,
      single_wall.width,
      single_wall.height)
  end

  def construct_walls
    left_wall = new_wall(
      0,
      0,
      wall_thickness,
      Lota::Graphics.height,
    )
    right_wall = new_wall(
      Lota::Graphics.width - wall_thickness,
      0,
      wall_thickness,
      Lota::Graphics.height,
    )
    top_wall = new_wall(
      0,
      0,
      Lota::Graphics.width,
      wall_thickness,
    )
    bottom_wall = new_wall(
      0,
      Lota::Graphics.height - wall_thickness,
      Lota::Graphics.width,
      wall_thickness,
    )
    current_level_walls["left"] = left_wall
    current_level_walls["right"] = right_wall
    current_level_walls["top"] = top_wall
    current_level_walls["bottom"] = bottom_wall
  end

  def update(dt)
    current_level_walls.each_value do |wall|
      update_wall(wall)
    end
  end

  def draw
    current_level_walls.each_value do |wall|
      draw_wall(wall)
    end
  end
end

WALLS = Walls.new(
  wall_thickness: 20,
  current_level_walls: {},
)

# Collisions (lines 180-259)
Rectangle = Struct.new(:x, :y, :width, :height)

module Collisions
  def self.resolve_collisions
    ball_platform_collision(BALL, PLATFORM)
    ball_walls_collision(BALL, WALLS)
    ball_bricks_collision(BALL, BRICKS)
    platform_walls_collision(PLATFORM, WALLS)
  end

  def self.check_rectangles_overlap(a, b)
    overlap = false
    if !((a.x + a.width < b.x) || (b.x + b.width < a.x) ||
        (a.y + a.height < b.y) || (b.y + b.height < a.y))

      overlap = true
    end
    overlap
  end

  def self.ball_platform_collision(ball, platform)
    a = Rectangle.new(x: platform.position_x,
      y: platform.position_y,
      width: platform.width,
      height: platform.height)
    b = Rectangle.new(x: ball.position_x - ball.radius,
      y: ball.position_y - ball.radius,
      width: 2 * ball.radius,
      height: 2 * ball.radius)
    if check_rectangles_overlap(a, b)
      puts("ball-platform collision")
    end
  end

  def self.ball_walls_collision(ball, walls)
    b = Rectangle.new(x: ball.position_x - ball.radius,
      y: ball.position_y - ball.radius,
      width: 2 * ball.radius,
      height: 2 * ball.radius)
    walls.current_level_walls.each_value do |wall|
      a = Rectangle.new(x: wall.position_x,
        y: wall.position_y,
        width: wall.width,
        height: wall.height)
      if check_rectangles_overlap(a, b)
        puts("ball-wall collision")
      end
    end
  end

  def self.ball_bricks_collision(ball, bricks)
    b = Rectangle.new(x: ball.position_x - ball.radius,
      y: ball.position_y - ball.radius,
      width: 2 * ball.radius,
      height: 2 * ball.radius)
    bricks.current_level_bricks.each do |brick|
      a = Rectangle.new(x: brick.position_x,
        y: brick.position_y,
        width: brick.width,
        height: brick.height)
      if check_rectangles_overlap(a, b)
        puts("ball-brick collision")
      end
    end
  end

  def self.platform_walls_collision(*)
    b = Rectangle.new(x: PLATFORM.position_x,
      y: PLATFORM.position_y,
      width: PLATFORM.width,
      height: PLATFORM.height)
    WALLS.current_level_walls.each_value do |wall|
      a = Rectangle.new(x: wall.position_x,
        y: wall.position_y,
        width: wall.width,
        height: wall.height)
      if check_rectangles_overlap(a, b)
        puts("platform-wall collision")
      end
    end
  end
end

# Lines 262-290.
def Lota.load
  BRICKS.construct_level
  WALLS.construct_walls
end

def Lota.update(dt)
  BALL.update(dt)
  PLATFORM.update(dt)
  BRICKS.update(dt)
  WALLS.update(dt)
  Collisions.resolve_collisions
end

def Lota.draw
  BALL.draw
  PLATFORM.draw
  BRICKS.draw
  WALLS.draw
end

def Lota.keyreleased(key, code)
  if key == :escape
    Lota::Event.quit
  end
end

def Lota.quit
  puts("Thanks for playing! Come back soon!")
end
# SPDX-SnippetEnd
