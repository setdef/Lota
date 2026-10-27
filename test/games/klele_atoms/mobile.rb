# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' mobile.lua
# (test/fixtures/klele_atoms/mobile.lua, lines 1-137), as main.rb and
# state.rb describe: updateMode becomes update_mode (rule 13), with its
# table's settings as keywords (rule 10), getSafeArea safe_area and
# getDesktopDimensions desktop_dimensions (rule 3), each returning an
# Array (rule 4), of which Lua's single assignment keeps the first value,
# and push, pop, translate, and scale keep their names (rules 11 and 13).
# string.format is Ruby's format.

module Mobile
  @scale = 1 # Mobile scale

  @res = [640, 480] # Ingame resolution (units)

  @sxo = 0 # Safe area X offset (avoids drawing on the notch)

  @realx = 0 # Real screen width (in pixels)

  @realy = 0 # Real screen height (in pixels)

  @movex = 0 # move screen X pixels to the right

  @movey = 0 # move screen Y pixels down

  @is_gfx_pushed = false # Is scaling active or not

  @is_init = false # Is mobile mode initialized or not

  def self.init # Initialize window scaling
    return if @is_init

    if CA.os_type == "Web"
      @realx = 800
      @realy = 600
      Lota::Window.update_mode(@realx, @realy)
    elsif CA.full_screen
      @res[0], @res[1] = Lota::Graphics.dimensions
      @sxo = Lota::Window.safe_area.first
      @realx, @realy = Lota::Window.desktop_dimensions
      @realx -= @sxo * 2
      Lota::Window.update_mode(@realx, @realy, fullscreen: true, resizable: false)
    else # _CAWinResizing
      @res[0], @res[1] = Lota::Graphics.dimensions
      @realx, @realy = @res[0], @res[1]
      Lota::Window.update_mode(@realx, @realy, resizable: true)
    end
    @is_init = true
  end

  def self.toggle_fullscreen
    CA.full_screen = !CA.full_screen
    @is_init = false
    if CA.full_screen
      if CA.win_resizing # Prevent scaling issues caused by resizable windows
        @realx = @res[0]
        @realy = @res[1]
        Lota::Window.update_mode(@res[0], @res[1], resizable: false)
      end
      init
    else
      if !CA.win_resizing && @is_gfx_pushed
        Lota::Graphics.pop
        @is_gfx_pushed = false
        @scale = 1
      end
      @realx = @res[0]
      @realy = @res[1]
      Lota::Window.update_mode(@res[0], @res[1], fullscreen: false, resizable: CA.win_resizing)
    end
    CA.use_scaling = (CA.full_screen || CA.win_resizing)
    State.printmsg(format("Fullscreen mode %s.", CA.full_screen ? "enabled" : "disabled"), 3)
  end

  def self.toggle_win_resizing
    CA.win_resizing = !CA.win_resizing
    State.printmsg(format("Window resizing %s.", CA.win_resizing ? "enabled" : "disabled"), 3)
    return if CA.full_screen

    @is_init = false
    if CA.win_resizing
      init
    else
      if @is_gfx_pushed
        Lota::Graphics.pop
        @is_gfx_pushed = false
        @scale = 1
      end
      @realx = @res[0]
      @realy = @res[1]
      Lota::Window.update_mode(@res[0], @res[1], resizable: false)
    end
    CA.use_scaling = (CA.full_screen || CA.win_resizing)
  end

  def self.resize(x, y)
    @realx = x - (@sxo * 2)
    @realy = y
  end

  def self.predraw # Setup graphics scaling
    @scale = [@realx / @res[0].to_f, @realy / @res[1].to_f].min
    @movex = ((@realx / 2.0) - ((@res[0] / 2.0) * @scale)).floor + @sxo
    @movey = ((@realy / 2.0) - ((@res[1] / 2.0) * @scale)).floor
    Lota::Graphics.push
    Lota::Graphics.translate(@movex, @movey)
    Lota::Graphics.scale(@scale, @scale)
    @is_gfx_pushed = true
  end

  def self.postdraw # Stop graphics scaling
    return unless @is_gfx_pushed

    Lota::Graphics.pop
    @is_gfx_pushed = false
  end

  def self.setresolution(winx, winy) # Set ingame resolution
    @res = [winx, winy]
  end

  def self.getresolution # Get ingame resolution
    [@res[0], @res[1]]
  end

  def self.convertcoords(x, y) # Convert screen coordinates to ingame coordinates
    x = (x - @movex) / @scale.to_f
    y = (y - @movey) / @scale.to_f
    [x, y]
  end

  def self.absolutedrawmode(enable) # Draw without scaling and x,y coordinate offsets
    if enable && @is_gfx_pushed
      Lota::Graphics.pop
      @is_gfx_pushed = false
    end
    return unless !enable && !@is_gfx_pushed

    Lota::Graphics.push
    Lota::Graphics.translate(@movex, @movey)
    Lota::Graphics.scale(@scale, @scale)
    @is_gfx_pushed = true
  end

  def self.getscale
    @scale
  end
end
# SPDX-SnippetEnd
