# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2016 noooway
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from the arkanoid tutorial's sixth snapshot,
# test/fixtures/love2d_arkanoid_tutorial/1-06_Levels/main.lua (lines
# 1-399), by ADR 001's rules and as the fifth snapshot is
# (test/games/arkanoid/1-05_ResolvingCollisions/main.rb), whose notes on
# dividing, on removing bricks while walking them, and on the order of
# the walls hold here too. love.graphics.printf keeps its name (rule 13),
# with its alignment a symbol (rule 9), and Lua's .. joins strings as
# Ruby's + does. Lua's ipairs counts from 1, and so do the rows and
# columns here, through each.with_index(1). The levels are numbered from
# 1, as in Lua, so level n is sequence[n - 1] of a Ruby Array, and Lua's
# # operator, a table's length, is Ruby's length. The snapshot has no
# conf.lua, so this game has no conf.rb.

# Ball (lines 1-45)
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

  def rebound(shift_ball_x, shift_ball_y)
    min_shift = [shift_ball_x.abs, shift_ball_y.abs].min
    if shift_ball_x.abs == min_shift
      shift_ball_y = 0
    else
      shift_ball_x = 0
    end
    self.position_x = position_x + shift_ball_x
    self.position_y = position_y + shift_ball_y
    if shift_ball_x != 0
      self.speed_x = -speed_x
    end
    if shift_ball_y != 0
      self.speed_y = -speed_y
    end
  end

  def reposition
    self.position_x = 200
    self.position_y = 500
  end
end

BALL = Ball.new(
  position_x: 200,
  position_y: 500,
  speed_x: 700,
  speed_y: 700,
  radius: 10,
)

# Platform (lines 47-74)
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

  def bounce_from_wall(shift_platform_x, shift_platform_y)
    self.position_x = position_x + shift_platform_x
  end
end

PLATFORM = Platform.new(
  position_x: 500,
  position_y: 500,
  speed_x: 500,
  width: 70,
  height: 20,
)

# Bricks (lines 76-148)
Brick = Struct.new(:position_x, :position_y, :width, :height)

Bricks = Struct.new(:rows, :columns, :top_left_position_x, :top_left_position_y, :brick_width, :brick_height,
  :horizontal_distance, :vertical_distance, :current_level_bricks, :no_more_bricks) do
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

  def construct_level(level_bricks_arrangement)
    self.no_more_bricks = false
    level_bricks_arrangement.each.with_index(1) do |row, row_index|
      row.each.with_index(1) do |bricktype, col_index|
        if bricktype != 0
          new_brick_position_x = top_left_position_x +
            ((col_index - 1) *
            (brick_width + horizontal_distance))
          new_brick_position_y = top_left_position_y +
            ((row_index - 1) *
            (brick_height + vertical_distance))
          new_brick = new_brick(new_brick_position_x,
            new_brick_position_y)
          add_to_current_level_bricks(new_brick)
        end
      end
    end
  end

  def update(dt)
    if current_level_bricks.length == 0
      self.no_more_bricks = true
    else
      current_level_bricks.each do |brick|
        update_brick(brick)
      end
    end
  end

  def draw
    current_level_bricks.each do |brick|
      draw_brick(brick)
    end
  end

  def brick_hit_by_ball(i, brick, shift_ball_x, shift_ball_y)
    current_level_bricks.delete_at(i)
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
  no_more_bricks: false,
)

# Walls (lines 150-214)
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

# Collisions (lines 217-322)
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
    shift_b_x, shift_b_y = 0, 0
    if !((a.x + a.width < b.x) || (b.x + b.width < a.x) ||
        (a.y + a.height < b.y) || (b.y + b.height < a.y))

      overlap = true
      if (a.x + (a.width / 2.0)) < (b.x + (b.width / 2.0))
        shift_b_x = (a.x + a.width) - b.x
      else
        shift_b_x = a.x - (b.x + b.width)
      end
      if (a.y + (a.height / 2.0)) < (b.y + (b.height / 2.0))
        shift_b_y = (a.y + a.height) - b.y
      else
        shift_b_y = a.y - (b.y + b.height)
      end
    end
    [overlap, shift_b_x, shift_b_y]
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
    overlap, shift_ball_x, shift_ball_y =
      check_rectangles_overlap(a, b)
    if overlap
      ball.rebound(shift_ball_x, shift_ball_y)
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
      overlap, shift_ball_x, shift_ball_y =
        check_rectangles_overlap(a, b)
      if overlap
        ball.rebound(shift_ball_x, shift_ball_y)
      end
    end
  end

  def self.ball_bricks_collision(ball, bricks)
    b = Rectangle.new(x: ball.position_x - ball.radius,
      y: ball.position_y - ball.radius,
      width: 2 * ball.radius,
      height: 2 * ball.radius)
    bricks.current_level_bricks.each_with_index do |brick, i|
      a = Rectangle.new(x: brick.position_x,
        y: brick.position_y,
        width: brick.width,
        height: brick.height)
      overlap, shift_ball_x, shift_ball_y =
        check_rectangles_overlap(a, b)
      if overlap
        ball.rebound(shift_ball_x, shift_ball_y)
        bricks.brick_hit_by_ball(i, brick,
          shift_ball_x, shift_ball_y)
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
      overlap, shift_platform_x, shift_platform_y =
        check_rectangles_overlap(a, b)
      if overlap
        PLATFORM.bounce_from_wall(shift_platform_x,
          shift_platform_y)
      end
    end
  end
end

# Levels (lines 324-362)
Levels = Struct.new(:current_level, :gamefinished, :sequence) do
  def switch_to_next_level(bricks)
    if bricks.no_more_bricks
      if current_level < sequence.length
        self.current_level = current_level + 1
        bricks.construct_level(sequence[current_level - 1])
        BALL.reposition
      else
        self.gamefinished = true
      end
    end
  end
end

LEVELS = Levels.new(
  current_level: 1,
  gamefinished: false,
  sequence: [],
)
LEVELS.sequence[0] = [
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1],
  [1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1],
  [1, 1, 1, 0, 1, 1, 0, 0, 0, 1, 0],
  [1, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0],
  [1, 0, 1, 0, 1, 1, 1, 0, 0, 1, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]

LEVELS.sequence[1] = [
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  [1, 1, 0, 0, 1, 0, 1, 0, 1, 1, 1],
  [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0],
  [1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 0],
  [1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0],
  [1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 1],
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]

# Lines 365-399.
def Lota.load
  BRICKS.construct_level(LEVELS.sequence[LEVELS.current_level - 1])
  WALLS.construct_walls
end

def Lota.update(dt)
  BALL.update(dt)
  PLATFORM.update(dt)
  BRICKS.update(dt)
  WALLS.update(dt)
  Collisions.resolve_collisions
  LEVELS.switch_to_next_level(BRICKS)
end

def Lota.draw
  BALL.draw
  PLATFORM.draw
  BRICKS.draw
  WALLS.draw
  if LEVELS.gamefinished
    Lota::Graphics.printf("Congratulations!\n" +
      "You have finished the game!",
      300, 250, 200, :center)
  end
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
