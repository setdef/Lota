# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's powerups_manager.lua
# (test/fixtures/flash_blip/game/powerups_manager.lua, lines 1-357), by the
# rules of doc/contributors/design/translation.md: setColor and
# setLineWidth become writers (rules 5 and 6), "fill" and "line" symbols
# (rule 9), and love.timer.getTime Lota::Timer.time (rule 3). The module's
# data fields are its accessors and its Lua locals instance variables. Lua
# reaches Debuffs through a table whose metatable requires debuffs on first
# use; here the private method debuffs requires it when it is called, so
# that debuffs, which draws a random number as it loads, loads no earlier
# than in Lua. The tables Lua keys by circle become Hashes that compare
# keys by identity, as Lua compares tables. handle_blip_collision returns
# Lua's two results as an Array of two, and reads the six of
# Powerups.check_blip_collision and Powerups.check_collisions from an
# Array. InputRecorder.INPUT.MULTIPLIER_STARTED and MULTIPLIER_ENDED are
# InputRecorder.input.multiplier_started and multiplier_ended. The local
# function draw_spawn_rate_indicator, which Lua then stores on the module,
# is the module's method.

require "powerups"
require "sound"
require "math_utils"
require "colors"
require "gamestate"
require "settings"
require "input_recorder"

module PowerupsManager
  # Lua's Debuffs: a table that requires debuffs the first time a field is
  # read from it.
  def self.debuffs
    require "debuffs"
    ::Debuffs
  end
  private_class_method :debuffs

  @circles = []
  @is_attract_mode = false

  class << self
    attr_accessor :is_invulnerable, :invulnerability_timer, :is_slowed, :slow_motion_timer, :is_phase_shift_active,
      :phase_shift_timer, :is_bolt_active, :bolt_timer, :is_score_multiplier_active,
      :score_multiplier_timer, :is_spawn_rate_boost_active, :spawn_rate_boost_timer
  end

  @is_invulnerable = false
  @invulnerability_timer = 0
  @is_slowed = false
  @slow_motion_timer = 0
  @is_phase_shift_active = false
  @phase_shift_timer = 0
  @is_bolt_active = false
  @bolt_timer = 0
  @is_score_multiplier_active = false
  @score_multiplier_timer = 0
  @is_spawn_rate_boost_active = false
  @spawn_rate_boost_timer = 0

  @original_velocities = {}.compare_by_identity
  @original_sizes = {}.compare_by_identity

  def self.activate_invulnerability(attract_mode_active)
    debuffs.clear_active_debuffs

    PowerupsManager.is_invulnerable = true
    PowerupsManager.invulnerability_timer = 10
    Sound.play("star_powerup") unless attract_mode_active
  end
  private_class_method :activate_invulnerability

  def self.activate_slow_motion(attract_mode_active)
    debuffs.clear_active_debuffs

    PowerupsManager.is_slowed = true
    PowerupsManager.slow_motion_timer = 10
    Sound.play("slowdown_powerup") unless attract_mode_active
    @original_velocities = {}.compare_by_identity
    @original_sizes = {}.compare_by_identity
    @circles.each do |circle|
      @original_velocities[circle] = circle.angular_velocity
      circle.angular_velocity = MathUtils.rnds(0.005, 0.015)
      @original_sizes[circle] = circle.obstacle_length
      min_obstacle_length = 5
      circle.obstacle_length = [circle.obstacle_length * 0.5, min_obstacle_length].max
    end
  end
  private_class_method :activate_slow_motion

  def self.activate_phase_shift(attract_mode_active)
    debuffs.clear_active_debuffs

    PowerupsManager.is_phase_shift_active = true
    PowerupsManager.phase_shift_timer = 10
    Sound.play("phaseshift_powerup") unless attract_mode_active
  end
  private_class_method :activate_phase_shift

  def self.activate_bolt(attract_mode_active)
    debuffs.clear_active_debuffs

    PowerupsManager.is_bolt_active = true
    PowerupsManager.bolt_timer = 30
    Powerups.create_lightning
    Sound.play("bolt_powerup") unless attract_mode_active
  end
  private_class_method :activate_bolt

  def self.activate_score_multiplier(attract_mode_active)
    debuffs.clear_active_debuffs

    if PowerupsManager.is_score_multiplier_active
      InputRecorder.record_next_tick(InputRecorder.input.multiplier_ended)
    end
    PowerupsManager.is_score_multiplier_active = true
    PowerupsManager.score_multiplier_timer = 30
    InputRecorder.record_next_tick(InputRecorder.input.multiplier_started)
    Sound.play("star_powerup") unless attract_mode_active
  end
  private_class_method :activate_score_multiplier

  def self.activate_spawn_rate_boost(attract_mode_active)
    debuffs.clear_active_debuffs

    PowerupsManager.is_spawn_rate_boost_active = true
    PowerupsManager.spawn_rate_boost_timer = 30
    Sound.play("phaseshift_powerup") unless attract_mode_active
  end
  private_class_method :activate_spawn_rate_boost

  def self.init(circles_ref, attract_mode_active)
    @circles = circles_ref
    @is_attract_mode = attract_mode_active
    PowerupsManager.reset
    @original_velocities = {}.compare_by_identity
    @original_sizes = {}.compare_by_identity
  end

  def self.reset
    PowerupsManager.is_invulnerable = false
    PowerupsManager.invulnerability_timer = 0
    PowerupsManager.is_slowed = false
    PowerupsManager.slow_motion_timer = 0
    PowerupsManager.is_phase_shift_active = false
    PowerupsManager.phase_shift_timer = 0
    PowerupsManager.is_bolt_active = false
    PowerupsManager.bolt_timer = 0
    PowerupsManager.is_score_multiplier_active = false
    PowerupsManager.score_multiplier_timer = 0
    PowerupsManager.is_spawn_rate_boost_active = false
    PowerupsManager.spawn_rate_boost_timer = 0
  end

  # Gives each circle back the angular velocity and obstacle length it had
  # before the slow motion, as Lua does in clear_active_powerups and update.
  def self.restore_circles
    @circles.each do |circle|
      circle.angular_velocity = @original_velocities[circle] if @original_velocities[circle]
      circle.obstacle_length = @original_sizes[circle] if @original_sizes[circle]
    end
    @original_velocities = {}.compare_by_identity
    @original_sizes = {}.compare_by_identity
  end
  private_class_method :restore_circles

  def self.clear_active_powerups
    if PowerupsManager.is_score_multiplier_active
      InputRecorder.record_next_tick(InputRecorder.input.multiplier_ended)
    end
    restore_circles if PowerupsManager.is_slowed
    PowerupsManager.reset
  end

  def self.get_player_color
    if PowerupsManager.is_invulnerable
      Colors.yellow
    elsif PowerupsManager.is_phase_shift_active
      Colors.emerald_shade
    elsif PowerupsManager.is_slowed
      Colors.cyan_glow
    else
      Colors.periwinkle_mist
    end
  end

  def self.get_ping_color
    if PowerupsManager.is_phase_shift_active
      Colors.emerald_shade
    elsif PowerupsManager.is_invulnerable
      Colors.yellow
    elsif PowerupsManager.is_slowed
      Colors.cyan_glow
    else
      Colors.periwinkle_mist
    end
  end

  def self.get_current_max_radius
    PowerupsManager.is_phase_shift_active ? 18 : 12
  end

  def self.draw_next_jump_ping_indicator(jump_pings, blip_counter, current_level_data)
    return unless jump_pings
    return if GameState.is_not("playing")

    jump_pings.each do |ping|
      next unless ping.life > 0 && ping.circle

      current_max_radius = PowerupsManager.get_current_max_radius
      color = if current_level_data &&
          current_level_data.win_condition.type == "blips" &&
          blip_counter.value >= current_level_data.win_condition.value - 1

        current_level_data.win_condition.final_blip_color
      elsif ping.circle&.is_passed
        Colors.rusty_cedar_transparent
      else
        PowerupsManager.get_ping_color
      end
      alpha = [0, 1 - ping.radius.fdiv(current_max_radius)].max

      Lota::Graphics.color = color[0], color[1], color[2], alpha * 0.8
      Lota::Graphics.line_width = 1.5
      Lota::Graphics.circle(:line, ping.circle.position.x, ping.circle.position.y, ping.radius)
      Lota::Graphics.line_width = 1
    end
  end

  def self.update(dt, game_state)
    if PowerupsManager.is_invulnerable && game_state != "help" && game_state != "levelCompleted"
      PowerupsManager.invulnerability_timer -= dt
      PowerupsManager.is_invulnerable = false if PowerupsManager.invulnerability_timer <= 0
    end

    if PowerupsManager.is_slowed && game_state != "help" && game_state != "levelCompleted"
      PowerupsManager.slow_motion_timer -= dt
      if PowerupsManager.slow_motion_timer <= 0
        PowerupsManager.is_slowed = false
        restore_circles
      end
    end

    if PowerupsManager.is_phase_shift_active && game_state != "help" && game_state != "levelCompleted"
      PowerupsManager.phase_shift_timer -= dt
      PowerupsManager.is_phase_shift_active = false if PowerupsManager.phase_shift_timer <= 0
    end

    if PowerupsManager.is_bolt_active && game_state != "help" && game_state != "levelCompleted"
      PowerupsManager.bolt_timer -= dt
      PowerupsManager.is_bolt_active = false if PowerupsManager.bolt_timer <= 0
    end

    if PowerupsManager.is_score_multiplier_active && game_state != "help" && game_state != "levelCompleted"
      PowerupsManager.score_multiplier_timer -= dt
      if PowerupsManager.score_multiplier_timer <= 0
        InputRecorder.record_next_tick(InputRecorder.input.multiplier_ended)
        PowerupsManager.is_score_multiplier_active = false
      end
    end

    if PowerupsManager.is_spawn_rate_boost_active && game_state != "help" && game_state != "levelCompleted"
      PowerupsManager.spawn_rate_boost_timer -= dt
      PowerupsManager.is_spawn_rate_boost_active = false if PowerupsManager.spawn_rate_boost_timer <= 0
    end

    Powerups.update(dt, game_state, PowerupsManager.is_bolt_active, PowerupsManager.is_spawn_rate_boost_active)
  end

  # Activates each powerup collected, in Lua's order.
  def self.activate_collected(collected_star, collected_clock, collected_phase_shift, collected_bolt,
    collected_score_multiplier, collected_spawn_rate_boost
  )
    activate_invulnerability(@is_attract_mode) if collected_star
    activate_slow_motion(@is_attract_mode) if collected_clock
    activate_phase_shift(@is_attract_mode) if collected_phase_shift
    activate_bolt(@is_attract_mode) if collected_bolt
    activate_score_multiplier(@is_attract_mode) if collected_score_multiplier
    activate_spawn_rate_boost(@is_attract_mode) if collected_spawn_rate_boost
  end
  private_class_method :activate_collected

  def self.handle_blip_collision(player_circle)
    return [false, false] if !player_circle || !player_circle.next

    collected_star, collected_clock, collected_phase_shift, collected_bolt, collected_score_multiplier,
      collected_spawn_rate_boost = Powerups.check_blip_collision(player_circle, player_circle.next)

    activate_collected(collected_star, collected_clock, collected_phase_shift, collected_bolt,
      collected_score_multiplier, collected_spawn_rate_boost)

    blip_collected_powerup = collected_star ||
      collected_clock ||
      collected_phase_shift ||
      collected_bolt ||
      collected_score_multiplier ||
      collected_spawn_rate_boost

    PowerupsManager.is_invulnerable = true if blip_collected_powerup && !collected_star

    [blip_collected_powerup, collected_star]
  end

  def self.handle_player_collision(player_circle)
    return unless player_circle

    activate_collected(*Powerups.check_collisions(player_circle))
  end

  def self.draw_spawn_rate_indicator
    return if GameState.is("gameOver") || GameState.is("levelCompleted")

    alpha_pulse = 0.8
    unless GameState.is_paused
      alpha_pulse = (Math.sin(Lota::Timer.time * 8) * 0.2) + 0.6 # Pulses between 40% and 80% opacity
    end
    color = Colors.neon_lime_splash

    Lota::Graphics.color = color[0], color[1], color[2], alpha_pulse
    Lota::Graphics.rectangle(:fill, 0, 0, Settings.internal_width, 2.5)
  end
end
# SPDX-SnippetEnd
