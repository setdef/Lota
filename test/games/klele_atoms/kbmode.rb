# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' kbmode.lua
# (test/fixtures/klele_atoms/kbmode.lua, lines 1-73), as main.rb and
# state.rb describe: newImage becomes Image.new (rule 2), setColor a
# writer (rules 5 and 6), the keys and the event names symbols (rule 9),
# and love.event.push Lota::Event.push.

module KbMode
  @xpos = 320 # Mouse X position

  @ypos = 240 # Mouse Y position

  @kpressed = false # Key is pressed

  @movement = [0, 0, 0, 0] # Movement up,down,left,right

  F_CURSPEED = -> { # Get mouse speed
    200 * [@xpos * 2 / 640.0, @ypos * 2 / 480.0].max
  }

  @curspeed = F_CURSPEED.call

  CACURSOR = Lota::Graphics::Image.new("graphics/cacursor.png")

  def self.draw
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.draw(CACURSOR, @xpos, @ypos)
  end

  def self.update(dt)
    @ypos += (@movement[1] - @movement[0]) * @curspeed * dt
    @xpos += (@movement[3] - @movement[2]) * @curspeed * dt
  end

  def self.keypressed(key)
    if !@kpressed && (key == :return || key == :space)
      Lota::Event.push(:mousepressed, @xpos, @ypos, 1, false)
      @kpressed = true
      return true
    elsif key == :w || key == :up
      @movement[0] = 1
    elsif key == :s || key == :down
      @movement[1] = 1
    elsif key == :a || key == :left
      @movement[2] = 1
    elsif key == :d || key == :right
      @movement[3] = 1
    end
    false
  end

  def self.keyreleased(key)
    if @kpressed && (key == :return || key == :space)
      Lota::Event.push(:mousereleased, @xpos, @ypos, 1, false)
      @kpressed = false
      return true
    elsif key == :w || key == :up
      @movement[0] = 0
    elsif key == :s || key == :down
      @movement[1] = 0
    elsif key == :a || key == :left
      @movement[2] = 0
    elsif key == :d || key == :right
      @movement[3] = 0
    end
    false
  end

  def self.get_pos # Get current position
    [@xpos, @ypos]
  end

  def self.set_pos(x, y) # Set position (screen size is double x and y)
    @xpos = x
    @ypos = y
    @curspeed = F_CURSPEED.call
  end
end
# SPDX-SnippetEnd
