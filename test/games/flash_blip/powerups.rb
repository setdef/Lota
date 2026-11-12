# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's powerups.lua
# (test/fixtures/flash_blip/game/powerups.lua, lines 1-907), by the rules
# of doc/contributors/design/translation.md: setColor and setLineWidth
# become writers (rules 5 and 6), "fill" and "line" symbols (rule 9), each
# paired push and pop the block form of push (rule 11), and
# love.math.triangulate Lota::Math.triangulate, which returns the triangles
# as an Array of Arrays. The module's data fields are its accessors, its Lua
# locals instance variables, and its falling powerups, particles, pings,
# lightning, and the lightning's points Structs. The two spawn intervals
# are drawn when the module loads, as Lua draws them when the module is
# first required. Lua's removals from the end of a list by index walk the
# Ruby Array from its last index down. add_point takes the 0-based index of
# the segment's first point, so update draws Lua's 1-based index and
# passes one less. Lua repeats one loop for each of the six kinds of
# powerup in update and in check_collisions; here each is a call of fall
# or collect, in the same order, with the same colors and the same random
# draws. check_collisions and check_blip_collision return Lua's six
# results as an Array of six. InputRecorder.INPUT.PING is
# InputRecorder.input.ping. activate_player_ping requires debuffs,
# sound, and input_recorder when it runs, as the Lua does.

require "colors"
require "lib/vector"
require "settings"
require "math_utils"

module Powerups
  # A powerup falling down the screen.
  Item = Struct.new(:pos, :radius, :speed, :color, :life, :rotation, keyword_init: true)

  # A particle a powerup trails or bursts into.
  Particle = Struct.new(:pos, :vel, :life, :max_life, :color, keyword_init: true)

  # A ping the player sends out.
  Ping = Struct.new(:pos, :radius, :max_radius, :speed, :life, :is_phase_shift_active, :color, keyword_init: true)

  # The bolt powerup's lightning net.
  Lightning = Struct.new(:source, :target, :main_line, :color, :flash_color, :is_flashing, :flash_timer,
    keyword_init: true)

  # A point of the lightning's line.
  Point = Struct.new(:x, :y, keyword_init: true)

  class << self
    attr_accessor :stars, :clocks, :phase_shifts, :bolts, :score_multipliers, :spawn_rate_boosts, :particles,
      :active_pings, :lightning
  end

  @stars = []
  @clocks = []
  @phase_shifts = []
  @bolts = []
  @score_multipliers = []
  @spawn_rate_boosts = []

  @particles = []
  @active_pings = []

  @lightning = nil

  # First intervals are shorter
  @active_spawn_timer = 0
  @active_spawn_interval = Lota::Math.random(4, 8)
  @next_active_powerup_type = "star"

  @support_spawn_timer = 0
  @support_spawn_interval = Lota::Math.random(5, 10)
  @next_support_powerup_type = "bolt"

  def self.reset
    Powerups.stars = []
    Powerups.clocks = []
    Powerups.phase_shifts = []
    Powerups.bolts = []
    Powerups.score_multipliers = []
    Powerups.spawn_rate_boosts = []
    Powerups.particles = []
    Powerups.active_pings = []
    Powerups.lightning = nil
    @active_spawn_timer = 0
    @active_spawn_interval = Lota::Math.random(4, 8)
    @next_active_powerup_type = "star"
    @support_spawn_timer = 0
    @support_spawn_interval = Lota::Math.random(5, 10)
    @next_support_powerup_type = "bolt"
  end

  def self.lightning_y_position
    Settings.internal_height * 0.65
  end
  private_class_method :lightning_y_position

  def self.draw_star(x, y, r, rotation)
    Lota::Graphics.push do
      Lota::Graphics.translate(x, y)
      Lota::Graphics.rotate(rotation)

      points = []
      spikes = 5
      outer_radius = r
      inner_radius = r * 0.4
      angle_step = 2 * Math::PI / (spikes * 2)

      (0..((2 * spikes) - 1)).each do |i|
        radius = i.even? ? outer_radius : inner_radius
        angle = (i * angle_step) - (Math::PI / 2)
        points << (Math.cos(angle) * radius)
        points << (Math.sin(angle) * radius)
      end

      # Use triangulation for concave polygons
      triangles = Lota::Math.triangulate(points)

      triangles.each do |triangle|
        Lota::Graphics.polygon(:fill, triangle)
      end
    end
  end

  def self.draw_clock(x, y, r, rotation)
    Lota::Graphics.push do
      Lota::Graphics.translate(x, y)
      Lota::Graphics.rotate(rotation)

      # Two opposite triangles to form the hourglass
      half_height = r
      half_width = r * 0.75

      # Upper triangle
      triangle_up = [
        -half_width,
        -half_height,
        half_width,
        -half_height,
        0,
        0,
      ]

      # Lower triangle
      triangle_bottom = [
        -half_width,
        half_height,
        half_width,
        half_height,
        0,
        0,
      ]

      Lota::Graphics.polygon(:fill, triangle_up)
      Lota::Graphics.polygon(:fill, triangle_bottom)
    end
  end

  def self.draw_phase_shift(x, y, r, rotation, line_width = nil)
    Lota::Graphics.push do
      Lota::Graphics.translate(x, y)
      Lota::Graphics.rotate(rotation)
      Lota::Graphics.line_width = line_width || 1

      # Draw two chevron arrows pointing at each other
      arrow_points1 = [
        -r * 0.6,
        -r * 0.5,
        -r * 0.2,
        0,
        -r * 0.6,
        r * 0.5,
      ]
      arrow_points2 = [
        r * 0.6,
        -r * 0.5,
        r * 0.2,
        0,
        r * 0.6,
        r * 0.5,
      ]

      Lota::Graphics.line(arrow_points1)
      Lota::Graphics.line(arrow_points2)
    end
    Lota::Graphics.line_width = 1
  end

  def self.draw_bolt(x, y, r, rotation, line_width = nil)
    Lota::Graphics.push do
      Lota::Graphics.translate(x, y)
      Lota::Graphics.rotate(rotation)
      Lota::Graphics.line_width = (line_width || 1) * 1.2

      # Triangular S shape for the lightning bolt
      points = [
        -r * 0.2,
        -r,
        r * 0.4,
        -r * 0.2,
        -r * 0.4,
        r * 0.2,
        r * 0.2,
        r,
      ]

      Lota::Graphics.line(points)
    end
    Lota::Graphics.line_width = 1
  end

  def self.draw_score_multiplier(x, y, r, rotation)
    Lota::Graphics.push do
      Lota::Graphics.translate(x, y)
      Lota::Graphics.rotate(rotation)

      # Draw 4 triangles pointing outward to symbolize multiplication
      half_r = r * 0.5
      outer_r = r * 1.1

      # Upper triangle
      tri_up = [
        0,
        -outer_r,
        -half_r,
        -half_r,
        half_r,
        -half_r,
      ]

      # Lower triangle
      tri_down = [
        0,
        outer_r,
        -half_r,
        half_r,
        half_r,
        half_r,
      ]

      # Left triangle
      tri_left = [
        -outer_r,
        0,
        -half_r,
        -half_r,
        -half_r,
        half_r,
      ]

      # Right triangle
      tri_right = [
        outer_r,
        0,
        half_r,
        -half_r,
        half_r,
        half_r,
      ]

      Lota::Graphics.polygon(:fill, tri_up)
      Lota::Graphics.polygon(:fill, tri_down)
      Lota::Graphics.polygon(:fill, tri_left)
      Lota::Graphics.polygon(:fill, tri_right)
    end
  end

  def self.draw_spawn_rate_boost(x, y, r, rotation)
    Lota::Graphics.push do
      Lota::Graphics.translate(x, y)
      Lota::Graphics.rotate(rotation)

      arrow_width = r * 0.7
      arrow_body_height = r * 0.5
      arrow_tip_height = -r

      arrow_points = [
        0,
        arrow_tip_height,
        -arrow_width,
        arrow_body_height,
        arrow_width,
        arrow_body_height,
      ]
      Lota::Graphics.polygon(:fill, arrow_points)

      particle_radius = r * 0.2
      Lota::Graphics.circle(:fill, 0, arrow_tip_height - (particle_radius * 1.5), particle_radius)
      Lota::Graphics.circle(:fill, -arrow_width * 0.6, arrow_tip_height + (particle_radius * 0.5),
        particle_radius * 0.8)
      Lota::Graphics.circle(:fill, arrow_width * 0.6, arrow_tip_height + (particle_radius * 0.5),
        particle_radius * 0.8)
    end
  end

  def self.spawn_star
    star = Item.new(
      pos: Vector.new(Lota::Math.random(2.5, Settings.internal_width - 2.5), -2.5),
      radius: 3,
      speed: Lota::Math.random(6, 12),
      color: Colors.yellow,
      life: 1,
      rotation: 0,
    )
    Powerups.stars << star
  end

  def self.spawn_clock
    clock = Item.new(
      pos: Vector.new(Lota::Math.random(2.5, Settings.internal_width - 2.5), -2.5),
      radius: 3,
      speed: Lota::Math.random(6, 12),
      color: Colors.cyan_glow,
      life: 1,
      rotation: 0,
    )
    Powerups.clocks << clock
  end

  def self.spawn_phase_shift
    phase_shift = Item.new(
      pos: Vector.new(Lota::Math.random(2.5, Settings.internal_width - 2.5), -2.5),
      radius: 4,
      speed: Lota::Math.random(6, 12),
      color: Colors.emerald_shade,
      life: 1,
      rotation: 0,
    )
    Powerups.phase_shifts << phase_shift
  end

  def self.spawn_bolt
    bolt = Item.new(
      pos: Vector.new(Lota::Math.random(2.5, Settings.internal_width - 2.5), -2.5),
      radius: 4,
      speed: Lota::Math.random(6, 12),
      color: Colors.tangerine_blaze,
      life: 1,
      rotation: 0,
    )
    Powerups.bolts << bolt
  end

  def self.spawn_score_multiplier
    multiplier = Item.new(
      pos: Vector.new(Lota::Math.random(2.5, Settings.internal_width - 2.5), -2.5),
      radius: 4,
      speed: Lota::Math.random(6, 12),
      color: Colors.yellow,
      life: 1,
      rotation: 0,
    )
    Powerups.score_multipliers << multiplier
  end

  def self.spawn_spawn_rate_boost
    boost = Item.new(
      pos: Vector.new(Lota::Math.random(2.5, Settings.internal_width - 2.5), -2.5),
      radius: 4,
      speed: Lota::Math.random(6, 12),
      color: Colors.neon_lime_splash,
      life: 1,
      rotation: 0,
    )
    Powerups.spawn_rate_boosts << boost
  end

  # Create particles
  def self.particle(position, count, speed, angle, angle_width, color)
    count ||= 1
    count.times do
      particle_angle = angle + (((Lota::Math.random * 2) - 1) * angle_width)
      Powerups.particles << Particle.new(
        pos: position.copy,
        vel: Vector.new(Math.cos(particle_angle) * speed, Math.sin(particle_angle) * speed),
        life: Lota::Math.random(15, 30),
        max_life: 30,
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

  # Moves each falling powerup of +list+ down, turns it by +spin+ times
  # +dt+, trails a particle of +color+ (the powerup's own when nil), and
  # removes it once it falls off the screen, from the last to the first,
  # as each of Lua's six loops does.
  def self.fall(list, dt, spin, color)
    (list.size - 1).downto(0) do |i|
      item = list[i]
      item.pos.y += item.speed * dt
      item.rotation += dt * spin
      Powerups.particle(item.pos, 1, 0.5, -Math::PI / 2, 0.5, color || item.color)

      list.delete_at(i) if item.pos.y > Settings.internal_height + item.radius
    end
  end
  private_class_method :fall

  def self.update(dt, game_state, is_bolt_active, is_spawn_rate_boost_active)
    return if game_state == "gameOver" || game_state == "help" || game_state == "levelCompleted"

    if is_bolt_active
      source = Point.new(x: 0, y: lightning_y_position)
      target = Point.new(x: Settings.internal_width, y: lightning_y_position)
      Powerups.lightning.main_line = [source, target]
      10.times do
        index = Lota::Math.random(Powerups.lightning.main_line.size - 1)
        Powerups.add_point(Powerups.lightning, index - 1)
      end

      if Powerups.lightning.is_flashing
        Powerups.lightning.flash_timer -= dt
        Powerups.lightning.is_flashing = false if Powerups.lightning.flash_timer <= 0
      end
    end

    # Logic for the appearance of active powerups
    @active_spawn_timer += dt
    if @active_spawn_timer > @active_spawn_interval
      if @next_active_powerup_type == "star"
        Powerups.spawn_star
      elsif @next_active_powerup_type == "clock"
        Powerups.spawn_clock
      else
        Powerups.spawn_phase_shift
      end
      @active_spawn_timer = 0
      @active_spawn_interval = if is_spawn_rate_boost_active
        Lota::Math.random(2.5, 5)
      else
        Lota::Math.random(5, 10)
      end
      rand = Lota::Math.random
      @next_active_powerup_type = if rand > 0.66
        "star"
      elsif rand > 0.33
        "clock"
      else
        "phase_shift"
      end
    end

    # Logic for the appearance of support powerups
    @support_spawn_timer += dt
    if @support_spawn_timer > @support_spawn_interval
      if @next_support_powerup_type == "bolt"
        Powerups.spawn_bolt
      elsif @next_support_powerup_type == "scoreMultiplier"
        Powerups.spawn_score_multiplier
      else
        Powerups.spawn_spawn_rate_boost
      end
      @support_spawn_timer = 0
      # The next powerup will have a higher probability of appearing 2x
      @support_spawn_interval = if is_spawn_rate_boost_active
        Lota::Math.random(6, 10)
      else
        Lota::Math.random(12, 20)
      end
      rand = Lota::Math.random
      @next_support_powerup_type = if rand > 0.66
        "bolt"
      elsif rand > 0.33
        "scoreMultiplier"
      else
        "spawnRateBoost"
      end
    end

    fall(Powerups.stars, dt, 2, Colors.yellow)
    fall(Powerups.clocks, dt, 2, Colors.cyan_glow)
    fall(Powerups.phase_shifts, dt, 1.5, Colors.emerald_shade)
    fall(Powerups.bolts, dt, 1.5, Colors.tangerine_blaze)
    fall(Powerups.score_multipliers, dt, 1.5, nil)
    fall(Powerups.spawn_rate_boosts, dt, 1.5, nil)

    remove(Powerups.particles) do |particle|
      particle.pos.add(particle.vel.copy.mul(dt * 60))
      particle.life -= 1
      particle.life <= 0
    end
  end

  def self.draw(game_state)
    return if game_state == "gameOver" || game_state == "levelCompleted"

    Powerups.particles.each do |particle|
      alpha = [0, particle.life.fdiv(particle.max_life)].max
      Lota::Graphics.color = particle.color[0], particle.color[1], particle.color[2], alpha
      Lota::Graphics.circle(:fill, particle.pos.x, particle.pos.y, 0.25)
    end

    Powerups.stars.each do |star|
      Lota::Graphics.color = star.color[0], star.color[1], star.color[2], 1
      Powerups.draw_star(star.pos.x, star.pos.y, star.radius, star.rotation)
    end

    Powerups.clocks.each do |clock|
      Lota::Graphics.color = clock.color[0], clock.color[1], clock.color[2], 1
      Powerups.draw_clock(clock.pos.x, clock.pos.y, clock.radius, clock.rotation)
    end

    Powerups.phase_shifts.each do |phase_shift|
      Lota::Graphics.color = phase_shift.color[0], phase_shift.color[1], phase_shift.color[2], 1
      Powerups.draw_phase_shift(phase_shift.pos.x, phase_shift.pos.y, phase_shift.radius, phase_shift.rotation, 1)
    end

    Powerups.bolts.each do |bolt|
      Lota::Graphics.color = bolt.color[0], bolt.color[1], bolt.color[2], 1
      Powerups.draw_bolt(bolt.pos.x, bolt.pos.y, bolt.radius, bolt.rotation, 1)
    end

    Powerups.score_multipliers.each do |multiplier|
      Lota::Graphics.color = multiplier.color[0], multiplier.color[1], multiplier.color[2], 1
      Powerups.draw_score_multiplier(multiplier.pos.x, multiplier.pos.y, multiplier.radius, multiplier.rotation)
    end

    Powerups.spawn_rate_boosts.each do |boost|
      Lota::Graphics.color = boost.color[0], boost.color[1], boost.color[2], 1
      Powerups.draw_spawn_rate_boost(boost.pos.x, boost.pos.y, boost.radius, boost.rotation)
    end

    Lota::Graphics.color = 1, 1, 1, 1
  end

  def self.draw_lightning
    return unless Powerups.lightning.main_line

    lightning_colors = [Colors.apricot_glow, Colors.tangerine_blaze]

    (0...(Powerups.lightning.main_line.size - 1)).each do |i|
      start_point = Powerups.lightning.main_line[i]
      end_point = Powerups.lightning.main_line[i + 1]

      color = lightning_colors[Lota::Math.random(1, lightning_colors.size) - 1]
      color = Powerups.lightning.flash_color if Powerups.lightning.is_flashing

      Lota::Graphics.color = color
      Lota::Graphics.line(start_point.x, start_point.y, end_point.x, end_point.y)
    end

    Lota::Graphics.color = 1, 1, 1, 1
  end

  def self.activate_player_ping(player_pos, is_phase_shift_active, color)
    require "debuffs"
    require "sound"
    if Debuffs.is_emp_active
      Sound.play("debuff_emp")
      Debuffs.spawn_particle(player_pos, 5, 1.5, 0, Math::PI * 2, [0.8, 0.1, 0.1])
      Debuffs.glitch_timer = 0.3
      return
    end

    require "input_recorder"
    InputRecorder.record(InputRecorder.input.ping) if InputRecorder.is_active

    new_ping = Ping.new(
      pos: player_pos.copy,
      radius: 0,
      max_radius: is_phase_shift_active ? (Settings.internal_width / 1.2) : (Settings.internal_width / 2.5),
      speed: is_phase_shift_active ? 60 : 40,
      life: 1,
      is_phase_shift_active:,
      color:,
    )
    Powerups.active_pings << new_ping
  end

  # Removes, from the last to the first, each powerup of +list+ that a
  # circle at +x+, +y+ of +radius+ touches, bursting it into particles of
  # +color+ (its own when nil), and answers whether it removed any, as
  # each of Lua's loops in check_collisions does.
  def self.collect(list, x, y, radius, color)
    collected = false
    (list.size - 1).downto(0) do |i|
      item = list[i]
      next unless MathUtils.is_circle_collision(x, y, radius, item.pos.x, item.pos.y, item.radius)

      Powerups.particle(item.pos, 20, 2, 0, Math::PI * 2, color || item.color)
      list.delete_at(i)
      collected = true
    end
    collected
  end
  private_class_method :collect

  def self.check_collisions(player)
    return [false, false, false, false, false, false] unless player

    px = player.position.x
    py = player.position.y
    collected_star = collect(Powerups.stars, px, py, 2.5, Colors.yellow)
    collected_clock = collect(Powerups.clocks, px, py, 2.5, Colors.cyan_glow)
    collected_phase_shift = collect(Powerups.phase_shifts, px, py, 2.5, Colors.emerald_shade)
    collected_bolt = collect(Powerups.bolts, px, py, 2.5, Colors.tangerine_blaze)
    collected_score_multiplier = collect(Powerups.score_multipliers, px, py, 2.5, nil)
    collected_spawn_rate_boost = collect(Powerups.spawn_rate_boosts, px, py, 2.5, nil)

    (Powerups.active_pings.size - 1).downto(0) do |i|
      ping = Powerups.active_pings[i]
      next unless ping.life > 0

      x = ping.pos.x
      y = ping.pos.y
      collected_star = true if collect(Powerups.stars, x, y, ping.radius, Colors.yellow)
      collected_clock = true if collect(Powerups.clocks, x, y, ping.radius, Colors.cyan_glow)
      collected_phase_shift = true if collect(Powerups.phase_shifts, x, y, ping.radius, Colors.emerald_shade)
      collected_bolt = true if collect(Powerups.bolts, x, y, ping.radius, Colors.tangerine_blaze)
      collected_score_multiplier = true if collect(Powerups.score_multipliers, x, y, ping.radius, nil)
      collected_spawn_rate_boost = true if collect(Powerups.spawn_rate_boosts, x, y, ping.radius, nil)
    end

    [
      collected_star,
      collected_clock,
      collected_phase_shift,
      collected_bolt,
      collected_score_multiplier,
      collected_spawn_rate_boost,
]
  end

  # +index+ is the 0-based index of the first point of the segment the
  # point goes into; Lua's is 1-based.
  def self.add_point(lightning, index)
    x1 = lightning.main_line[index].x
    y1 = lightning.main_line[index].y
    x2 = lightning.main_line[index + 1].x
    y2 = lightning.main_line[index + 1].y

    # Fractional position of the new point between x1,y1 and x2,y2
    t = 0.25 + (0.5 * Lota::Math.random)
    x = x1 + (t * (x2 - x1))
    y = y1 + (t * (y2 - y1))

    # Perpendicular vector to the segment (clockwise)
    dx = x2 - x1
    dy = y2 - y1
    length = Math.sqrt((dx * dx) + (dy * dy))
    return if length.zero?

    perp_x = dy / length
    perp_y = -dx / length

    # Deviation amplitude (proportional to the total length of the lightning)
    amplitude = 0.10

    # Random perpendicular offset
    offset = (Lota::Math.random - 0.5) * 2 * amplitude * length
    x += perp_x * offset
    y += perp_y * offset

    lightning.main_line.insert(index + 1, Point.new(x:, y:))
  end

  def self.create_lightning
    source = Point.new(x: 0, y: lightning_y_position)
    target = Point.new(x: Settings.internal_width, y: lightning_y_position)
    Powerups.lightning = Lightning.new(
      source:,
      target:,
      main_line: [source, target],
      color: Colors.tangerine_blaze,
      flash_color: Colors.white,
      is_flashing: false,
      flash_timer: 0,
    )
  end

  def self.check_lightning_collision(player)
    return false if !player || !Powerups.lightning.main_line

    player_y = player.position.y
    net_y = lightning_y_position

    if player_y >= net_y
      Powerups.lightning.is_flashing = true
      Powerups.lightning.flash_timer = 0.2
      return true
    end

    false
  end

  def self.update_pings(dt)
    (Powerups.active_pings.size - 1).downto(0) do |i|
      ping = Powerups.active_pings[i]
      if ping.life > 0
        current_max_radius = ping.is_phase_shift_active ? 60 : 30
        ping.radius += ping.speed * dt
        ping.life = 0 if ping.radius >= current_max_radius
      else
        Powerups.active_pings.delete_at(i)
      end
    end
  end

  def self.draw_pings
    Powerups.active_pings.each do |ping|
      next unless ping.life > 0

      current_max_radius = ping.is_phase_shift_active ? 60 : 30
      alpha = [0, 1 - ping.radius.fdiv(current_max_radius)].max
      color = ping.color || (ping.is_phase_shift_active ? Colors.emerald_shade : Colors.cyan)

      Lota::Graphics.color = color[0], color[1], color[2], alpha * 0.8
      Lota::Graphics.line_width = 1.5
      Lota::Graphics.circle(:line, ping.pos.x, ping.pos.y, ping.radius)
      Lota::Graphics.line_width = 1
    end
  end

  def self.is_ping_connected(jump_pings)
    Powerups.active_pings.each do |ping|
      next unless ping.life > 0 && jump_pings && !jump_pings.empty?

      jump_ping = jump_pings[0]
      next unless jump_ping.circle && jump_ping.life > 0

      if MathUtils.is_circle_collision(
        ping.pos.x,
        ping.pos.y,
        ping.radius,
        jump_ping.circle.position.x,
        jump_ping.circle.position.y,
        jump_ping.radius,
      )

        return true
      end
    end
    false
  end

  def self.check_blip_collision(player, target)
    return [false, false, false, false, false, false] if !player || !target

    p1 = player.position
    p2 = target.position

    check_list = lambda do |list|
      collected = false
      (list.size - 1).downto(0) do |i|
        item = list[i]
        next unless MathUtils.is_line_circle_collision(p1, p2, item.pos, item.radius)

        Powerups.particle(item.pos, 20, 2, 0, Math::PI * 2, item.color)
        list.delete_at(i)
        collected = true
      end
      collected
    end

    collected_star = check_list.call(Powerups.stars)
    collected_clock = check_list.call(Powerups.clocks)
    collected_phase_shift = check_list.call(Powerups.phase_shifts)
    collected_bolt = check_list.call(Powerups.bolts)
    collected_score_multiplier = check_list.call(Powerups.score_multipliers)
    collected_spawn_rate_boost = check_list.call(Powerups.spawn_rate_boosts)

    [
      collected_star,
      collected_clock,
      collected_phase_shift,
      collected_bolt,
      collected_score_multiplier,
      collected_spawn_rate_boost,
]
  end
end
# SPDX-SnippetEnd
