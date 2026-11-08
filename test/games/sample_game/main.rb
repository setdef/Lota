# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A ball bounces between two paddles that follow it, under a pale moon.
# A touch or a click moves the bottom paddle to it, and the top one goes
# on by itself. Every five seconds it prints how many frames it drew, and
# with SAMPLE_GAME_QUIT_AFTER=SECONDS it quits with 0 after that long.
class SampleGame
  SKY = [0.05, 0.05, 0.15, 1.0].freeze
  MOON = [0.95, 0.93, 0.8, 1.0].freeze
  PADDLE = [0.6, 0.8, 1.0, 1.0].freeze

  def load
    @quit_after = ENV.fetch("SAMPLE_GAME_QUIT_AFTER", nil)&.then { |value| Float(value) }
    @frames = 0
    @reported = 0
    @touch_x = nil
    @started = Lota::Timer.time
    Lota::Graphics.background_color = SKY
    width, height = Lota::Graphics.dimensions
    @ball = [width / 2.0, height / 2.0]
    @speed = [width * 0.4, height * 0.5]
    @top = @bottom = width / 2.0
    puts "sample game: Lota #{Lota::VERSION}, #{Lota::Graphics.renderer_info.join(' / ')}"
    puts "sample game: #{width}x#{height}, pixels #{Lota::Graphics.pixel_dimensions.join('x')}"
  end

  def update(delta)
    width, height = Lota::Graphics.dimensions
    move_ball(delta, width, height)
    @top += (@ball[0] - @top) * [delta * 6, 1].min
    @bottom = @touch_x || (@bottom + ((@ball[0] - @bottom) * [delta * 6, 1].min))
    elapsed = Lota::Timer.time - @started
    if elapsed - @reported >= 5
      @reported = elapsed
      puts "sample game: #{@frames} frames by #{elapsed.round} s, #{Lota::Timer.fps} fps"
    end
    return unless @quit_after && elapsed >= @quit_after && !@quitting

    @quitting = true
    puts "sample game: quitting after #{@quit_after} s, #{@frames} frames"
    Lota::Event.quit(0)
  end

  def draw
    @frames += 1
    width, height = Lota::Graphics.dimensions
    side = [width, height].min
    Lota::Graphics.color = MOON
    Lota::Graphics.circle(:fill, width * 0.75, height * 0.2, side * 0.12)
    Lota::Graphics.color = PADDLE
    paddle = side * 0.25
    Lota::Graphics.rectangle(:fill, @top - (paddle / 2), side * 0.05, paddle, side * 0.03)
    Lota::Graphics.rectangle(:fill, @bottom - (paddle / 2), height - (side * 0.08), paddle, side * 0.03)
    Lota::Graphics.color = [1, 1, 1, 1]
    Lota::Graphics.circle(:fill, @ball[0], @ball[1], side * 0.025)
    Lota::Graphics.print("Sample Game  #{Lota::Timer.fps} fps", side * 0.05, height / 2.0)
  end

  def point(x, label)
    @touch_x = x
    puts "sample game: #{label} at #{x.round(1)}"
  end

  def resize(width, height)
    puts "sample game: resized to #{width}x#{height}"
    @ball = [[@ball[0], width].min, [@ball[1], height].min]
  end

  private def move_ball(delta, width, height)
    2.times do |axis|
      @ball[axis] += @speed[axis] * delta
      limit = axis.zero? ? width : height
      @speed[axis] = -@speed[axis].abs if @ball[axis] > limit
      @speed[axis] = @speed[axis].abs if @ball[axis].negative?
    end
  end
end

def Lota.load(_arguments)
  @game = SampleGame.new
  @game.load
end

def Lota.update(delta)
  @game.update(delta)
end

def Lota.draw
  @game.draw
end

def Lota.resize(width, height)
  @game.resize(width, height)
end

def Lota.touchpressed(_id, x, _y, *)
  @game.point(x, "touch")
end

def Lota.mousepressed(x, _y, *)
  @game.point(x, "click")
end
