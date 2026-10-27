# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' states/menu/menustate.lua
# (test/fixtures/klele_atoms/states/menu/menustate.lua, lines 1-414), as
# main.rb and gamelogic.rb describe: newImage becomes Image.new and
# newSource Lota::Audio::Source.new (rule 2), getTitle title (rule 3),
# Texture:getDimensions dimensions (rules 3 and 4), setColor a writer
# (rules 5 and 6), love.event.quit Lota::Event.quit, and the draw modes,
# the alignment, the source type, and the keys symbols (rule 9). Lua's
# string.sub(12, -1) is the title from its twelfth character on, and the
# text Lua's print draws of a number, which tostring writes, is its to_s.
#
# A button, a table of up to ten values that the code reads by position,
# is a Button with a field for each; its icon and description are an
# Image or a String, or a lambda, where Lua stores a function, which the
# code calls where Lua calls one. A falling atom, a table of six, is a
# MenuAtom. The colors, indexed from 0, are an Array. The globals the
# buttons name, which Lua reads through _G, are CA's fields, read by name
# with [].

module MenuState
  Button = Struct.new(:icon, :description, :x, :y, :type, :value1, :value2, :value3, :value4, :value5)
  MenuAtom = Struct.new(:x, :y, :color, :xspeed, :yspeed, :atom_count)

  MBG = Lota::Graphics::Image.new("graphics/m_bg.png")

  MBUTTON = Lota::Graphics::Image.new("graphics/m_button.png")

  MBUTSEL = Lota::Graphics::Image.new("graphics/m_butsel.png")

  MSBUTTON = Lota::Graphics::Image.new("graphics/m_sbutton.png")

  MSBUTSEL = Lota::Graphics::Image.new("graphics/m_sbutsel.png")

  MGH = Lota::Graphics::Image.new("graphics/m_gh.png")

  MGW = Lota::Graphics::Image.new("graphics/m_gw.png")

  MPLAY = Lota::Graphics::Image.new("graphics/m_play.png")

  MPLAYSAV = Lota::Graphics::Image.new("graphics/m_playsav.png")

  MPLAYER = Lota::Graphics::Image.new("graphics/m_player.png")

  MPLAYERNO = Lota::Graphics::Image.new("graphics/m_playerno.png")

  MTUTORIAL = Lota::Graphics::Image.new("graphics/m_tutorial.png")

  MLEVEL = [
    Lota::Graphics::Image.new("graphics/m_ailevel1.png"),
    Lota::Graphics::Image.new("graphics/m_ailevel2.png"),
    Lota::Graphics::Image.new("graphics/m_ailevel3.png"),
].freeze

  MCPU = Lota::Graphics::Image.new("graphics/m_cpu.png")

  CATOM = Lota::Graphics::Image.new("graphics/atom.png")

  KALOGO = Lota::Graphics::Image.new("graphics/m_kalogo.png")

  ATOMPARTS = [
    Lota::Graphics::Image.new("graphics/m_atp1.png"),
    Lota::Graphics::Image.new("graphics/m_atp2.png"),
    Lota::Graphics::Image.new("graphics/m_atp3.png"),
].freeze

  @menutimer = 0.0 # Timer to prevent accidental button presses

  @buttontimer = 0.0 # Button press timer

  @buttonpressed = 0 # pressed button number (0 if none)

  @buttonstepback = false # Should button value go backwards?

  @requestedfunc = nil # Requested function (for click type buttons)

  @issavefile = false # Was the game saved before? (shows a saved game play button variant if true)

  SNDCLICK = Lota::Audio::Source.new("sounds/click.wav", :static)

  @madebystr = "Made by Nightwolf-47" # Attribution string (bottom-right corner)

  VERSIONSTR = "v#{Lota::Window.title[11..]}" # version number string

  PLAYFUNC = -> (_x, _y, _button = nil) { # Play button function: start the game
    State.change("game")
  }

  MPLAYICON = -> { # Return correct play button icon
    @issavefile ? MPLAYSAV : MPLAY
  }

  MCOLTAB = [ # table of atom colors by player number
    [0.2, 0.2, 0.2, 1], # only for testing
    [1, 0.2, 0.2, 1], # red
    [0.2, 0.4, 1, 1], # blue
    [0, 1, 0, 1], # green
    [1, 1, 0, 1], # yellow
  ].freeze

  PVALNAMES = [ # Player type variable names
    :player1,
    :player2,
    :player3,
    :player4,
  ].freeze

  def self.active_player_count # Returns the amount of non-empty player slots in the menu
    pcount = 0
    1.upto(4) do |i|
      pcount += 1 if CA[PVALNAMES[i - 1]] > 0
    end
    pcount
  end

  def self.give_p_icon(pnum) # Give appropriate player type icon(s)
    val = CA[PVALNAMES[pnum - 1]]
    if val == 0
      MPLAYERNO
    elsif val == 1
      [MPLAYER, MCOLTAB[pnum]]
    elsif val > 1
      [MCPU, MCOLTAB[pnum], MLEVEL[val - 2]]
    end
  end

  def self.switch_p_val(pnum, button) # Change player type value after button has been clicked
    val = CA[PVALNAMES[pnum - 1]]
    if button == 2
      val -= 1
      val = 4 if val < 0 || (val == 0 && active_player_count <= 2)
    else
      val += 1
      if val > 4
        val = (active_player_count <= 2) ? 1 : 0
      end
    end
    CA[PVALNAMES[pnum - 1]] = val
  end

  # The small buttons' function for player +pnum+: given no position, its
  # icons, which drawing asks for; given one, a click.
  def self.player_button(pnum)
    lambda do |x = nil, _y = nil, button = nil|
      if !x # Drawing function
        give_p_icon(pnum)
      else # Click function
        switch_p_val(pnum, button)
      end
    end
  end

  MP1BUTTON = player_button(1)

  MP2BUTTON = player_button(2)

  MP3BUTTON = player_button(3)

  MP4BUTTON = player_button(4)

  PTSTRFUNC = lambda { |num|
    num -= 3
    if CA[PVALNAMES[num - 1]] == 0
      "Player #{num} type (nothing)"
    elsif CA[PVALNAMES[num - 1]] == 1
      "Player #{num} type (human)"
    else
      "Player #{num} type (AI #{CA[PVALNAMES[num - 1]] - 1})"
    end
  }

  TUTORIALFUNC = -> (_x, _y, _button) {
    State.change("game", ["tutorial"])
  }

  @menuatoms = [] # Table of background atoms
  # Format: {x,y,playerColor,xspeed,yspeed,atomCount}
  # playerColor is a number from 1 to 4
  # Atoms move (xspeed,yspeed) units per second

  # {icon,description,x,y,type,val1,val2,val3,val4,val5}
  # icon can be either a Drawable or a function returning Drawable and Color (default {1,1,1,1})
  # type == "click" -> val1 - function(x,y,button)
  # type == "slider" -> val1 - global_var_name, val2 - min_value, val3 - max_value, val4 - delay, val5 - speed
  # type == "switch" -> val1 - global_var_name
  # type == "small" -> val1 - function(x,y,button)
  # type == "nofunc" -> no values
  BUTTONS = [
    Button.new(MPLAYICON, "Start the game.", 245, 205, "click", PLAYFUNC), # Play button
    Button.new(MGW, "Set grid width. (7-30)", 50, 325, "slider", :grid_w, 7, 30, 0.3, 0.1), # Grid Width
    Button.new(MGH, "Set grid height. (4-20)", 245, 325, "slider", :grid_h, 4, 20, 0.3, 0.1), # Grid Height
    Button.new(MP1BUTTON, PTSTRFUNC, 425, 205, "small", MP1BUTTON), # Player 1 type
    Button.new(MP2BUTTON, PTSTRFUNC, 516, 205, "small", MP2BUTTON), # Player 2 type
    Button.new(MP3BUTTON, PTSTRFUNC, 425, 325, "small", MP3BUTTON), # Player 3 type
    Button.new(MP4BUTTON, PTSTRFUNC, 516, 325, "small", MP4BUTTON), # Player 4 type
    Button.new(MTUTORIAL, "Start the tutorial.", 50, 205, "click", TUTORIALFUNC), # Tutorial button
  ].freeze

  def self.spawn_atom(color, xpos, maxatoms) # Spawn menu background atoms unless atom count > maxatoms
    return if @menuatoms.size >= maxatoms

    @menuatoms.push(MenuAtom.new(xpos, -50, color, Lota::Math.random(-200, 200), Lota::Math.random(100, 300),
      Lota::Math.random(1, 3)))
  end

  def self.movestep(varname, min, max) # Add 1 to value, set to minimal value if too high
    CA[varname] += 1
    min, max = max, min if min > max
    CA[varname] = min if CA[varname] > max
  end

  def self.movestepback(varname, min, max) # Remove 1 from value, set to max value if too low
    CA[varname] -= 1
    min, max = max, min if min > max
    CA[varname] = max if CA[varname] < min
  end

  def self.drawicons(icon1, icon2, x, y)
    Lota::Graphics.draw(icon1, x, y)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.draw(icon2, x, y) if icon2
  end

  # Move the value and play click sound every `speed` seconds when the button is pressed
  def self.sliderclicked(varname, min, max, speed)
    return if !speed || speed == 0
    return if @buttontimer < speed

    amount = (@buttontimer / speed).floor
    @buttontimer -= (amount * speed)
    Lota::Audio.play(SNDCLICK)
    if @buttonstepback
      1.upto(amount) do
        movestepback(varname, min, max)
      end
    else
      1.upto(amount) do
        movestep(varname, min, max)
      end
    end
  end

  def self.init(_laststate = nil, _argtab = nil) # Initialize/modify some values, check for saved game and set resolution
    @menutimer = 0.0
    @buttontimer = 0.0
    @buttonpressed = 0
    @buttonstepback = false
    if Lota::Filesystem.info("savegame.ksf")
      BUTTONS[0].description = "Resume a saved game."
      @issavefile = true
    else
      BUTTONS[0].description = "Start the game."
      @issavefile = false
    end
    winh = Lota::Graphics.height
    winw = Lota::Graphics.width
    if CA.is_mobile
      BUTTONS[1].value3 = 18
      BUTTONS[2].value3 = 10
      BUTTONS[1].description = "Set grid width. (7-18)"
      BUTTONS[2].description = "Set grid height. (4-10)"
    end
    @madebystr = "Made by KleleMaster" if CA.os_type == "Web" # On Newgrounds, my nick is KleleMaster
    [640, 480] if winw != 640 || winh != 480 || CA.os_type == "Web" || CA.use_scaling
  end

  def self.update(dt)
    @menutimer += dt
    if @buttonpressed > 0 && BUTTONS[@buttonpressed - 1].type == "slider"
      @buttontimer += dt
      btab = BUTTONS[@buttonpressed - 1]
      sliderclicked(btab.value1, btab.value2, btab.value3, btab.value5)
    end
    newatoms = []
    @menuatoms.each do |v|
      v.x += v.xspeed * dt
      v.y += v.yspeed * dt
      newatoms.push(v) unless v.x <= -44 || v.x >= 640 || v.y >= 524
    end
    @menuatoms = newatoms
    spawn_atom(Lota::Math.random(1, 4), Lota::Math.random(20, 620), 15)
  end

  def self.hover?(v, mx, my)
    (v.type == "small" && mx >= v.x && mx < v.x + 84 && my >= v.y && my < v.y + 75) ||
      (v.type != "small" && mx >= v.x && mx < v.x + 150 && my >= v.y && my < v.y + 75)
  end

  def self.draw
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.draw(MBG)
    @menuatoms.each do |v|
      Lota::Graphics.color = MCOLTAB[v.color]
      Lota::Graphics.draw(ATOMPARTS[v.atom_count - 1], v.x, v.y)
    end
    BUTTONS.each.with_index(1) do |v, k|
      buttonselected = false
      descstr = v.description # button description
      descstr = v.description.call(k) if v.description.is_a?(Proc)
      if @buttonpressed == 0 || @buttonpressed == k
        mx, my = State.get_mouse_pos
        if hover?(v, mx, my) # hover
          buttonselected = true
          if @buttonpressed == 0
            Lota::Graphics.color = 1, 0.65, 0, 1
            Lota::Graphics.printf(descstr, CA.font24, 20, 425, 600, :center)
          end
        end
      end
      Lota::Graphics.color = 1, 1, 1, 1
      if v.type == "small"
        Lota::Graphics.draw(buttonselected ? MSBUTSEL : MSBUTTON, v.x, v.y)
      else
        Lota::Graphics.draw(buttonselected ? MBUTSEL : MBUTTON, v.x, v.y)
      end
      micon = v.icon # First icon
      ncoltab = nil # Color table for first icon
      micon2 = nil # Second icon
      micon, ncoltab, micon2 = v.icon.call if v.icon.is_a?(Proc)
      Lota::Graphics.color = ncoltab if ncoltab
      if v.type == "click" || v.type == "nofunc"
        drawicons(micon, micon2, v.x + 43, v.y + 5)
      elsif v.type == "slider"
        drawicons(micon, micon2, v.x + 10, v.y + 5)
        Lota::Graphics.color = 0, 0, 0, 1
        Lota::Graphics.print(CA[v.value1].to_s, CA.font24, v.x + 100, v.y + 23)
      elsif v.type == "small"
        drawicons(micon, micon2, v.x + 10, v.y + 5)
      elsif v.type == "switch"
        drawicons(micon, micon2, v.x + 10, v.y + 5)
        Lota::Graphics.color = 0, 0, 0, 1
        Lota::Graphics.print(CA[v.value1].to_s, CA.font24, v.x + 100, v.y + 23)
      end
      Lota::Graphics.color = 1, 1, 1, 1
    end
    if @buttonpressed > 0
      descstr = BUTTONS[@buttonpressed - 1].description # button description
      descstr = descstr.call(@buttonpressed) if descstr.is_a?(Proc)
      Lota::Graphics.color = 1, 0.65, 0, 1
      Lota::Graphics.printf(descstr, CA.font24, 20, 425, 600, :center)
    end
    Lota::Graphics.color = 1, 1, 1, 1
    klwidth, = KALOGO.dimensions
    Lota::Graphics.draw(KALOGO, (640 - klwidth) / 2.0, 0)
    Lota::Graphics.printf(@madebystr, CA.font16, 5, 460, 630, :right)
    Lota::Graphics.print(VERSIONSTR, CA.font16, 5, 460)
    if CA.play_exp == 1 && @menutimer.floor % 2 == 0 # Show tutorial message to new players
      Lota::Graphics.color = 1, 0.65, 0, 1
      tutbut = BUTTONS.last
      Lota::Graphics.printf("TUTORIAL!", CA.font24, tutbut.x, tutbut.y - 40, 150, :center)
    end
    Lota::Graphics.color = 0, 0, 0, 1
    Lota::Graphics.rectangle(:fill, -50, 0, 50, 480)
    Lota::Graphics.rectangle(:fill, 640, 0, 50, 480)
    if CA.use_scaling # Draw extended background
      Lota::Graphics.color = 1, 1, 1, 0.75
      Lota::Graphics.draw(MBG, -640)
      Lota::Graphics.draw(MBG, 640)
      Lota::Graphics.color = 0, 0, 0.40, 1
      Lota::Graphics.rectangle(:fill, 0, -480, 640, 480)
      Lota::Graphics.color = 0, 0, 0.07, 1
      Lota::Graphics.rectangle(:fill, 0, 480, 640, 480)
    end
    Lota::Graphics.color = 1, 1, 1, 1
  end

  def self.keypressed(key, _scancode = nil, _isrepeat = nil)
    Lota::Event.quit(0) if CA.os_type != "Web" && @menutimer >= 0.3 && key == :escape
  end

  def self.mousepressed(x, y, button)
    return if @menutimer < 0.3 || ![1, 2].include?(button)

    BUTTONS.each.with_index(1) do |v, k|
      next unless hover?(v, x, y) # pressed

      Lota::Audio.play(SNDCLICK)
      if v.type == "click" || v.type == "small"
        @requestedfunc = [v.value1, x, y, button]
      elsif v.type == "slider"
        if button == 1
          movestep(v.value1, v.value2, v.value3)
          @buttonstepback = false
        else
          movestepback(v.value1, v.value2, v.value3)
          @buttonstepback = true
        end
        @buttontimer = -v.value4
      elsif v.type == "switch"
        CA[v.value1] = !CA[v.value1]
      end
      @buttonpressed = k
    end
  end

  def self.mousereleased(_x, _y, button)
    return unless @menutimer >= 0.3

    if button == 1
      @buttonpressed = 0
      @buttontimer = 0.0
    elsif button == 2
      @buttonpressed = 0
      @buttontimer = 0.0
      @buttonstepback = false
    end
    return unless @requestedfunc

    func, rx, ry, rbutton = @requestedfunc
    func.call(rx, ry, rbutton)
    @requestedfunc = nil
  end

  def self.stop(_name = nil) = State.save_settings # Save settings
end
# SPDX-SnippetEnd
