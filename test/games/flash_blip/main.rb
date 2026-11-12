# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's main.lua
# (test/fixtures/flash_blip/game/main.lua, lines 1-924), by the rules of
# doc/contributors/design/translation.md: love.window.setMode becomes
# Lota::Window.set_mode, which keeps its set_ because it returns whether it
# worked (rule 7), with its option table as keywords (rule 10);
# getDesktopDimensions, getWidth, getHeight, getFPS, and getTime drop their
# get (rule 3), and those returning several values return an Array (rule 4);
# setTitle, setColor, and setCanvas become writers (rules 5 and 6), and
# setCanvas() Lota::Graphics.canvas = nil; newCanvas becomes
# Lota::Graphics::Canvas.new (rule 2); the draw mode "fill" a symbol
# (rule 9); love.math.random Lota::Math.random (rule 1); and each push ...
# pop paired in one function the block form of push (rule 11). love.load,
# love.update, love.draw, and the input callbacks become methods on Lota
# (doc/contributors/design/game.md), each declaring the arguments Lua's
# does.
#
# Main, a Lua global table, is the module Main, its field
# current_level_data a reader and writer, and the functions main.lua puts
# on it (apply_glow_setting, apply_blur_setting, init_game, restart_game)
# methods of it. main.lua's locals are instance variables of Main and its
# local functions methods of Main, and the global function particle, which
# game.lua calls, is Main.particle. love.load, love.update, and love.draw
# read and write those locals, so their bodies are Main.load, Main.update,
# and Main.draw, which Lota.load, Lota.update, and Lota.draw call. A Lua
# function stored to call later, the splash's on_done, the glow benchmark's
# callback, the highscore flow's continuation, and the ones Game.update and
# Game.update_effects take, is anything that answers call: a lambda, a
# Method, or, where Lua passes it arguments it ignores, a proc. Lua's
# Input:method(...) is Input.method(...), and OverlayStats.handleKeyboard
# is OverlayStats.handle_keyboard.
#
# The Moonshine chain of shader effects, which Lua calls as a function to
# draw a scene through the effects, answers call with the scene as a block
# (rule 12), and its effects, read as fields of the chain in Lua, are its
# methods of the same names, whose settings are writers.
#
# Lua numbers are all doubles, so where Lua divides, Ruby divides as
# Floats. A function that returns several values returns an Array.

module Main
end

require "simple_splash/init"
require "lib/shaders/init"
require "parallax"
require "lib/vector"
require "powerups"
require "colors"
require "text"
require "settings"
require "sound"
require "about"
require "options"
require "help"
require "levels_selector"
require "player_progress"
require "hi_scores"
require "powerups_manager"
require "gamestate"
require "debuffs"
require "math_utils"
require "glow_benchmark"
require "game"
require "music"
require "input"
require "display_config"
require "highscore_flow"
require "http_client"
require "update_checker"

module Main
  class << self
    attr_accessor :current_level_data
  end

  @score = nil
  @hi_score = 0
  @current_level_high_score = 0
  @current_level_data = nil

  @game_canvas = nil
  @splash_canvas = nil
  @effects = nil
  @splash = nil
  @is_splash_active = nil

  # Variables to handle initialization on Android
  @graphics_initialized = false
  @orientation_stabilized = false
  @orientation_check_frames = 0
  @last_width = 0
  @last_height = 0

  def self.set_window_mode(width, height)
    Lota::Window.set_mode(
      width,
      height,
      resizable: false,
      fullscreen: false,
      vsync: true,
      highdpi: true,
    )
  end
  private_class_method :set_window_mode

  def self.is_correct_orientation
    width = Lota::Graphics.width
    height = Lota::Graphics.height
    height > width # Portrait: height greater than width
  end
  private_class_method :is_correct_orientation

  # Function to initialize canvas and effects
  def self.initialize_graphics
    if @graphics_initialized
      # Clear previous canvases
      if @game_canvas
        @game_canvas.release
        @game_canvas = nil
      end
      if @splash_canvas
        @splash_canvas.release
        @splash_canvas = nil
      end
      @effects = nil if @effects
    end

    # Create canvas with the correct dimensions
    @game_canvas = Lota::Graphics::Canvas.new(Settings.window_width, Settings.window_height)
    @splash_canvas = Lota::Graphics::Canvas.new(Settings.window_width, Settings.window_height)

    @effects = Moonshine.chain(Moonshine.effects.glow)
      .chain(Moonshine.effects.fastgaussianblur)
      .chain(Moonshine.effects.scanlines)
      .chain(Moonshine.effects.crt)
      .resize(Settings.window_width, Settings.window_height)

    @effects.glow.min_luma = 0.1
    @effects.fastgaussianblur.sigma = 1
    @effects.scanlines.width = 4
    @effects.scanlines.opacity = 0.2
    @effects.scanlines.color = Colors.light_blue

    Main.apply_glow_setting
    Main.apply_blur_setting

    @graphics_initialized = true
  end
  private_class_method :initialize_graphics

  def self.apply_glow_setting
    return if !@effects || !@effects.glow

    @effects.glow.strength = if Settings.is_glow_enabled
      20
    else
      1
    end
  end

  def self.apply_blur_setting
    return unless @effects

    if Settings.is_blur_enabled
      @effects.enable("fastgaussianblur")
    else
      @effects.disable("fastgaussianblur")
    end
  end

  def self.init_game
    @score = 0
    GameState.set(GameState.is_attract_mode ? "attract" : "playing")
    HighscoreFlow.reset

    if Main.current_level_data
      @current_level_high_score = PlayerProgress.get_level_high_score(Main.current_level_data.id)
      Main.current_level_data.load
    else
      @current_level_high_score = 0
    end

    init_difficulty = Main.current_level_data ? Main.current_level_data.difficulty : 1
    Game.init(GameState.is_attract_mode, init_difficulty)

    Input.reset_just_pressed
    GameState.is_new_hi_score = false

    GameState.ignore_input_timer = if !GameState.is_attract_mode
      1
    else
      0
    end
  end

  def self.setup_dimensions
    # Calculate optimal resolution for current screen
    desktop_width, desktop_height = Lota::Window.desktop_dimensions

    if Settings.is_mobile
      saved_config = DisplayConfig.load

      if saved_config
        Settings.dpi_scale = saved_config.dpi_scale
        Settings.internal_height = saved_config.internal_height
        Settings.scale_factor = saved_config.scale_factor
        Settings.window_width = saved_config.pixel_width
        Settings.window_height = saved_config.pixel_height
      else
        # Calculate dimensions for the first time
        pixel_width = Lota::Graphics.width
        pixel_height = Lota::Graphics.height

        # Ensure we have portrait orientation (height > width)
        pixel_width, pixel_height = pixel_height, pixel_width if pixel_width > pixel_height

        # Calculate DPI scale factor and aspect ratio to adjust internal height
        Settings.dpi_scale = pixel_width.fdiv([desktop_width, desktop_height].min)
        aspect_ratio = pixel_height.fdiv(pixel_width)
        Settings.internal_height = (Settings.internal_width * aspect_ratio).floor
        # Calculate scale to fit the width perfectly
        Settings.scale_factor = pixel_width.fdiv(Settings.internal_width)
        Settings.window_width = pixel_width
        Settings.window_height = pixel_height

        DisplayConfig.save(DisplayConfig::Config.new(
          pixel_width:,
          pixel_height:,
          desktop_width:,
          desktop_height:,
          dpi_scale: Settings.dpi_scale,
          internal_height: Settings.internal_height,
          scale_factor: Settings.scale_factor,
        ))
      end
    else
      # Desktop
      scale_x = desktop_width.fdiv(Settings.internal_width).floor
      scale_y = desktop_height.fdiv(Settings.internal_height).floor
      Settings.scale_factor = [scale_x, scale_y].min
      Settings.window_width = Settings.internal_width * Settings.scale_factor
      Settings.window_height = Settings.internal_height * Settings.scale_factor
    end
    true
  end
  private_class_method :setup_dimensions

  # love.load.
  def self.load
    Lota::Window.title = "FLASH-BLIP"

    Settings.load

    GlowBenchmark.init
    GlowBenchmark.set_on_glow_disabled(Main.method(:apply_glow_setting))

    desktop_width, desktop_height = Lota::Window.desktop_dimensions

    if Settings.is_mobile
      # For mobiles, set portrait mode explicitly
      portrait_width = [desktop_width, desktop_height].min
      portrait_height = [desktop_width, desktop_height].max
      set_window_mode(portrait_width, portrait_height)

      # DO NOT initialize graphics yet on mobiles, will wait for the orientation to stabilize
      @orientation_stabilized = false
      @is_splash_active = false
      @last_width = Lota::Graphics.width
      @last_height = Lota::Graphics.height
    else
      # Desktop
      setup_dimensions
      set_window_mode(Settings.window_width, Settings.window_height)

      @splash = SimpleSplash.new(Settings.window_width, Settings.window_height)
      @is_splash_active = true
      @splash.on_done = lambda do
        @is_splash_active = false
        init_game
      end

      initialize_graphics

      GlowBenchmark.start if GlowBenchmark.is_benchmark_needed
    end

    Sound.load
    Music.play

    Sound.toggle_mute(!Settings.is_sfx_enabled)
    Music.toggle_mute(!Settings.is_music_enabled)
    Music.set_volume(Settings.is_music_volume)
    Sound.set_volume(Settings.is_sfx_volume)

    Parallax.load(nil, nil)
    About.load
    Options.load
    Help.load
    LevelsSelector.load
    PlayerProgress.load
    @hi_score = PlayerProgress.get_endless_high_score

    UpdateChecker.start

    return unless Settings.is_debug_enabled

    require "lib/overlayStats"
    OverlayStats.load
  end

  def self.end_game
    return if GameState.is("gameOver")

    if Main.current_level_data # is Arcade mode
      if @score > @current_level_high_score
        PlayerProgress.set_level_high_score(Main.current_level_data.id, @score)
        @current_level_high_score = @score
        GameState.is_new_hi_score = true
        GameState.hi_score_flash_visible = true
      end
    elsif !GameState.is_attract_mode # is Endless mode
      if @score > @hi_score
        @hi_score = @score
        PlayerProgress.set_endless_high_score(@score)
        GameState.is_new_hi_score = true
        GameState.hi_score_flash_visible = true
      end
    end

    PowerupsManager.clear_active_powerups
    Debuffs.clear_active_debuffs

    HighscoreFlow.prepare(@score, Main.current_level_data)

    GameState.set("gameOver")
    GameState.game_over_input_delay = 3.0
  end
  private_class_method :end_game

  # Lua's loop runs over the particles there were when it began, keeps
  # those still alive at the front, and clears the slots after them.
  def self.update_particles(_dt)
    write_index = 0
    count = Game.particles.size
    count.times do |read_index|
      p = Game.particles[read_index]
      p.pos.add(p.vel)
      p.life -= 0.4

      if p.life > 0
        Game.particles[write_index] = p
        write_index += 1
      end
    end

    Game.particles.slice!(write_index..) if write_index < Game.particles.size
  end
  private_class_method :update_particles

  def self.add_score(value)
    return if GameState.is_attract_mode

    multiplier = PowerupsManager.is_score_multiplier_active ? 4 : 1
    @score += (value * multiplier)
  end
  private_class_method :add_score

  def self.particle(position, count = nil, speed = nil, angle = nil, angle_width = nil, color = nil)
    count ||= 1
    count.times do
      particle_angle = angle + MathUtils.rnds(angle_width || 0)
      Game.particles << Game::Particle.new(
        pos: position.copy,
        vel: Vector.new(Math.cos(particle_angle) * speed, Math.sin(particle_angle) * speed),
        life: MathUtils.rnd(10, 20),
        color: color || Colors.periwinkle_mist,
      )
    end
  end

  def self.restart_game
    if GameState.is("gameOver") && (Game.game_over_line.nil? || Game.game_over_line.timer <= 0)
      init_game
      GameState.restart_delay_counter = 10
    end
  end

  def Lota.keypressed(key)
    Input.keypressed(key)
    OverlayStats.handle_keyboard(key) if Settings.is_debug_enabled
  end

  def Lota.wheelmoved(x, y)
    Input.wheelmoved(x, y)
  end

  def Lota.mousemoved(x, y, _dx, _dy, _istouch)
    Input.mousemove(x, y)
  end

  def Lota.mousepressed(x, y, button)
    Input.mousepressed(x, y, button)
  end

  def Lota.mousereleased(x, y, button)
    Input.mousereleased(x, y, button)
  end

  def Lota.touchpressed(id, x, y, dx, dy, pressure)
    Input.touchpressed(id, x, y, dx, dy, pressure)
  end

  def Lota.touchmoved(id, x, y, dx, dy, pressure)
    Input.touchmoved(id, x, y, dx, dy, pressure)
  end

  def Lota.touchreleased(id, x, y, dx, dy, pressure)
    Input.touchreleased(id, x, y, dx, dy, pressure)
  end

  def Lota.joystickpressed(joystick, button)
    Input.joystickpressed(joystick, button)
  end

  def Lota.gamepadpressed(joystick, button)
    Input.gamepadpressed(joystick, button)
  end

  def Lota.joystickadded(joystick)
    Input.joystickadded(joystick)
  end

  def Lota.joystickremoved(joystick)
    Input.joystickremoved(joystick)
  end

  def self.update_pings(dt)
    return if GameState.is_not("playing")

    Game.jump_pings.reverse_each do |ping|
      current_max_radius = PowerupsManager.get_current_max_radius
      ping.speed = PowerupsManager.is_phase_shift_active ? 15 : 10

      ping.radius += ping.speed * dt
      ping.radius = 0 if ping.radius >= current_max_radius # Reset radius for cyclic effect
    end
  end
  private_class_method :update_pings

  def self.win_level
    @current_level_high_score, @hi_score =
      Game.win_level(Main.current_level_data, @score, @current_level_high_score, @hi_score)

    HighscoreFlow.prepare(@score, Main.current_level_data)

    GameState.set("levelCompleted")
    GameState.level_completed_input_delay = 1.0
  end
  private_class_method :win_level

  def self.handle_successful_blip(blip_type)
    Game.handle_successful_blip(blip_type, Main.current_level_data)
  end
  private_class_method :handle_successful_blip

  # love.update.
  def self.update(dt)
    dt = [dt, 1 / 30.0].min

    Settings.update(dt)
    GlowBenchmark.update(dt)

    HttpClient.update
    Music.update(dt)

    HighscoreFlow.update(dt)

    if Settings.is_mobile && !@orientation_stabilized
      current_width = Lota::Graphics.width
      current_height = Lota::Graphics.height

      # Check if dimensions have changed
      if current_width != @last_width || current_height != @last_height
        @last_width = current_width
        @last_height = current_height
        @orientation_check_frames = 0
      else
        @orientation_check_frames += 1
      end

      if @orientation_check_frames >= 5 && is_correct_orientation
        @orientation_stabilized = true

        setup_dimensions

        Parallax.load(nil, nil)

        initialize_graphics

        GlowBenchmark.start if GlowBenchmark.is_benchmark_needed

        LevelsSelector.load

        @splash = SimpleSplash.new(Settings.window_width, Settings.window_height)
        @is_splash_active = true
        @splash.on_done = lambda do
          @is_splash_active = false
          init_game
        end
      end

      return # Do not process anything else until stabilized
    end

    if @is_splash_active
      @splash.update(dt)
      @splash.set_done if Music.is_ready
      return
    end

    if GameState.is("virtual_keyboard")
      require "virtual_keyboard"
      VirtualKeyboard.update(dt)
      return
    end

    return if GameState.is_paused

    if GameState.is("levels")
      LevelsSelector.update(dt)
      return
    end

    HiScores.update(dt) if GameState.is("hi_scores")

    GameState.update(dt)

    Parallax.update(dt, GameState.current)
    PowerupsManager.update(dt, GameState.current)
    Debuffs.update(dt, GameState.current)
    Powerups.update_pings(dt)
    update_pings(dt)
    Input.update(dt)

    Game.update_effects(method(:win_level))

    if GameState.is("gameOver")
      if Input.is_game_over_continue &&
          (Game.game_over_line.nil? || Game.game_over_line.timer <= 0) &&
          GameState.game_over_input_delay <= 0 &&
          !HighscoreFlow.is_waiting

        HighscoreFlow.request_proceed("gameOver", proc do
          init_game
          GameState.restart_delay_counter = 10
        end)
      end
      init_game if GameState.is_attract_mode && (Game.game_over_line.nil? || Game.game_over_line.timer <= 0)
      return
    end

    if GameState.is("levelCompleted")
      if GameState.level_completed_input_delay <= 0 &&
          Input.is_level_completed_continue &&
          !HighscoreFlow.is_waiting

        HighscoreFlow.request_proceed("levelCompleted", proc do
          Game.clear_game_objects
          GameState.set("levels")
        end)
      end
      return
    end

    return if GameState.is("help")

    return if GameState.restart_delay_counter > 0

    Input.simulate_attract_input(Game.player_circle) if GameState.is_attract_mode

    obstacles = Game.update(dt, PowerupsManager, method(:end_game), method(:add_score))
    Game.player_circle = Game.get_player_circle
    Game.circles = Game.get_circles

    if Game.player_circle
      did_teleport = false
      if PowerupsManager.is_phase_shift_active &&
          Game.player_circle.next &&
          GameState.ignore_input_timer <= 0 &&
          Powerups.is_ping_connected(Game.jump_pings)

        handle_successful_blip("phase_shift")
        did_teleport = true
      end

      if PowerupsManager.is_bolt_active &&
          !did_teleport &&
          Game.player_circle.next &&
          GameState.ignore_input_timer <= 0 &&
          Powerups.check_lightning_collision(Game.player_circle)

        handle_successful_blip("bolt")
        did_teleport = true
      end

      if !did_teleport &&
          Input.is_just_pressed &&
          Game.player_circle.next &&
          GameState.ignore_input_timer <= 0

        was_invulnerable = PowerupsManager.is_invulnerable
        blip_collected_powerup, collected_star = PowerupsManager.handle_blip_collision(Game.player_circle)
        Debuffs.check_blip_collision(Game.player_circle, Game.player_circle.next)
        collision = false
        unless PowerupsManager.is_invulnerable
          (obstacles || []).each do |obstacle|
            next unless MathUtils.is_line_rotated_rect_collision(
              Game.player_circle.position,
              Game.player_circle.next.position,
              obstacle.center,
              obstacle.width,
              obstacle.height,
              obstacle.angle,
            )

            collision = true
            break
          end
        end

        if collision
          unless GameState.is_attract_mode
            Sound.play("explosion")
            end_game
            Game.game_over_line = Game::Line.new(
              p1: Game.player_circle.position.copy,
              p2: Game.player_circle.next.position.copy,
              timer: 60,
              width: 3,
            )
          end
        else
          handle_successful_blip("manual")
          # If a power-up was collected on the blip, invulnerability is deactivated upon arriving at the destination only if it wasn't active previously.
          if blip_collected_powerup && !collected_star && !was_invulnerable
            PowerupsManager.is_invulnerable = false
          end
        end
      end
    end

    Game.update_jump_pings(Colors.periwinkle_mist)

    PowerupsManager.handle_player_collision(Game.player_circle)
    Debuffs.check_collisions(Game.player_circle)

    update_particles(dt)

    Input.reset_just_pressed

    return unless Settings.is_debug_enabled

    OverlayStats.update(dt)
    fps = Lota::Timer.fps
    return unless fps < 58

    puts(
      format(
        "FPS dropped to %.2f | dt: %.4f | State: %s | Particles: %d | Circles: %d | Blips: %d | Time: %.2f",
        fps,
        dt,
        GameState.current,
        Game.particles.size,
        Game.circles.size,
        Game.blip_counter.value,
        Lota::Timer.time,
      ),
    )
  end

  # love.draw.
  def self.draw
    if Settings.is_mobile && !@orientation_stabilized
      Lota::Graphics.clear(Colors.murky_blue)
      Lota::Graphics.color = [1, 1, 1, 1]
      return
    end

    if @is_splash_active
      Lota::Graphics.canvas = @splash_canvas
      Lota::Graphics.clear
      @splash.draw
      Lota::Graphics.canvas = nil

      @effects.call do
        Lota::Graphics.color = [1, 1, 1, 1]
        Lota::Graphics.draw(@splash_canvas, 0, 0)
      end
      return
    end

    Lota::Graphics.canvas = @game_canvas
    Lota::Graphics.clear
    Parallax.draw

    Lota::Graphics.push do
      Lota::Graphics.scale(Settings.scale_factor, Settings.scale_factor)

      Game.particles.each do |p|
        alpha = [0, p.life / 20.0].max
        Lota::Graphics.color = if PowerupsManager.is_invulnerable
          [Colors.yellow[0], Colors.yellow[1], Colors.yellow[2], alpha]
        else
          [p.color[0], p.color[1], p.color[2], alpha]
        end
        Lota::Graphics.circle(:fill, p.pos.x, p.pos.y, 0.5)
      end

      # Draw circles and their rotating obstacles
      Game.circles.each do |circle|
        is_final_blip = Main.current_level_data &&
          Main.current_level_data.win_condition.type == "blips" &&
          Game.blip_counter.value == Main.current_level_data.win_condition.value - 1 &&
          circle.equal?(Game.player_circle.next)

        if is_final_blip
          Lota::Graphics.color = Main.current_level_data.win_condition.final_blip_color
        elsif PowerupsManager.is_phase_shift_active &&
            (circle.equal?(Game.player_circle) || (Game.player_circle && circle.equal?(Game.player_circle.next)))

          Lota::Graphics.color = Colors.emerald_shade
        elsif PowerupsManager.is_invulnerable &&
            (circle.equal?(Game.player_circle) || (Game.player_circle && circle.equal?(Game.player_circle.next)))

          Lota::Graphics.color = Colors.yellow
        elsif circle.equal?(Game.player_circle) || (Game.player_circle && circle.equal?(Game.player_circle.next))
          Lota::Graphics.color = if PowerupsManager.is_slowed
            Colors.light_blue_glow
          else
            Colors.periwinkle_mist
          end
        elsif circle.is_passed
          Lota::Graphics.color = Colors.rusty_cedar_transparent
        else
          Lota::Graphics.color = Colors.rusty_cedar
        end
        is_glitching = Debuffs.glitch_timer && Debuffs.glitch_timer > 0
        if !((PowerupsManager.is_invulnerable || is_glitching) && circle.equal?(Game.player_circle))
          if is_final_blip
            # Draw hexagonal shape for final blip
            x = circle.position.x
            y = circle.position.y
            size = 3.5
            Lota::Graphics.polygon(
              :fill,
              x,
              y - size,
              x + (size * 0.866),
              y - (size * 0.5),
              x + (size * 0.866),
              y + (size * 0.5),
              x,
              y + size,
              x - (size * 0.866),
              y + (size * 0.5),
              x - (size * 0.866),
              y - (size * 0.5),
            )
          else
            Lota::Graphics.circle(:fill, circle.position.x, circle.position.y, 1.5)
          end
        end

        # Obstacles
        Lota::Graphics.color = if PowerupsManager.is_slowed
          Colors.light_blue_glow
        else
          Colors.safety_orange
        end
        1.upto(circle.obstacle_count) do |i|
          obstacle_angle = circle.angle + ((i * Math::PI * 2) / circle.obstacle_count)
          rect_center = Vector.new(circle.position.x, circle.position.y).add_with_angle(obstacle_angle, circle.radius)

          Lota::Graphics.push do
            Lota::Graphics.translate(rect_center.x, rect_center.y)
            Lota::Graphics.rotate(obstacle_angle + (Math::PI / 2)) # The obstacles are perpendicular to radius.
            Lota::Graphics.rectangle(:fill, -circle.obstacle_length / 2.0, -1.5, circle.obstacle_length, 3, 1.2, 1.2)
          end
        end
      end

      # Draw the player (larger square circle).
      if Game.player_circle
        px = Game.player_circle.position.x - 2.5
        py = Game.player_circle.position.y - 2.5
        pw = 5
        ph = 5

        if Debuffs.is_emp_active
          Lota::Graphics.color = Colors.crimson
          if Debuffs.glitch_timer && Debuffs.glitch_timer > 0
            px += Lota::Math.random(-3, 3)
            py += Lota::Math.random(-1, 1)
            pw += Lota::Math.random(-2, 3)
            ph += Lota::Math.random(-2, 2)

            # Draw a thin horizontal glitch slice
            if Lota::Math.random > 0.4
              Lota::Graphics.color = [Colors.crimson[0], Colors.crimson[1], Colors.crimson[2], 0.6]
              Lota::Graphics.rectangle(
                :fill,
                Game.player_circle.position.x - 5 + Lota::Math.random(-6, 6),
                Game.player_circle.position.y - 1.5 + Lota::Math.random(-3, 3),
                10,
                1,
                0,
                0,
              )
              Lota::Graphics.color = Colors.crimson
            end
          end
        elsif PowerupsManager.is_invulnerable
          alpha_pulse = 0.8
          unless GameState.is_paused
            # Invulnerability visual effect (blinking) pulses from 0.2 to 1.0 (20% to 100% opacity)
            alpha_pulse = 0.6 + (Math.sin(Lota::Timer.time * 20) * 0.4)
          end
          Lota::Graphics.color = [Colors.yellow[0], Colors.yellow[1], Colors.yellow[2], alpha_pulse]
        elsif PowerupsManager.is_phase_shift_active
          Lota::Graphics.color = Colors.emerald_shade
        elsif PowerupsManager.is_slowed
          Lota::Graphics.color = Colors.light_blue_glow
        else
          Lota::Graphics.color = Colors.periwinkle_mist
        end
        Lota::Graphics.rectangle(:fill, px, py, pw, ph, 1.6, 1.6)
        Game.draw_blip_chevrons
      end

      PowerupsManager.draw_spawn_rate_indicator if PowerupsManager.is_spawn_rate_boost_active

      Game.draw_game_over_line
      Game.draw_flash_line(Main.current_level_data)

      Powerups.draw(GameState.current)
      Debuffs.draw(GameState.current)

      if PowerupsManager.is_bolt_active && GameState.is_not("gameOver") && GameState.is_not("levelCompleted")
        Powerups.draw_lightning
      end

      if GameState.is_not("gameOver")
        Powerups.draw_pings
        PowerupsManager.draw_next_jump_ping_indicator(Game.jump_pings, Game.blip_counter, Main.current_level_data)
      end
    end

    # Draw user interface (UI).
    Lota::Graphics.push do
      Lota::Graphics.origin # Reset any previous scale transformations
      display_hi_score = @hi_score
      display_hi_score = @current_level_high_score if Main.current_level_data

      if !GameState.is_attract_mode && !GameState.is("levels")
        Text.draw_score(@score, display_hi_score, PowerupsManager.is_score_multiplier_active)

        if Main.current_level_data && Main.current_level_data.win_condition.type == "blips"
          Text.draw_level_progress(
            Game.blip_counter.value,
            Main.current_level_data.win_condition.value,
            Main.current_level_data.win_condition.final_blip_color,
          )
        end
      end

      if GameState.is("attract")
        Text.draw_attract(Input.get_menu_items, Input.get_selected_menu_item)
        UpdateChecker.draw
      end

      if GameState.is("gameOver") && !GameState.is_attract_mode && (!Game.game_over_line || Game.game_over_line.timer <= 0)
        Text.draw_game_over(display_hi_score, GameState.is_new_hi_score, GameState.hi_score_flash_visible)
      end

      if GameState.is("levelCompleted")
        if GameState.all_levels_completed
          Text.draw_all_levels_completed(display_hi_score, GameState.is_new_hi_score, GameState.hi_score_flash_visible)
        else
          Text.draw_level_completed(display_hi_score, GameState.is_new_hi_score, GameState.hi_score_flash_visible)
        end
      end

      if GameState.is_paused
        level_id = Main.current_level_data&.id
        Text.draw_pause_menu(Input.get_pause_menu_items, Input.get_selected_pause_menu_item, level_id)
      end
    end
    Lota::Graphics.canvas = nil

    draw_game_and_ui = proc do
      Lota::Graphics.color = [1, 1, 1, 1]
      Lota::Graphics.draw(@game_canvas, 0, 0)
      if GameState.is("help")
        Help.draw
      elsif GameState.is("about")
        About.draw
      elsif GameState.is("options")
        Options.draw
      elsif GameState.is("hi_scores")
        HiScores.draw
      elsif GameState.is("levels")
        LevelsSelector.draw
      elsif GameState.is("virtual_keyboard")
        require "virtual_keyboard"
        VirtualKeyboard.draw
      end
    end

    # Draw canvas to screen applying shader effects
    @effects.call(&draw_game_and_ui)

    GlowBenchmark.draw

    OverlayStats.draw if Settings.is_debug_enabled
  end
end

def Lota.load
  Main.load
end

def Lota.update(dt)
  Main.update(dt)
end

def Lota.draw
  Main.draw
end
# SPDX-SnippetEnd
