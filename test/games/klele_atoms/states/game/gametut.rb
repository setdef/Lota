# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' states/game/gametut.lua
# (test/fixtures/klele_atoms/states/game/gametut.lua, lines 1-262), as
# main.rb and gamelogic.rb describe: setColor becomes a writer (rules 5
# and 6), and the draw modes and the alignment symbols (rule 9). Each
# event is an Array, so Lua's events[i][2] is events[i][1]. The tutorial's
# update reads a global, animplaying, that the game never sets, which
# Lua reads as nil; Ruby reads CA.animplaying, never set either. Its
# skiptab is never set, so it is nil too.

module GameTut
  @logic = nil

  # Event variable layout:
  # name, arg1, arg2, ...

  # "textbox", str, time, type - prints a textbox (types are described in the 'gametut.text' comment)
  # "setptypes", {p1,p2,p3,p4} - set player types (0 - not present, 1 - player, 2 - AI, 3 - dummy/scripted)
  # "curplayer", number - set current player
  # "putatom", player/nil, x, y - put an atom (simulate a click --> player == nil uses logic.curplayer)
  # "setatoms", player/nil, x, y, count - set atoms on a tile (no new turn --> player == nil uses logic.curplayer)
  # "allow", {{x,y}, ...} - set a new allowed atoms table or no atoms allowed if arg1 is an empty table (UNUSED,
  #   NOT RECOMMENDED)
  # "wait", time - pause execution for a certain time in seconds
  # "clear" - clear the entire grid
  EVENTS = [
    ["setptypes", [9, 9, 9, 9]],
    [
      "textbox",
      "Welcome to the KłełeAtoms tutorial! It will teach you the basics of KłełeAtoms.\n\nYou can " \
        "always press the pause button to quit the tutorial.\n\nPress any key or click the text box to continue...",
      0,
      1,
],
    ["textbox", "Each player can place one atom per turn on empty or their own tiles.", 0, 1],
    ["setatoms", 3, 4, 2, 1],
    ["setatoms", 4, 5, 2, 2],
    ["wait", 0.5],
    ["putatom", 1, 2, 2],
    ["curplayer", 2],
    ["wait", 0.5],
    ["putatom", 2, 3, 2],
    ["curplayer", 3],
    ["wait", 0.5],
    ["putatom", 3, 4, 2],
    ["curplayer", 4],
    ["wait", 0.5],
    ["putatom", 4, 5, 2],
    ["curplayer", 1],
    ["wait", 1],
    ["setptypes", [9, 9, 9, 9]],
    [
      "textbox",
      "The atoms will explode if too many are present on one tile.\n\nAtoms in the corners explode if 2 " \
        "or more are present.",
      0,
      1,
],
    ["clear"],
    ["setatoms", 1, 1, 1, 1],
    ["wait", 0.5],
    ["putatom", 1, 1, 1],
    ["wait", 1],
    ["setptypes", [9, 9, 9, 9]],
    ["textbox", "On the sides they explode if 3 or more are present.", 0, 1],
    ["clear"],
    ["setatoms", 2, 1, 2, 2],
    ["wait", 0.5],
    ["putatom", 2, 1, 2],
    ["wait", 1],
    ["setptypes", [9, 9, 9, 9]],
    ["textbox", "Anywhere else they only explode if 4 or more are present.", 0, 1],
    ["clear"],
    ["setatoms", 3, 2, 2, 3],
    ["wait", 0.5],
    ["putatom", 3, 2, 2],
    ["wait", 1],
    ["setptypes", [9, 9, 9, 9]],
    ["textbox", "Atom explosions can make nearby atoms explode, causing chain reactions.", 0, 1],
    ["clear"],
    ["setatoms", 4, 2, 2, 3],
    ["setatoms", 4, 1, 1, 1],
    ["setatoms", 4, 2, 1, 2],
    ["setatoms", 4, 1, 2, 2],
    ["wait", 0.5],
    ["putatom", 4, 2, 2],
    ["wait", 1],
    ["textbox", "Exploding atoms turn nearby enemy atoms into current player's atoms.", 0, 1],
    ["clear"],
    ["setptypes", [9, 9, 9, 9]],
    ["curplayer", 1],
    ["setatoms", 1, 2, 2, 3],
    ["setatoms", 2, 1, 2, 1],
    ["setatoms", 3, 2, 1, 1],
    ["setatoms", 4, 3, 2, 1],
    ["setatoms", 2, 2, 3, 1],
    ["setatoms", 3, 5, 5, 1],
    ["wait", 0.5],
    ["putatom", 1, 2, 2],
    ["wait", 1],
    [
      "textbox",
      "If the player loses all their atoms, they're out.\n\nThe last standing player wins the game.\n\n" \
        "That's it!",
      0,
      1,
],
  ].freeze

  class << self
    attr_accessor :text, :allowedtiles, :lastparse, :waittimer, :finished, :skiptab
  end

  def self.parse_next # Event parser, also handles state change after finishing
    @lastparse += 1
    if @lastparse > EVENTS.size
      @finished = true
      State.change("menu")
      return true
    end
    i = @lastparse
    event = EVENTS[i - 1]
    name = event[0]
    if name == "setptypes"
      if event[1].is_a?(Array)
        pttab = event[1]
        1.upto(4) do |p|
          next unless pttab[p - 1] > 0

          @logic.curplayer = p if @logic.curplayer == -1
          @logic.players += 1
          @logic.playertab[p] = true
          @logic.playeratoms[p] = 0
          @logic.playermoved[p] = false
          if pttab[p - 1] == 9
            @logic.playertab[p] = "dummy"
          elsif pttab[p - 1] > 1
            @logic.ai.playertab[p] = true
            @logic.ai.difficulty[p] = pttab[p - 1] - 1
          else
            @logic.ai.playertab[p] = false
          end
        end
      else
        State.printmsg("Tutorial event #{i}: arg1 is not a table", 5)
        State.change("menu")
        @finished = true
        return
      end
    elsif name == "curplayer"
      if event[1].is_a?(Numeric)
        @logic.curplayer = event[1]
      else
        State.printmsg("Tutorial event #{i}: arg1 is not a number", 5)
        State.change("menu")
        @finished = true
        return
      end
    elsif name == "textbox"
      @text = [event[1], event[2], event[3]]
    elsif name == "putatom"
      oldcplayer = @logic.curplayer
      @logic.curplayer = event[1] || @logic.curplayer
      @logic.clicked_tile(event[2], event[3], true)
      @logic.curplayer = oldcplayer
      return
    elsif name == "setatoms"
      pplayer = event[1] || @logic.curplayer
      atcount = event[4] || 1
      @logic.set_atoms(event[2], event[3], atcount, pplayer)
    elsif name == "allow"
      if event[1].is_a?(Array)
        @allowedtiles = event[1]
      else
        State.printmsg("Tutorial event #{i}: arg1 is not a table", 5)
        State.change("menu")
        @finished = true
        return
      end
    elsif name == "wait"
      @waittimer = event[1].is_a?(Numeric) ? event[1] : 0.0
    elsif name == "clear"
      1.upto(@logic.grid.size) do |x|
        1.upto(@logic.grid[1].size) do |y|
          @logic.grid[x][y] = GameLogic::Tile.new(player: 0, atoms: [], explode: 0)
        end
      end
    else
      State.printmsg("Tutorial event #{i}: incorrect event name", 5)
      State.change("menu")
      @finished = true
      return
    end
    nil
  end

  @text = [nil, 0, 0] # string, time, type (0 - none, 1 - wait for click, 2 - timed, 3 - timed + wait)

  @allowedtiles = [] # If empty, no tiles are allowed, otherwise filled with {x,y} tables

  @lastparse = 0 # Last parsed event (0 if none)

  @waittimer = 0.0 # Event delay timer

  @finished = false # Has the tutorial been finished?

  def self.init(gamelogic)
    @logic = gamelogic
    @text = [nil, 0, 0]
    @allowedtiles = []
    @lastparse = 0
    @waittimer = 0.0
    @finished = false
  end

  def self.update(dt)
    return false if @finished

    @waittimer = [0, @waittimer - dt].max
    while !CA.animplaying && @logic.atomstack.empty? && (@text[2] <= 0 || !@text[0])
      break if @waittimer > 0
      return nil if parse_next
    end
    playergood = (!@skiptab || @skiptab.empty?)
    lastplayer = @logic.curplayer
    until playergood
      @skiptab.each do |v|
        if v == @logic.curplayer
          @logic.next_player
          break
        end
      end
      if @logic.curplayer == lastplayer
        playergood = true
      else
        lastplayer = @logic.curplayer
      end
    end
    return unless @text && @text[0] && @text[2] > 0

    if @text[1] > 0 && @text[2] >= 2
      @text[1] -= dt
      @text = [nil, 0, 0] if @text[1] <= 0
    end
    true
  end

  def self.draw
    return if @finished

    if @allowedtiles && @allowedtiles.size > 0
      Lota::Graphics.color = 0, 0, 0, 0.2
      Lota::Graphics.rectangle(:fill, 10, 90, @logic.winsize[0] - 10, @logic.winsize[1] - 90)
      Lota::Graphics.color = 0.5, 0.5, 0.5, 1
      gsize = @logic.c_gridsize
      @allowedtiles.each do |v|
        Lota::Graphics.rectangle(:fill, 11 + (v[0] * gsize), 91 + (v[1] * gsize), gsize - 1, gsize - 1)
      end
    end
    return unless @text && @text[0]

    Lota::Graphics.color = 0, 0, 0, 0.5
    Lota::Graphics.rectangle(:fill, 0, 0, @logic.winsize[0], @logic.winsize[1])
    Lota::Graphics.color = 0.5, 0.5, 0.5, 1
    Lota::Graphics.rectangle(:fill, 0, @logic.winsize[1] / 2.0, @logic.winsize[0], @logic.winsize[1] / 2.0)
    Lota::Graphics.color = 0, 1, 0, 1
    Lota::Graphics.rectangle(:line, 2, (@logic.winsize[1] / 2.0) + 2, @logic.winsize[0] - 4,
      (@logic.winsize[1] / 2.0) - 4)
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.printf(@text[0], CA.font16, 8, (@logic.winsize[1] / 2.0) + 8, @logic.winsize[0] - 16, :left)
  end

  def self.mousepressed(x, y, _button)
    return false if @finished

    if @text && @text[0] && (@text[2] == 1 || @text[2] == 3)
      @text = [nil, 0, 0]
      return true
    end
    return true if @logic.playertab[@logic.curplayer] == "dummy"

    pressx = ((x - 10) / @logic.c_gridsize.to_f).floor + 1
    pressy = ((y - 90) / @logic.c_gridsize.to_f).floor + 1
    @allowedtiles.each do |v|
      return false if v[0] == pressx && v[1] == pressy
    end
    true
  end

  def self.keyreleased(_key)
    return if @finished || CA.kb_mode

    @text = [nil, 0, 0] if @text && @text[0] && (@text[2] == 1 || @text[2] == 3)
  end
end
# SPDX-SnippetEnd
