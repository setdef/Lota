# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' states/game/gamepause.lua
# (test/fixtures/klele_atoms/states/game/gamepause.lua, lines 1-260), as
# main.rb and gamelogic.rb describe: love.filesystem.write becomes
# Lota::Filesystem.write, whose result is an Array, of which Lua's if
# reads the first (rule 4), newCanvas Canvas.new and newFont Font.new
# (rule 2), renderTo render_to with a block (rule 12), getDimensions and
# love.mouse.getPosition dimensions and position (rules 3 and 4), and the
# keys symbols (rule 9). The window and the buttons' corners, Lua tables
# indexed from 1, are Arrays, so Lua's winpos[1] is winpos[0] and
# butpos[1][1] is butpos[0][0]. string.char of a number Lua truncates is
# the truncated number's chr.

module GamePause
  @gamelogic = nil # Gamelogic table reference

  @winx = -1 # Current window width (on desktop limited to 480)

  @winy = -1 # Current window height (on desktop limited to 360)

  @pfont = CA.font24 # Pause text font

  @bfont = CA.font16 # Button text font

  @bfontsize = 16 # Button text font size

  # 1-4th numbers - positions of top-left and bottom-right corners, 5-6th are pause text width and y position
  @winpos = [0, 0, 0, 0, 0, 0]

  @butpos = []

  @butpos[0] = [0, 0, 0, 0] # 1-4th numbers - the same as above

  @butpos[1] = [0, 0, 0, 0]

  @butpos[2] = [0, 0, 0, 0]

  @butpos[3] = [0, 0, 0, 0]

  @cbut = nil # Button texture (rendered once)

  @cbutpress = nil # Pressed button texture (rendered once)

  @pausetime = 0.0 # Time spent in pause menu

  @buttonclicked = nil # The pause menu button that is being clicked or nil if none

  @gametime = 0.0 # A copy of in-game time (for game saving)

  @drawcooldown = 0.0 # A cooldown for pause menu drawing (to prevent resize issues)

  SNDCLICK = Lota::Audio::Source.new("sounds/click.wav", :static)

  def self.pst(num) # Convert player status from 2 variables to a number 0-2 (or 255 if player does not exist)
    if @gamelogic.playertab[num] == true
      @gamelogic.playermoved[num] ? 2 : 1
    elsif @gamelogic.playertab[num] == false
      0
    else
      255
    end
  end

  def self.pai(num) # Convert AI player boolean to a 0 or AI Difficulty + 1
    if @gamelogic.ai.playertab[num]
      @gamelogic.ai.difficulty[num] + 1
    else
      0
    end
  end

  # string.char of +number+, which LuaJIT truncates to an integer.
  def self.char(number)
    number.to_i.chr
  end

  def self.save_game # Save the game to savegame.ksf file
    gw = @gamelogic.grid.size
    gh = @gamelogic.grid[1].size
    str = "KSF".b + char(gw % 256) + char(gh % 256) + char([@gamelogic.startplayers, 4].min) +
      char(@gamelogic.players % 256) + char(CA.play_exp % 256) + char(@gamelogic.curplayer % 256) + char(pst(1)) +
      char(pst(2)) + char(pst(3)) + char(pst(4)) + char(pai(1)) + char(pai(2)) + char(pai(3)) + char(pai(4)) +
      char(@gametime % 60) + char((@gametime / 60) % 60) + char((@gametime / 3600) % 256)
    1.upto(gw) do |x|
      1.upto(gh) do |y|
        str += char(@gamelogic.grid[x][y].player % 256) + char(@gamelogic.grid[x][y].atoms.size % 256)
      end
    end
    if Lota::Filesystem.write("savegame.ksf", str).first
      true
    else
      false
    end
  end

  # Calculate window, text and button positions, render buttons, calculate font sizes
  def self.setup_pause_menu
    yoffs = 0
    xoffs = 0
    unless CA.is_mobile
      if CA.full_screen
        xoffs = (@winx / 4.0).floor
        yoffs = (@winy / 4.0).floor
        @winx = (@winx / 2.0).floor
        @winy = (@winy / 2.0).floor
      elsif !CA.win_resizing
        if @winx > 480
          xoffs = ((@winx - 480) / 2.0).floor
          @winx = 480
        end
        if @winy > 360
          yoffs = ((@winy - 360) / 2.0).floor
          @winy = 360
        end
      end
    end
    maxwinx = (4 * @winy / 3.0).floor
    if @winx > maxwinx # Pause menu can't be wider than 4:3
      xoffs += ((@winx - maxwinx) / 2.0).floor
      @winx = maxwinx
    elsif @winy > @winx
      yoffs = yoffs + xoffs + ((@winy - @winx) / 2.0).floor
      @winy = @winx
    end
    @winpos = [
      ((@winx / 16.0) + xoffs).floor,
      ((@winy / 8.0) + yoffs).floor,
      ((15 * @winx / 16.0) + xoffs).floor,
      ((7 * @winy / 8.0) + yoffs).floor,
      (28 * @winx / 32.0).floor,
      ((3 * @winy / 20.0) + yoffs).floor,
    ]
    width = @winpos[2] - @winpos[0]
    height = @winpos[3] - @winpos[1]
    @butpos[0] = [
      ((1 * width / 25.0) + @winpos[0]).floor,
      ((8 * height / 12.0) + @winpos[1]).floor,
      ((12 * width / 25.0) + @winpos[0]).floor,
      ((11 * height / 12.0) + @winpos[1]).floor,
    ]
    @butpos[1] = [
      ((13 * width / 25.0) + @winpos[0]).floor,
      @butpos[0][1],
      ((24 * width / 25.0) + @winpos[0]).floor,
      @butpos[0][3],
    ]
    @butpos[2] = [
      ((1 * width / 25.0) + @winpos[0]).floor,
      ((4 * height / 12.0) + @winpos[1]).floor,
      ((12 * width / 25.0) + @winpos[0]).floor,
      ((7 * height / 12.0) + @winpos[1]).floor,
    ]
    @butpos[3] = [
      ((13 * width / 25.0) + @winpos[0]).floor,
      @butpos[2][1],
      ((24 * width / 25.0) + @winpos[0]).floor,
      @butpos[2][3],
    ]
    minw = [width, height].min
    @pfont = Lota::Graphics::Font.new((minw / 4.0).floor)
    bx = (@butpos[0][2] - @butpos[0][0]).abs
    by = (@butpos[0][3] - @butpos[0][1]).abs
    minb = [bx, by].min
    @bfontsize = (6 * minb / 20.0).floor
    @bfont = Lota::Graphics::Font.new(@bfontsize)
    @cbut = Lota::Graphics::Canvas.new(bx, by)
    @cbutpress = Lota::Graphics::Canvas.new(bx, by)
    @cbut.render_to do
      Lota::Graphics.color = 0.5, 0.5, 0.5, 1
      Lota::Graphics.rectangle(:fill, 0, 0, bx - 1, by - 1)
      Lota::Graphics.color = 0, 0, 0, 1
      Lota::Graphics.rectangle(:line, 0, 0, bx - 1, by - 1)
      Lota::Graphics.color = 1, 1, 1, 1
    end
    @cbutpress.render_to do
      Lota::Graphics.color = 0.3, 0.3, 0.3, 1
      Lota::Graphics.rectangle(:fill, 0, 0, bx - 1, by - 1)
      Lota::Graphics.color = 0, 0, 0, 1
      Lota::Graphics.rectangle(:line, 0, 0, bx - 1, by - 1)
      Lota::Graphics.color = 1, 1, 1, 1
    end
  end

  def self.button_selected(x, y, bnum)
    pos = @butpos[bnum - 1]
    if (!@buttonclicked || @buttonclicked == bnum) && x >= pos[0] && x <= pos[2] && y >= pos[1] && y <= pos[3]
      return true
    end

    false
  end

  def self.init(logic, gtime)
    @gamelogic = logic
    @gametime = gtime
    @winx, @winy = Lota::Graphics.dimensions
    setup_pause_menu
    @gamelogic.paused = true
    @pausetime = 0.0
    @buttonclicked = nil
  end

  def self.update(dt)
    @pausetime += dt
    if @drawcooldown > 0
      @drawcooldown = [@drawcooldown - dt, 0].max
    elsif !@cbut
      setup_pause_menu
    end
  end

  # The y at which a button's label is drawn: its bottom edge, moved up by
  # its height and the font's size, halved.
  def self.label_y(pos)
    (pos[3] + ((pos[1] - pos[3] - @bfontsize) / 2.0)).floor
  end

  def self.draw
    State.absolute_draw_mode(true)
    Lota::Graphics.color = 0, 0, 0, 0.5
    Lota::Graphics.rectangle(:fill, 0, 0, *Lota::Graphics.dimensions)
    Lota::Graphics.color = 1, 1, 1, 1
    return unless @cbut # If pause menu is not setup, do not render it

    Lota::Graphics.rectangle(:line, @winpos[0], @winpos[1], @winpos[2] - @winpos[0], @winpos[3] - @winpos[1])
    Lota::Graphics.color = 0.2, 0.2, 0.2, 1
    Lota::Graphics.rectangle(:fill, @winpos[0], @winpos[1], @winpos[2] - @winpos[0], @winpos[3] - @winpos[1])
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.printf("PAUSE", @pfont, @winpos[0], @winpos[5], @winpos[4], :center)
    mx, my = Lota::Mouse.position
    1.upto(4) do |i|
      if button_selected(mx, my, i)
        Lota::Graphics.draw(@cbutpress, @butpos[i - 1][0], @butpos[i - 1][1])
      else
        Lota::Graphics.draw(@cbut, @butpos[i - 1][0], @butpos[i - 1][1])
      end
    end
    Lota::Graphics.printf("Menu", @bfont, @butpos[0][0], label_y(@butpos[0]), @butpos[0][2] - @butpos[0][0], :center)
    Lota::Graphics.printf("Reset", @bfont, @butpos[1][0], label_y(@butpos[1]), @butpos[1][2] - @butpos[1][0], :center)
    Lota::Graphics.printf("Play", @bfont, @butpos[2][0], label_y(@butpos[2]), @butpos[2][2] - @butpos[2][0], :center)
    Lota::Graphics.printf("Save & Quit", @bfont, @butpos[3][0], label_y(@butpos[3]), @butpos[3][2] - @butpos[3][0],
      :center)
  end

  def self.keyreleased(key)
    return unless @pausetime >= 0.3

    if key == :escape
      @gamelogic.paused = false
    elsif key == :m
      State.change("menu")
    end
  end

  def self.mousepressed(_x, _y, _button)
    x, y = Lota::Mouse.position
    1.upto(4) do |i|
      pos = @butpos[i - 1]
      next unless x >= pos[0] && x <= pos[2] && y >= pos[1] && y <= pos[3]

      Lota::Audio.play(SNDCLICK)
      @buttonclicked = i
      break
    end
  end

  def self.mousereleased(_x, _y, _button)
    if @buttonclicked == 1
      @gamelogic.paused = false
      State.change("menu")
    elsif @buttonclicked == 2
      @gamelogic.paused = false
      State.change("game")
    elsif @buttonclicked == 3
      @gamelogic.paused = false
    elsif @buttonclicked == 4
      if save_game
        @gamelogic.paused = false
        State.printmsg("Game has been saved.", 2)
        State.change("menu")
      else
        State.printmsg("Could not save the game!", 2)
      end
    end
    @buttonclicked = nil
  end

  def self.fullscreen(_is_fullscreen)
    @winx, @winy = Lota::Graphics.dimensions
    @drawcooldown = 0.25
    @cbut = nil
  end
end
# SPDX-SnippetEnd
