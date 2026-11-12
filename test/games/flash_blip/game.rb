# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's game.lua
# (test/fixtures/flash_blip/game/game.lua, lines 1-596), by the rules of
# doc/contributors/design/translation.md: love.graphics.setColor becomes
# the writer Lota::Graphics.color= (rules 5 and 6), the draw mode "fill" a
# symbol (rule 9), love.math.random Lota::Math.random (rule 1), and each
# push ... pop paired in one function the block form of push (rule 11).
#
# The Game table becomes the module Game, each of its fields a reader and
# writer of the same name, and each of its functions a method of the
# module. Its local functions are private methods of it, and its locals
# instance variables of the module; the three locals that share a name with
# a field of Game, circles, particles, and player_circle, which Lua keeps
# apart from Game.circles, Game.particles, and Game.player_circle, are
# @local_circles, @local_particles, and @local_player_circle. The global
# function particle, which main.lua defines, is Main.particle.
#
# The tables game.lua and main.lua make with fixed fields are records whose
# fields read and write as Lua's do. A circle is a Circle, an object of its
# own compared by identity, as Lua compares tables and as
# powerups_manager.lua keys a table by circle; the others, compared by
# nothing, are Structs: a Particle, a JumpPing, a Line (Game.flash_line and
# Game.game_over_line), an Obstacle, and the BlipCounter.
#
# Game.update takes end_game and add_score, and Game.update_effects
# win_level_fn, as functions, which here are anything that answers call.
# A function that returns several values returns an Array. Lua numbers are
# all doubles, so where Lua divides, Ruby divides as Floats, and ^ is ** of
# a Float.

require "lib/vector"
require "settings"
require "powerups"
require "sound"
require "colors"
require "math_utils"
require "gamestate"
require "powerups_manager"
require "levels_selector"
require "debuffs"
require "player_progress"
require "input_recorder"

module Game
  # A circle the player blips between, with its rotating obstacles.
  class Circle
    attr_accessor :position, :radius, :obstacle_count, :angle, :angular_velocity, :obstacle_length, :next,
      :is_passed

    def initialize(
      position:, radius:, obstacle_count:, angle:, angular_velocity:, obstacle_length:, next_circle:, is_passed:
    )
      @position = position
      @radius = radius
      @obstacle_count = obstacle_count
      @angle = angle
      @angular_velocity = angular_velocity
      @obstacle_length = obstacle_length
      @next = next_circle
      @is_passed = is_passed
    end
  end

  # A particle of Game.particles.
  Particle = Struct.new(:pos, :vel, :life, :color, keyword_init: true)

  # A ping of Game.jump_pings.
  JumpPing = Struct.new(:circle, :radius, :max_radius, :speed, :life, :color, keyword_init: true)

  # Game.flash_line or Game.game_over_line; only the latter has a width.
  Line = Struct.new(:p1, :p2, :timer, :width, keyword_init: true)

  # An obstacle Game.update returns.
  Obstacle = Struct.new(:center, :width, :height, :angle, keyword_init: true)

  # Game.blip_counter.
  BlipCounter = Struct.new(:value, keyword_init: true)

  class << self
    attr_accessor :jump_pings, :circles, :player_circle, :particles, :blip_counter, :flash_line,
      :game_over_line, :last_next_circle, :pending_win_level, :pending_win_level_delay, :time
  end

  @jump_pings = []
  @circles = []
  @player_circle = nil
  @particles = []
  @blip_counter = BlipCounter.new(value: 0)
  @flash_line = nil
  @game_over_line = nil
  @last_next_circle = nil
  @pending_win_level = false
  @pending_win_level_delay = 0
  @time = 0

  @local_circles = nil
  @local_particles = nil
  @circle_add_dist = nil
  @last_circle = nil
  @local_player_circle = nil
  @ticks = nil
  @difficulty = nil
  @base_difficulty = nil
  @base_scroll_speed = 0.08
  @is_attract_mode = false
  @min_circle_dist = Settings.internal_height / 4.0
  PERP_WAVE_INTENSITY = 0.3 # 0 off to 1.0 normal

  def self.vec(x, y)
    Vector.new(x, y)
  end
  private_class_method :vec

  def self.remove(tbl)
    i = tbl.size
    while i >= 1
      tbl.delete_at(i - 1) if yield(tbl[i - 1])
      i -= 1
    end
  end
  private_class_method :remove

  def self.init(attract_mode_active, initial_difficulty = nil)
    @local_circles = []
    @local_particles = []
    @circle_add_dist = 0
    @last_circle = nil
    @local_player_circle = nil
    @ticks = 0
    @difficulty = initial_difficulty || 1
    @base_difficulty = initial_difficulty || 1
    @is_attract_mode = attract_mode_active

    Game.circles = @local_circles
    Game.particles = @local_particles
    Game.player_circle = nil
    Game.jump_pings = []
    Game.blip_counter = BlipCounter.new(value: 0)
    Game.flash_line = nil
    Game.game_over_line = nil
    Game.last_next_circle = nil
    Game.pending_win_level = false
    Game.pending_win_level_delay = 0
    Game.time = 0

    PowerupsManager.init(Game.circles, @is_attract_mode)
    Debuffs.init
    Powerups.reset

    if !@is_attract_mode
      seed = defined?(Main) ? Main.current_level_data&.seed : nil
      InputRecorder.start(seed)
    else
      InputRecorder.stop
    end
  end

  def self.get_circles
    @local_circles
  end

  def self.get_particles
    @local_particles
  end

  def self.get_player_circle
    @local_player_circle
  end

  def self.set_player_circle(circle)
    @local_player_circle = circle
    Game.player_circle = circle
    Game.player_circle = circle
  end

  def self.add_circle(is_slowed)
    radius = MathUtils.rnd(20, 30)

    y_pos = -radius
    y_pos = [y_pos, @local_player_circle.position.y - @min_circle_dist].min if @local_player_circle

    new_circle = Circle.new(
      position: vec(MathUtils.rnd(15, Settings.internal_width - 15), y_pos),
      radius:,
      obstacle_count: MathUtils.rndi(1, 3),
      angle: MathUtils.rnd(Math::PI * 2),
      angular_velocity: MathUtils.rnds(0.005, 0.015) * @difficulty,
      obstacle_length: MathUtils.rnd(15, 25),
      next_circle: nil,
      is_passed: false,
    )

    if is_slowed
      new_circle.angular_velocity = MathUtils.rnds(0.005, 0.015)
      new_circle.obstacle_length = new_circle.obstacle_length * 0.5
    end

    @last_circle.next = new_circle unless @last_circle.nil?
    @local_player_circle = new_circle if @local_player_circle.nil?
    @last_circle = new_circle
    @local_circles << new_circle
  end
  private_class_method :add_circle

  def self.update_difficulty
    ticks_per_unit = 3600
    exponent = 1.25
    scale_factor = 1.5

    time_units = @ticks.fdiv(ticks_per_unit)

    @difficulty = @base_difficulty + ((time_units ** exponent) * scale_factor)
  end
  private_class_method :update_difficulty

  def self.update(dt, powerups_manager, end_game, add_score)
    Game.time = (Game.time || 0) + dt
    @ticks += 1
    InputRecorder.tick
    update_difficulty

    add_circle(powerups_manager.is_slowed) if @ticks == 1

    if @circle_add_dist <= 0
      add_circle(powerups_manager.is_slowed)
      @circle_add_dist += MathUtils.rnd(Settings.internal_height * 0.25, Settings.internal_height * 0.45)
    end

    base_speed_for_score = @difficulty * @base_scroll_speed
    if @local_player_circle
      player_y = @local_player_circle.position.y
      if player_y < (Settings.internal_height / 2.0)
        base_speed_for_score += ((Settings.internal_height / 2.0) - player_y) * 0.02
      end
    end

    scroll_speed = base_speed_for_score

    if powerups_manager.is_slowed
      player_y = @local_player_circle ? @local_player_circle.position.y : 0
      if player_y < (Settings.internal_height * 0.2)
        scroll_speed = @base_scroll_speed + (((Settings.internal_height / 2.0) - player_y) * 0.02)
      elsif player_y > (Settings.internal_height * 0.5) && player_y < (Settings.internal_height * 0.8)
        scroll_speed = @base_scroll_speed
      elsif player_y >= (Settings.internal_height * 0.8)
        scroll_speed = @base_scroll_speed * 0.10
      end
    end

    @circle_add_dist -= scroll_speed
    add_score.call(base_speed_for_score)

    if @local_player_circle && @local_player_circle.position.y > Settings.internal_height - 1
      unless @is_attract_mode
        if powerups_manager.is_bolt_active &&
            @local_player_circle.next &&
            Powerups.check_lightning_collision(@local_player_circle)

          Sound.play("teleport")
          Main.particle(@local_player_circle.position, 20, 3, 0, Math::PI * 2, Colors.yellow)
          Main.particle(@local_player_circle.next.position, 20, 3, 0, Math::PI * 2, Colors.yellow)
          @local_player_circle.is_passed = true
          @local_player_circle = @local_player_circle.next
          return
        end
        Sound.play("explosion")
      end
      end_game.call
      return
    end

    if powerups_manager.is_bolt_active &&
        @local_player_circle&.next &&
        Powerups.check_lightning_collision(@local_player_circle)

      Sound.play("teleport") unless @is_attract_mode
      Main.particle(@local_player_circle.position, 20, 3, 0, Math::PI * 2, Colors.yellow)
      Main.particle(@local_player_circle.next.position, 20, 3, 0, Math::PI * 2, Colors.yellow)
      @local_player_circle.is_passed = true
      @local_player_circle = @local_player_circle.next
    end

    obstacles = []
    remove(@local_circles) do |circle|
      circle.position.y = circle.position.y + scroll_speed
      next true if circle.position.y > Settings.internal_height + circle.radius

      circle.angle = circle.angle + circle.angular_velocity

      1.upto(circle.obstacle_count) do |i|
        obstacle_angle = circle.angle + ((i * Math::PI * 2) / circle.obstacle_count)
        rect_center = vec(circle.position.x, circle.position.y).add_with_angle(obstacle_angle, circle.radius)
        obstacles << Obstacle.new(
          center: rect_center,
          width: circle.obstacle_length,
          height: 3,
          angle: obstacle_angle + (Math::PI / 2),
        )
      end
      false
    end

    remove(@local_particles) do |p|
      p.pos.add(p.vel)
      p.life -= 0.4
      p.life <= 0
    end

    obstacles
  end

  def self.get_blip_color(current_level_data, blip_counter)
    if current_level_data &&
        current_level_data.win_condition.type == "blips" &&
        blip_counter.value == current_level_data.win_condition.value - 1

      current_level_data.win_condition.final_blip_color
    else
      PowerupsManager.get_ping_color
    end
  end
  private_class_method :get_blip_color

  # Lua asks whether level_data_or_params is a table with a
  # current_level_data field; a LevelData is a table without one, so here
  # it is anything that answers current_level_data with something.
  def self.handle_successful_blip(blip_type, level_data_or_params)
    blip_type ||= "manual" # "manual", "phase_shift", "bolt"
    current_level_data = if level_data_or_params.respond_to?(:current_level_data) &&
        !level_data_or_params.current_level_data.nil?

      level_data_or_params.current_level_data
    else
      level_data_or_params
    end

    InputRecorder.record(InputRecorder.input.blip) unless @is_attract_mode

    return if !@local_player_circle || !@local_player_circle.next

    blip_color = get_blip_color(current_level_data, Game.blip_counter)

    if blip_type == "phase_shift" || blip_type == "bolt"
      Sound.play("teleport") unless GameState.is_attract_mode
      Main.particle(@local_player_circle.position, 20, 3, 0, Math::PI * 2, blip_color)
      Main.particle(@local_player_circle.next.position, 20, 3, 0, Math::PI * 2, blip_color)
    else # "manual"
      Sound.play("blip") unless GameState.is_attract_mode
      current_pos = @local_player_circle.position.copy
      # Divide the distance between player and next point into 10 equal pieces
      step_vector = Vector.new(@local_player_circle.next.position.x, @local_player_circle.next.position.y)
        .sub(@local_player_circle.position).div(10)
      particle_angle = step_vector.angle
      10.times do
        Main.particle(current_pos, 4, 2, particle_angle + Math::PI, 0.5, blip_color)
        current_pos.add(step_vector)
      end
    end

    if blip_type != "bolt"
      Game.flash_line = Line.new(
        p1: @local_player_circle.position.copy,
        p2: @local_player_circle.next.position.copy,
        timer: 2,
      )
    end

    @local_player_circle.is_passed = true
    Game.set_player_circle(@local_player_circle.next)
    Game.blip_counter.value = Game.blip_counter.value + 1

    return unless current_level_data &&
      current_level_data.win_condition.type == "blips" &&
      Game.blip_counter.value >= current_level_data.win_condition.value

    if blip_type == "bolt"
      Game.pending_win_level_delay = 2
    else
      Game.pending_win_level = true
    end
  end

  def self.update_effects(win_level_fn)
    if Game.flash_line
      if Game.flash_line.timer > 0
        Game.flash_line.timer = Game.flash_line.timer - 1
      else
        Game.flash_line = nil
        Game.flash_line = nil
        if Game.pending_win_level
          Game.pending_win_level = false
          win_level_fn&.call
        end
      end
    end

    if Game.pending_win_level_delay > 0
      Game.pending_win_level_delay = Game.pending_win_level_delay - 1
      win_level_fn.call if Game.pending_win_level_delay <= 0 && win_level_fn
    end

    return unless Game.game_over_line && Game.game_over_line.timer > 0

    Game.game_over_line.timer = Game.game_over_line.timer - 1
  end

  def self.update_jump_pings(color)
    if @local_player_circle&.next && !@local_player_circle.next.equal?(Game.last_next_circle)
      Game.jump_pings = [
        JumpPing.new(
          circle: @local_player_circle.next,
          radius: 0,
          max_radius: 12,
          speed: 10,
          life: 1,
          color: color || Colors.periwinkle_mist,
        ),
      ]
      Game.last_next_circle = @local_player_circle.next
    elsif !@local_player_circle || !@local_player_circle.next
      Game.last_next_circle = nil
      Game.jump_pings = []
    end
  end

  def self.draw_game_over_line
    return unless Game.game_over_line

    Lota::Graphics.color = if PowerupsManager.is_phase_shift_active
      Colors.emerald_shade
    elsif PowerupsManager.is_slowed
      Colors.light_blue_glow
    else
      Colors.periwinkle_mist
    end

    line = Game.game_over_line
    angle = Vector.new(line.p2.x, line.p2.y).sub(Vector.new(line.p1.x, line.p1.y)).angle
    length = line.p1.distance(line.p2) + 2
    width = line.width || 2

    Lota::Graphics.push do
      Lota::Graphics.translate(line.p1.x, line.p1.y)
      Lota::Graphics.rotate(angle)
      Lota::Graphics.rectangle(:fill, 0, -width / 2.0, length, width, width / 2.0, width / 2.0)
    end
  end

  def self.draw_flash_line(current_level_data)
    return unless Game.flash_line

    line = Game.flash_line
    dist = line.p1.distance(line.p2)
    step_vector = Vector.new(line.p2.x, line.p2.y).sub(line.p1).normalize
    current_pos = line.p1.copy

    # Lua's for i = 0, dist, 3: i counts up by 3 while it is at most dist.
    i = 0
    while i <= dist
      alpha = i.fdiv(dist)
      if Debuffs.is_emp_active
        Lota::Graphics.color = [Colors.crimson[0], Colors.crimson[1], Colors.crimson[2], alpha]
      elsif current_level_data &&
          current_level_data.win_condition.type == "blips" &&
          Game.blip_counter.value >= current_level_data.win_condition.value

        Lota::Graphics.color = [
          current_level_data.win_condition.final_blip_color[0],
          current_level_data.win_condition.final_blip_color[1],
          current_level_data.win_condition.final_blip_color[2],
          alpha,
        ]
      elsif PowerupsManager.is_invulnerable
        Lota::Graphics.color = [Colors.yellow[0], Colors.yellow[1], Colors.yellow[2], alpha]
      elsif PowerupsManager.is_phase_shift_active
        Lota::Graphics.color = [Colors.emerald_shade[0], Colors.emerald_shade[1], Colors.emerald_shade[2], alpha]
      elsif PowerupsManager.is_slowed
        Lota::Graphics.color = [Colors.cyan_glow[0], Colors.cyan_glow[1], Colors.cyan_glow[2], alpha]
      else
        Lota::Graphics.color = [Colors.periwinkle_mist[0], Colors.periwinkle_mist[1], Colors.periwinkle_mist[2], alpha]
      end
      Lota::Graphics.rectangle(:fill, current_pos.x - 2, current_pos.y - 2, 4, 4, 1.6, 1.6)
      current_pos.add(step_vector.copy.mul(3))
      i += 3
    end
  end

  def self.win_level(current_level_data, score, current_level_high_score, hi_score)
    GameState.set("levelCompleted")
    GameState.level_completed_input_delay = 1.5
    PowerupsManager.clear_active_powerups
    if current_level_data # Arcade mode
      if score > current_level_high_score
        PlayerProgress.set_level_high_score(current_level_data.id, score)
        current_level_high_score = score
        GameState.is_new_hi_score = true
        GameState.hi_score_flash_visible = true
      end
    elsif score > hi_score
      hi_score = score
      GameState.is_new_hi_score = true
      GameState.hi_score_flash_visible = true
    end
    current_level_index = nil
    LevelsSelector.get_level_points.each_with_index do |level, index|
      if current_level_data && level.label == current_level_data.id
        current_level_index = index + 1
        break
      end
    end
    if current_level_index && current_level_index < LevelsSelector.get_level_points.size
      # Lua's index current_level_index + 1, counting from 0.
      next_level = LevelsSelector.get_level_points[current_level_index]
      PlayerProgress.unlock_level(next_level.label)
    end
    if current_level_index
      GameState.all_levels_completed = (current_level_index == LevelsSelector.get_level_points.size)
    end
    PlayerProgress.save
    [current_level_high_score, hi_score]
  end

  def self.get_player_color
    if Debuffs.is_emp_active
      color = Colors.crimson
      [color[0], color[1], color[2], color[3] || 1.0]
    elsif PowerupsManager.is_invulnerable
      alpha_pulse = 0.8
      alpha_pulse = 0.6 + (Math.sin((Game.time || 0) * 20) * 0.4) unless GameState.is_paused
      color = Colors.yellow
      [color[0], color[1], color[2], alpha_pulse]
    elsif PowerupsManager.is_phase_shift_active
      color = Colors.emerald_shade
      [color[0], color[1], color[2], color[3] || 1.0]
    elsif PowerupsManager.is_slowed
      color = Colors.light_blue_glow
      [color[0], color[1], color[2], color[3] || 1.0]
    else
      color = Colors.periwinkle_mist
      [color[0], color[1], color[2], color[3] || 1.0]
    end
  end

  def self.draw_blip_chevrons
    return if !@local_player_circle || !@local_player_circle.next

    return if GameState.is("gameOver") || GameState.is("levelCompleted")

    p1 = @local_player_circle.position
    p2 = @local_player_circle.next.position

    dist = MathUtils.distance(p1, p2)
    return if dist < 0.001

    dir = p2.sub(p1)
    dx = dir.x
    dy = dir.y
    angle = dir.angle
    r, g, b = Game.get_player_color

    num_chevrons = 5
    start_offset = 6.5
    max_span = [dist * 0.45, 24].min
    spacing = [3.2, (max_span - start_offset) / (num_chevrons - 1)].max

    time = Game.time || 0

    # last 2 seconds to warn the player
    is_warning = PowerupsManager.is_invulnerable && PowerupsManager.invulnerability_timer <= 2

    is_glitching = !GameState.is_paused &&
      Debuffs.is_emp_active &&
      Debuffs.glitch_timer &&
      Debuffs.glitch_timer > 0

    1.upto(num_chevrons) do |i|
      t_grad = (i - 1).fdiv(num_chevrons - 1)
      grad_scale = 1.0 - (t_grad * 0.62)

      perp_wave = Math.sin((time * 7.0) - (i * 0.85)) * 1.1 * PERP_WAVE_INTENSITY
      scale_wave = 1.0 + (0.16 * Math.sin((time * 8.0) - (i * 0.9)))
      opacity_wave = 0.55 + (0.45 * Math.sin((time * 9.0) - (i * 0.85)))
      chevron_alpha = (1 * opacity_wave).clamp(0.15, 1.0)

      if is_warning # visual feedback so the player knows the invuln powerup is ending
        warn_t = 0.5 + (0.5 * Math.sin((time * 26) - (i * 1.1)))
        c = Colors.lerp(Colors.yellow, Colors.periwinkle_mist, 1 - warn_t)
        r = c[0]
        g = c[1]
        b = c[2]
        perp_wave *= 1.8
        scale_wave = 1.0 + (0.35 * Math.sin((time * 20) - (i * 1.1)))
        chevron_alpha = [0.6, chevron_alpha].max
      end

      base_w = 3.6
      base_h = 4.2
      width = base_w * grad_scale * scale_wave
      height = base_h * grad_scale * scale_wave

      chevron_offset = start_offset + ((i - 1) * spacing)
      cx = p1.x + ((dx / dist) * chevron_offset)
      cy = p1.y + ((dy / dist) * chevron_offset)

      cx += (-dy / dist) * perp_wave
      cy += (dx / dist) * perp_wave

      if is_glitching && Lota::Math.random > 0.3
        cx += Lota::Math.random(-1.5, 1.5)
        cy += Lota::Math.random(-1.0, 1.0)
      end

      Lota::Graphics.push do
        Lota::Graphics.translate(cx, cy)
        Lota::Graphics.rotate(angle)

        Lota::Graphics.color = [r, g, b, chevron_alpha]
        Lota::Graphics.polygon(
          :fill,
          width * 0.55,
          0,
          -width * 0.45,
          -height * 0.5,
          -width * 0.15,
          0,
          -width * 0.45,
          height * 0.5,
        )
      end
    end
  end

  def self.clear_game_objects
    Game.init(GameState.is_attract_mode)
  end
end
# SPDX-SnippetEnd
