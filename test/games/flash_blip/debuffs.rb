# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's debuffs.lua
# (test/fixtures/flash_blip/game/debuffs.lua, lines 1-239), by the rules of
# doc/contributors/design/translation.md: setColor and setLineWidth become
# writers (rules 5 and 6), "fill" and "line" symbols (rule 9), and the
# paired push and pop of draw_emp_fuse the block form of push (rule 11).
# The module's data fields are its accessors, its Lua locals instance
# variables, and its fuses and particles Structs. The spawn interval is
# drawn when the module loads, as Lua draws it when the module is first
# required. Lua's removals from the end of a list by index walk the Ruby
# Array from its last index down. activate_emp and check_collisions require
# powerups_manager and powerups when they run, as the Lua does, so that
# neither loads before the Lua loads it.

require "lib/vector"
require "settings"
require "sound"
require "colors"
require "math_utils"
require "gamestate"

module Debuffs
  # An EMP fuse falling down the screen.
  EmpFuse = Struct.new(:pos, :radius, :speed, :color, :life, :rotation, keyword_init: true)

  # A particle a fuse trails or bursts into.
  Particle = Struct.new(:pos, :vel, :life, :max_life, :color, keyword_init: true)

  class << self
    attr_accessor :emp_fuses, :particles, :is_emp_active, :emp_timer, :glitch_timer
  end

  @emp_fuses = []
  @particles = []
  @is_emp_active = false
  @emp_timer = 0
  @glitch_timer = 0

  @min_spawn_interval = 20
  @max_spawn_interval = 40

  @min_particle_life = 20
  @max_particle_life = 40

  @spawn_timer = 0
  @spawn_interval = Lota::Math.random(@min_spawn_interval, @max_spawn_interval)

  @debuff_color = Colors.crimson

  def self.init
    Debuffs.reset
  end

  def self.reset
    Debuffs.emp_fuses = []
    Debuffs.particles = []
    Debuffs.is_emp_active = false
    Debuffs.emp_timer = 0
    Debuffs.glitch_timer = 0
    @spawn_timer = 0
    @spawn_interval = Lota::Math.random(@min_spawn_interval, @max_spawn_interval)
  end

  def self.spawn_emp_fuse
    emp_fuse = EmpFuse.new(
      pos: Vector.new(Lota::Math.random(2.5, Settings.internal_width - 2.5), -2.5),
      radius: 3.5,
      speed: Lota::Math.random(6, 12),
      color: @debuff_color,
      life: 1,
      rotation: 0,
    )
    Debuffs.emp_fuses << emp_fuse
  end

  def self.spawn_particle(position, count, speed, angle, angle_width, color)
    count ||= 1
    count.times do
      particle_angle = angle + (((Lota::Math.random * 2) - 1) * angle_width)
      Debuffs.particles << Particle.new(
        pos: position.copy,
        vel: Vector.new(Math.cos(particle_angle) * speed, Math.sin(particle_angle) * speed),
        life: Lota::Math.random(@min_particle_life, @max_particle_life),
        max_life: @max_particle_life,
        color:,
      )
    end
  end

  # Removes, from the last element to the first, each element of +tbl+
  # for which the block is true.
  def self.remove(tbl)
    i = tbl.size - 1
    while i >= 0
      tbl.delete_at(i) if yield(tbl[i])
      i -= 1
    end
  end
  private_class_method :remove

  def self.update(dt, game_state)
    return if game_state == "gameOver" || game_state == "help" || game_state == "levelCompleted"

    if Debuffs.is_emp_active
      Debuffs.emp_timer -= dt
      Debuffs.is_emp_active = false if Debuffs.emp_timer <= 0
    end

    Debuffs.glitch_timer -= dt if Debuffs.glitch_timer && Debuffs.glitch_timer > 0

    @spawn_timer += dt
    if @spawn_timer > @spawn_interval
      Debuffs.spawn_emp_fuse
      @spawn_timer = 0
      @spawn_interval = Lota::Math.random(@min_spawn_interval, @max_spawn_interval)
    end

    (Debuffs.emp_fuses.size - 1).downto(0) do |i|
      fuse = Debuffs.emp_fuses[i]
      fuse.pos.y += fuse.speed * dt
      fuse.rotation += dt * 2.5
      Debuffs.spawn_particle(fuse.pos, 1, 0.5, -Math::PI / 2, 0.5, @debuff_color)

      Debuffs.emp_fuses.delete_at(i) if fuse.pos.y > Settings.internal_height + fuse.radius
    end

    remove(Debuffs.particles) do |particle|
      particle.pos.add(particle.vel.copy.mul(dt * 60))
      particle.life -= 1
      particle.life <= 0
    end
  end

  def self.draw_emp_fuse(x, y, radius, rotation, line_width = nil)
    Lota::Graphics.push do
      Lota::Graphics.translate(x, y)
      Lota::Graphics.rotate(rotation)

      # Outer segmented circle
      Lota::Graphics.line_width = line_width || 1
      Lota::Graphics.circle(:line, 0, 0, radius, 8)

      # Inner cross (times sign)
      Lota::Graphics.line(-radius * 0.35, -radius * 0.35, radius * 0.35, radius * 0.35)
      Lota::Graphics.line(-radius * 0.35, radius * 0.35, radius * 0.35, -radius * 0.35)
    end
    Lota::Graphics.line_width = 1
  end

  def self.draw(game_state)
    return if game_state == "gameOver" || game_state == "levelCompleted"

    Debuffs.particles.each do |particle|
      alpha = [0, particle.life.fdiv(particle.max_life)].max
      Lota::Graphics.color = particle.color[0], particle.color[1], particle.color[2], alpha
      Lota::Graphics.circle(:fill, particle.pos.x, particle.pos.y, 0.25)
    end

    Debuffs.emp_fuses.each do |fuse|
      Lota::Graphics.color = fuse.color[0], fuse.color[1], fuse.color[2], 1
      Debuffs.draw_emp_fuse(fuse.pos.x, fuse.pos.y, fuse.radius, fuse.rotation)
    end

    Lota::Graphics.color = 1, 1, 1, 1
  end

  def self.activate_emp
    Debuffs.is_emp_active = true
    Debuffs.emp_timer = 10.0 # EMP debuff duration
    Sound.play("debuff_emp") unless GameState.is_attract_mode

    require "powerups_manager"
    PowerupsManager.clear_active_powerups

    require "powerups"
    Powerups.active_pings = []
    Powerups.particles = []
  end

  def self.check_collisions(player)
    return false unless player

    collected_emp = false

    (Debuffs.emp_fuses.size - 1).downto(0) do |i|
      fuse = Debuffs.emp_fuses[i]
      next unless MathUtils.is_circle_collision(player.position.x, player.position.y, 2.5, fuse.pos.x, fuse.pos.y,
        fuse.radius)

      Debuffs.spawn_particle(fuse.pos, 25, 2.5, 0, Math::PI * 2, @debuff_color)
      Debuffs.emp_fuses.delete_at(i)
      collected_emp = true
    end

    require "powerups"
    (Powerups.active_pings.size - 1).downto(0) do |i|
      ping = Powerups.active_pings[i]
      next unless ping.life > 0

      (Debuffs.emp_fuses.size - 1).downto(0) do |j|
        fuse = Debuffs.emp_fuses[j]
        next unless MathUtils.is_circle_collision(ping.pos.x, ping.pos.y, ping.radius, fuse.pos.x, fuse.pos.y,
          fuse.radius)

        Debuffs.spawn_particle(fuse.pos, 25, 2.5, 0, Math::PI * 2, @debuff_color)
        Debuffs.emp_fuses.delete_at(j)
        collected_emp = true
      end
    end

    Debuffs.activate_emp if collected_emp

    collected_emp
  end

  def self.check_blip_collision(player, target)
    return false if !player || !target

    collected_emp = false
    p1 = player.position
    p2 = target.position

    (Debuffs.emp_fuses.size - 1).downto(0) do |i|
      fuse = Debuffs.emp_fuses[i]
      next unless MathUtils.is_line_circle_collision(p1, p2, fuse.pos, fuse.radius)

      Debuffs.spawn_particle(fuse.pos, 25, 2.5, 0, Math::PI * 2, @debuff_color)
      Debuffs.emp_fuses.delete_at(i)
      collected_emp = true
    end

    Debuffs.activate_emp if collected_emp

    collected_emp
  end

  def self.clear_active_debuffs
    Debuffs.is_emp_active = false
    Debuffs.emp_timer = 0
  end
end
# SPDX-SnippetEnd
