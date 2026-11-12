# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's input.lua
# (test/fixtures/flash_blip/game/input.lua, lines 1-592), by the rules of
# doc/contributors/design/translation.md: love.math.setRandomSeed is the
# writer Lota::Math.random_seed= (rule 5), love.keyboard.isDown and
# love.mouse.isDown and Joystick:isDown the predicates down? (rule 8),
# Joystick:getID and getName id, an Array (rules 3 and 4), and name,
# love.timer.getTime Lota::Timer.time, love.event.quit Lota::Event.quit,
# and the keys and gamepad buttons symbols (rule 9). The global table Input
# is the module Input, its fields help_scroll_y and max_help_scroll read
# and write as methods of the same names, its methods called with : are
# module methods, and its locals are its instance variables.
#
# A menu item, a table of text and action to which this file and text.lua
# assign y and height, is a MenuItem, for the attract menu and the pause
# menu alike. A touch, a table of x, y, and time, is a Touch. The
# joysticks connected, the touches, and the touches' first heights are
# Hashes keyed by id, as Lua's tables are; where Lua iterates them with
# pairs, the order does not change what the loop answers. Lua's print is
# puts. Indices into the menus stay 1-based, as the game stores and draws
# them, and index the Arrays less one.

require "gamestate"
require "sound"
require "music"
require "text"
require "settings"
require "powerups"
require "powerups_manager"
require "levels_selector"
require "about"
require "options"
require "game"
require "update_checker"

module Input
  MenuItem = Struct.new(:text, :action, :y, :height)
  Touch = Struct.new(:x, :y, :time, keyword_init: true)

  class << self
    attr_accessor :help_scroll_y, :max_help_scroll
  end

  @help_scroll_y = 0
  @max_help_scroll = 300

  @menu_items = [
    MenuItem.new("ENDLESS MODE", "start_endless"),
    MenuItem.new("ARCADE MODE", "start_arcade"),
    MenuItem.new("HI SCORES", "show_hi_scores"),
    MenuItem.new("OPTIONS", "show_options"),
    MenuItem.new("ABOUT", "show_about"),
    MenuItem.new("HELP", "show_help"),
  ]
  @menu_items << MenuItem.new("EXIT", "exit_game") unless Settings.is_web

  @pause_menu_items = [
    MenuItem.new("RESUME", "resume"),
    MenuItem.new("RESTART", "restart"),
    MenuItem.new("OPTIONS", "show_options"),
    MenuItem.new("HELP", "show_help"),
    MenuItem.new("QUIT TO MENU", "quit_to_menu"),
  ]

  @selected_menu_item = 1
  @selected_pause_menu_item = 1
  @just_pressed = false

  # Touch support variables
  @touch_hold_timer = 0
  @touch_hold_threshold = 0.5
  @is_touch_holding = false
  @ping_interval = 0.5 # 2 pings per second
  @last_ping_time = 0

  @active_touches = {}
  @ping_gesture_threshold = 0.15 # Max time difference for simultaneous detection (150ms)
  @min_simultaneous_touches = 2

  @touch_initial_y = {}
  @has_touchscreen = false
  @touch_start_y = nil
  @touch_id = nil

  def self.get_menu_items
    @menu_items
  end

  def self.get_pause_menu_items
    @pause_menu_items
  end

  def self.get_selected_menu_item
    @selected_menu_item
  end

  def self.set_selected_menu_item(index)
    @selected_menu_item = index
  end

  def self.get_selected_pause_menu_item
    @selected_pause_menu_item
  end

  def self.set_selected_pause_menu_item(index)
    @selected_pause_menu_item = index
  end

  def self.is_just_pressed
    @just_pressed
  end

  def self.keypressed(key)
    if GameState.is("virtual_keyboard")
      require "virtual_keyboard"
      VirtualKeyboard.keypressed(key)
      return
    end

    if GameState.is("attract")
      if key == :up
        @selected_menu_item = [1, @selected_menu_item - 1].max
        Sound.play("blip")
      elsif key == :down
        @selected_menu_item = [@menu_items.size, @selected_menu_item + 1].min
        Sound.play("blip")
      elsif key == :return || key == :space
        action = @menu_items[@selected_menu_item - 1].action
        case action
        when "start_endless"
          GameState.is_attract_mode = false
          Main.current_level_data = nil
          Lota::Math.random_seed = Time.now.to_i
          Main.init_game
        when "start_arcade"
          Game.clear_game_objects
          GameState.set("levels")
        when "show_hi_scores"
          GameState.previous = "attract"
          GameState.set("hi_scores")
        when "show_about"
          GameState.previous = "attract"
          GameState.set("about")
        when "show_options"
          GameState.previous = "attract"
          GameState.set("options")
        when "show_help"
          GameState.previous = GameState.current
          GameState.set("help")
        when "exit_game"
          Lota::Event.quit
        end
      end
    elsif GameState.is("help")
      if key == :escape
        nil
      elsif key == :up
        self.help_scroll_y = [0, help_scroll_y - 20].max
      elsif key == :down
        self.help_scroll_y = [max_help_scroll, help_scroll_y + 20].min
      end
    elsif GameState.is("options")
      Options.keypressed(key)
    elsif GameState.is_paused
      if key == :up
        @selected_pause_menu_item = [1, @selected_pause_menu_item - 1].max
        Sound.play("blip")
      elsif key == :down
        @selected_pause_menu_item = [@pause_menu_items.size, @selected_pause_menu_item + 1].min
        Sound.play("blip")
      elsif key == :return
        action = @pause_menu_items[@selected_pause_menu_item - 1].action
        case action
        when "resume"
          GameState.is_paused = false
        when "restart"
          GameState.is_paused = false
          Main.init_game
        when "show_options"
          GameState.previous = GameState.current
          GameState.set("options")
        when "show_help"
          GameState.previous = GameState.current
          GameState.set("help")
        when "quit_to_menu"
          GameState.is_paused = false
          GameState.is_attract_mode = true
          Main.current_level_data = nil
          Main.init_game
        end
      end
    elsif GameState.is("playing") && (key == :space || key == :return)
      @just_pressed = true if !GameState.is_paused && GameState.ignore_input_timer <= 0
    elsif GameState.is("levels")
      LevelsSelector.keypressed(key)
      return
    end

    Main.init_game if key == :r

    if key == :escape
      if GameState.is("help") || GameState.is("about") || GameState.is("options") || GameState.is("hi_scores")
        GameState.set(GameState.previous || "attract")
      elsif GameState.is_paused
        GameState.is_paused = false
      elsif GameState.is("playing")
        GameState.is_paused = true
      elsif GameState.is("attract")
        Lota::Event.quit unless Settings.is_web
      end
    end

    if key == :c && Game.get_player_circle && GameState.is("playing") && GameState.ignore_input_timer <= 0
      player_circle = Game.get_player_circle
      Powerups.activate_player_ping(
        player_circle.position,
        PowerupsManager.is_phase_shift_active,
        PowerupsManager.get_ping_color
      )
    end

    return unless key == :m

    if Lota::Keyboard.down?(:lshift) || Lota::Keyboard.down?(:rshift)
      Music.stop
      Music.play
    else
      Settings.is_music_enabled = !Settings.is_music_enabled
      Music.toggle_mute(!Settings.is_music_enabled)
      Settings.is_sfx_enabled = !Settings.is_sfx_enabled
      Sound.toggle_mute(!Settings.is_sfx_enabled)
      Settings.save_debounced
    end
  end

  def self.mousemove(x, y)
    if GameState.is("help")
      require "help"
      Help.mousemoved(x, y)
    elsif GameState.is("levels")
      LevelsSelector.mousemove(x, y)
    end
  end

  def self.wheelmoved(_x, y)
    if GameState.is("help")
      self.help_scroll_y = help_scroll_y - (y * 20)
      self.help_scroll_y = [0, help_scroll_y].max
      self.help_scroll_y = [max_help_scroll, help_scroll_y].min
    elsif GameState.is("levels")
      if y.positive?
        # Scroll up
        LevelsSelector.move_up
      elsif y.negative?
        # Scroll down
        LevelsSelector.move_down
      end
    end
  end

  def self.mousepressed(x, y, button)
    if GameState.is("virtual_keyboard")
      require "virtual_keyboard"
      VirtualKeyboard.mousepressed(x, y, button)
      return
    end

    if GameState.is("levels")
      LevelsSelector.mousepressed(x, y, button)
      return
    end

    if GameState.is("about")
      About.mousepressed(x, y, button) if button == 1
      return
    end

    if GameState.is("hi_scores")
      if button == 1
        require "hi_scores"
        GameState.set(GameState.previous || "attract") unless HiScores.mousepressed(x, y, button)
      end
      return
    end

    if GameState.is("options")
      if button == 1 && !Options.mousepressed(x, y, button)
        GameState.set(GameState.previous || "attract")
      end
      return
    end

    if GameState.is("help")
      if button == 1
        require "help"
        Help.mousepressed(x, y, button)
      end
      return
    end

    return if GameState.ignore_input_timer.positive? && !GameState.is_paused

    # Attract menu mouse
    if button == 1 && GameState.is("attract")
      return if UpdateChecker.handle_click(x, y)

      start_y = Settings.window_height * 0.4
      text_percentage = 0.55
      uniform_scale = Text.calculate_uniform_scale(@menu_items, text_percentage)

      y_pos = start_y
      @menu_items.each_with_index do |item, index|
        i = index + 1
        item_width = Text.get_text_width(item.text, uniform_scale)
        item_x = (Settings.window_width - item_width) / 2.0
        item.y = y_pos
        item.height = Text.get_text_height(uniform_scale)
        y_pos += 50
        next unless x >= item_x && x <= item_x + item_width && y >= item.y && y <= item.y + item.height

        set_selected_menu_item(i)
        Sound.play("blip")
        action = item.action
        case action
        when "start_endless"
          GameState.is_attract_mode = false
          Main.current_level_data = nil
          Lota::Math.random_seed = Time.now.to_i
          Main.init_game
        when "start_arcade"
          Game.clear_game_objects
          GameState.set("levels")
        when "show_hi_scores"
          GameState.previous = "attract"
          GameState.set("hi_scores")
        when "show_about"
          GameState.is_paused = true if GameState.is("playing")
          GameState.set("about")
        when "show_options"
          GameState.previous = "attract"
          GameState.set("options")
        when "show_help"
          GameState.previous = GameState.current
          GameState.is_paused = true if GameState.is("playing")
          GameState.set("help")
        when "exit_game"
          Lota::Event.quit
        end
        break
      end
      return
    # Pause menu mouse
    elsif button == 1 && GameState.is_paused
      start_y = Settings.window_height * 0.5
      text_percentage = 0.50
      uniform_scale = Text.calculate_uniform_scale(@pause_menu_items, text_percentage)

      y_pos = start_y
      @pause_menu_items.each_with_index do |item, index|
        i = index + 1
        item_width = Text.get_text_width(item.text, uniform_scale)
        item_x = (Settings.window_width - item_width) / 2.0
        item.y = y_pos
        item.height = Text.get_text_height(uniform_scale)
        y_pos += 50
        next unless x >= item_x && x <= item_x + item_width && y >= item.y && y <= item.y + item.height

        set_selected_pause_menu_item(i)
        Sound.play("blip")
        action = item.action
        case action
        when "resume"
          GameState.is_paused = false
        when "restart"
          GameState.is_paused = false
          Main.init_game
        when "show_options"
          GameState.previous = GameState.current
          GameState.set("options")
        when "show_help"
          GameState.previous = GameState.current
          GameState.set("help")
        when "quit_to_menu"
          GameState.is_paused = false
          GameState.is_attract_mode = true
          Main.current_level_data = nil
          Main.init_game
        end
        break
      end
      return
    end

    @just_pressed = true if button == 1 && GameState.is_not("gameOver") && !GameState.is_paused

    player_circle = Game.get_player_circle
    return unless button == 2 && player_circle && GameState.is("playing")

    Powerups.activate_player_ping(
      player_circle.position,
      PowerupsManager.is_phase_shift_active,
      PowerupsManager.get_ping_color
    )
  end

  # Simulate user input so the game runs automatically in attract mode.
  def self.simulate_attract_input(player_circle)
    click_chance = 0.01
    if player_circle && player_circle.position.y > (Settings.internal_height * 0.7)
      click_chance *= 50 # Multiply click probability by 50
    end
    @just_pressed = true if Lota::Math.random < click_chance
  end

  # Controller support
  @connected_joysticks = {}
  @controller_button_one = 1
  @controller_button_two = 2
  @controller_button_three = 3

  def self.gamepadpressed(_joystick, button)
    if button == :dpup
      keypressed(:up)
    elsif button == :dpdown
      keypressed(:down)
    end
  end

  def self.joystickpressed(_joystick, button)
    if button == @controller_button_one
      keypressed(:return)
    elsif button == @controller_button_two
      keypressed(:c)
    elsif button == @controller_button_three
      keypressed(:escape)
    end
  end

  def self.joystickadded(joystick)
    @connected_joysticks[joystick.id.first] = joystick
    puts "Controller connected: #{joystick.name}"
  end

  def self.joystickremoved(joystick)
    @connected_joysticks.delete(joystick.id.first)
    puts "Controller disconnected: #{joystick.name}"
  end

  def self.get_connected_joysticks
    @connected_joysticks
  end

  def self.is_keyboard_or_mouse_continue
    Lota::Keyboard.down?(:space) || Lota::Keyboard.down?(:return) || Lota::Mouse.down?(1)
  end

  def self.is_controller_continue
    @connected_joysticks.each_value do |joystick|
      return true if joystick.down?(@controller_button_one)
    end
    false
  end

  def self.is_game_over_continue
    is_keyboard_or_mouse_continue || is_controller_continue
  end

  def self.is_level_completed_continue
    is_keyboard_or_mouse_continue || is_controller_continue
  end

  def self.reset_just_pressed
    @just_pressed = false
  end

  def self.trigger_ping
    player_circle = Game.get_player_circle
    return unless player_circle && GameState.is("playing") && GameState.ignore_input_timer <= 0

    Powerups.activate_player_ping(
      player_circle.position,
      PowerupsManager.is_phase_shift_active,
      PowerupsManager.get_ping_color
    )
  end

  def self.update(dt)
    return unless @is_touch_holding

    @touch_hold_timer += dt
    return unless @touch_hold_timer >= @touch_hold_threshold

    # Start pinging continuously
    current_time = Lota::Timer.time
    return unless current_time - @last_ping_time >= @ping_interval

    trigger_ping
    @last_ping_time = current_time
  end

  def self.touchpressed(id, x, y, _dx, _dy, _pressure)
    @has_touchscreen = true

    if GameState.is("help")
      # Store initial touch position for scrolling
      @touch_initial_y[id] = y
      return
    elsif GameState.is("levels")
      @touch_id = id
      @touch_start_y = y
      return
    elsif GameState.is("about")
      return
    elsif GameState.is("attract")
      return
    end

    return unless GameState.is("playing")
    return if GameState.ignore_input_timer.positive? && !GameState.is_paused

    @active_touches[id] = Touch.new(x:, y:, time: Lota::Timer.time)

    # Check for simultaneous touches to trigger direct ping
    simultaneous_touches = 0
    current_time = Lota::Timer.time

    @active_touches.each_value do |touch_data|
      simultaneous_touches += 1 if current_time - touch_data.time <= @ping_gesture_threshold
    end

    if simultaneous_touches >= @min_simultaneous_touches
      trigger_ping
    else
      @is_touch_holding = true
      @touch_hold_timer = 0
    end
  end

  def self.touchmoved(id, x, y, _dx, _dy, _pressure)
    if GameState.is("help") && (@has_touchscreen || Settings.is_mobile) && @touch_initial_y[id]
      # Calculate scroll delta based on touch movement
      delta_y = @touch_initial_y[id] - y
      self.help_scroll_y = help_scroll_y + delta_y
      self.help_scroll_y = [0, help_scroll_y].max
      self.help_scroll_y = [max_help_scroll, help_scroll_y].min
      # Update initial position for continuous scrolling
      @touch_initial_y[id] = y
      return
    elsif GameState.is("levels") && (@has_touchscreen || Settings.is_mobile) && @touch_id == id && @touch_start_y
      delta_y = y - @touch_start_y
      if delta_y.abs > 50 # threshold for swipe
        if delta_y.positive?
          # Swipe down
          LevelsSelector.move_down
        else
          # Swipe up
          LevelsSelector.move_up
        end
        @touch_start_y = y # reset for continuous swiping
      end
      return
    end

    # Handle touch movement as mouse movement
    mousemove(x, y)
  end

  def self.touchreleased(id, x, y, _dx, _dy, _pressure)
    if GameState.is("help")
      # Clear touch data for help screen
      @touch_initial_y.delete(id)
      require "help"
      Help.mousereleased(x, y, 1)
      return
    elsif GameState.is("levels") && id == @touch_id
      @touch_id = nil
      @touch_start_y = nil
      return
    end

    @active_touches.delete(id)

    return unless @is_touch_holding

    # Stop pinging when touch is released
    @is_touch_holding = false
    @touch_hold_timer = 0
  end

  def self.mousereleased(x, y, button)
    return unless GameState.is("help")

    require "help"
    Help.mousereleased(x, y, button)
  end
end
# SPDX-SnippetEnd
