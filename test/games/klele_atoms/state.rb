# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' state.lua
# (test/fixtures/klele_atoms/state.lua, lines 1-201), as main.rb
# describes: the state table is the module State, whose Lua locals are its
# instance variables, and each state a module whose functions it calls when
# the state defines them, as Lua tests a table's field. love.filesystem.write
# becomes Lota::Filesystem.write, getDimensions dimensions (rules 3 and 4),
# newFont Font.new (rule 2), setColor a writer (rules 5 and 6), the
# alignment a symbol (rule 9), and updateMode update_mode (rule 13). The
# special keys are symbols, as Lota names keys (rule 9).

require "mobile" # Mobile/scaling mode
require "kbmode" # Keyboard mode

module State
  @curstate = nil # Current state name

  @curstatedata = nil # Current state table/class

  @globalmsg = ["", 0.0] # string, time (in seconds)

  @msgfont = nil # Font of size 16*scale, used by printmsg

  SPECIAL_KEYS = {
    f3: -> {
      Mobile.toggle_win_resizing
      @msgfont = nil
      @curstatedata.fullscreen(CA.use_scaling) if @curstatedata.respond_to?(:fullscreen)
    },
    f4: -> {
      Mobile.toggle_fullscreen
      @msgfont = nil
      @curstatedata.fullscreen(CA.use_scaling) if @curstatedata.respond_to?(:fullscreen)
    },
  }.freeze

  @list = {} # List of states

  class << self
    attr_reader :list
  end

  def self.save_settings
    fsval = CA.full_screen ? 1 : 0 # Convert boolean to number (0 - false, 1 - true)
    wrval = CA.win_resizing ? 1 : 0
    settstr = "#{CA.grid_w}\n#{CA.grid_h}\n#{CA.play_exp}\n#{CA.player1}\n#{CA.player2}\n#{CA.player3}\n" \
      "#{CA.player4}\n#{fsval}\n#{wrval}"
    Lota::Filesystem.write("settings2.txt", settstr)
  end

  def self.update(dt)
    @globalmsg[1] -= dt if @globalmsg[1] > 0
    KbMode.update(dt) if CA.kb_mode
    @curstatedata.update(dt) if @curstatedata.respond_to?(:update)
  end

  def self.draw
    Mobile.predraw if CA.use_scaling
    @curstatedata.draw if @curstatedata.respond_to?(:draw)
    KbMode.draw if CA.kb_mode
    Mobile.postdraw if CA.use_scaling
    return unless @globalmsg[1] > 0

    wx, = Lota::Graphics.dimensions
    @msgfont ||= Lota::Graphics::Font.new(16 * get_window_scale)
    Lota::Graphics.color = 0, 1, 0, 1
    Lota::Graphics.printf(@globalmsg[0], @msgfont, 0, 0, wx, :center)
    Lota::Graphics.color = 1, 1, 1, 1
  end

  def self.keypressed(key, scancode, isrepeat)
    if CA.kb_mode && KbMode.keypressed(key)
      # Nothing
    elsif @curstatedata.respond_to?(:keypressed)
      @curstatedata.keypressed(key, scancode, isrepeat)
    end
  end

  def self.keyreleased(key)
    if CA.kb_mode && KbMode.keyreleased(key)
      # Nothing
    elsif !CA.is_mobile && SPECIAL_KEYS[key]
      SPECIAL_KEYS[key].call
    elsif @curstatedata.respond_to?(:keyreleased)
      @curstatedata.keyreleased(key)
    end
  end

  def self.mousepressed(x, y, button)
    x, y = Mobile.convertcoords(x, y) if CA.use_scaling
    @curstatedata.mousepressed(x, y, button) if @curstatedata.respond_to?(:mousepressed)
  end

  def self.mousereleased(x, y, button)
    x, y = Mobile.convertcoords(x, y) if CA.use_scaling
    @curstatedata.mousereleased(x, y, button) if @curstatedata.respond_to?(:mousereleased)
  end

  def self.focus(focus) # Window focus callback function
    @curstatedata.focus(focus) if @curstatedata.respond_to?(:focus)
  end

  def self.quit # love.quit callback function, saves settings
    retval = false
    retval = @curstatedata.quit if @curstatedata.respond_to?(:quit)
    save_settings
    retval
  end

  def self.resize(x, y) # love.resize callback function
    if CA.use_scaling
      Mobile.resize(x, y)
      @msgfont = nil
    end
    @curstatedata.resize(x, y) if @curstatedata.respond_to?(:resize)
  end

  def self.change(name, argtab = nil) # Change state
    Mobile.init if CA.use_scaling
    raise "Invalid state \"#{name}\"!" unless @list[name]

    @curstatedata.stop(name) if @curstatedata.respond_to?(:stop)
    laststate = @curstate
    @curstate = name
    @curstatedata = @list[name]
    return unless @curstatedata.respond_to?(:init)

    newx, newy = argtab.is_a?(Array) ? @curstatedata.init(laststate, argtab) : @curstatedata.init(laststate)
    return unless newx && newy

    if CA.use_scaling
      Mobile.setresolution(newx, newy)
      @msgfont = nil
    else
      KbMode.set_pos(newx / 2.0, newy / 2.0) if CA.kb_mode
      Lota::Window.update_mode(newx, newy)
    end
  end

  def self.printmsg(str, time = nil) # Print a message on the top-left corner for a specified time in seconds
    @globalmsg[0] = str || ""
    @globalmsg[1] = time || 1
  end

  def self.get_mouse_pos # Get current mouse position (use this instead of love.mouse.getPosition()/getX()/getY())
    return KbMode.get_pos if CA.kb_mode

    mx, my = Lota::Mouse.position
    mx, my = Mobile.convertcoords(mx, my) if CA.use_scaling
    [mx, my]
  end

  def self.get_window_size
    if CA.use_scaling
      Mobile.getresolution
    else
      Lota::Graphics.dimensions
    end
  end

  def self.get_window_scale
    if CA.use_scaling
      Mobile.getscale
    else
      1
    end
  end

  def self.absolute_draw_mode(enable)
    Mobile.absolutedrawmode(enable) if CA.use_scaling
  end
end
# SPDX-SnippetEnd
