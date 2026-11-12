# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's math_utils.lua
# (test/fixtures/flash_blip/game/math_utils.lua, lines 1-161), by the rules
# of doc/contributors/design/translation.md: love.math.random becomes
# Lota::Math.random (rule 1). The MathUtils table becomes the module
# MathUtils, and its local function get_cached_trig a private method of it,
# with the cache, a Hash keyed by number, kept in the module.
#
# Lua numbers are all doubles, so where Lua divides, Ruby divides by a
# Float. Lua's % on doubles is a - floor(a / b) * b, which can differ in
# the last bit from Ruby's Float#%, built on C's fmod, so lua_mod computes
# it as Lua does. Lua's math.min and math.max of several numbers are the
# min and max of an Array.

require "lib/vector"

module MathUtils
  # Generates a decimal random number in the range [a, b).
  def self.rnd(a, b = nil)
    if b.nil?
      b = a
      a = 0
    end
    (Lota::Math.random * (b - a)) + a
  end

  # Generates an integer random number in the range [a, b].
  def self.rndi(a, b)
    Lota::Math.random(a, b)
  end

  # Generates a random number in a symmetric range [-a, a] or [a, b).
  def self.rnds(a, b = nil)
    if b.nil?
      (Lota::Math.random * (2 * a)) - a
    else
      (Lota::Math.random * (b - a)) + a
    end
  end

  def self.distance(p1, p2)
    dx = p2.x - p1.x
    dy = p2.y - p1.y
    Math.sqrt((dx * dx) + (dy * dy))
  end

  # Checks collision between two circles.
  def self.is_circle_collision(x1, y1, r1, x2, y2, r2)
    dx = x1 - x2
    dy = y1 - y2
    distance = Math.sqrt((dx * dx) + (dy * dy))
    distance < (r1 + r2)
  end

  # Checks collision between a line segment and a circle.
  def self.is_line_circle_collision(p1, p2, circle_center, circle_radius)
    d = Vector.new(p2.x, p2.y).sub(p1)
    f = Vector.new(p1.x, p1.y).sub(circle_center)

    a = d.dot(d)
    b = 2 * f.dot(d)
    c = f.dot(f) - (circle_radius * circle_radius)

    discriminant = (b * b) - (4 * a * c)
    if discriminant < 0
      false
    else
      discriminant = Math.sqrt(discriminant)
      t1 = (-b - discriminant) / (2.0 * a)
      t2 = (-b + discriminant) / (2.0 * a)

      return true if (t1 >= 0 && t1 <= 1) || (t2 >= 0 && t2 <= 1)

      return true if f.dot(f) < circle_radius * circle_radius

      false
    end
  end

  # Lua's a % b for doubles: a - floor(a / b) * b.
  def self.lua_mod(a, b)
    a - ((a / b).floor * b)
  end
  private_class_method :lua_mod

  # The cosine and sine get_cached_trig caches for an angle.
  Trig = Struct.new(:cos, :sin, keyword_init: true)

  @trig_cache = {}
  TRIG_CACHE_SIZE = 3600

  def self.get_cached_trig(angle)
    normalized_angle = lua_mod(angle, Math::PI * 2)
    normalized_angle += (Math::PI * 2) if normalized_angle < 0

    key = (normalized_angle * TRIG_CACHE_SIZE / (Math::PI * 2)).floor

    @trig_cache[key] ||= Trig.new(
      cos: Math.cos(angle),
      sin: Math.sin(angle),
    )

    @trig_cache[key]
  end
  private_class_method :get_cached_trig

  # Checks intersection between a line segment and an Axis-Aligned Bounding Box (AABB).
  def self.is_line_aabb_intersect(x1, y1, x2, y2, min_x, min_y, max_x, max_y)
    dx = x2 - x1
    dy = y2 - y1

    if dx.abs < 1e-8 && dy.abs < 1e-8
      return x1 >= min_x && x1 <= max_x && y1 >= min_y && y1 <= max_y
    end

    t1 = 0
    t2 = 1

    if dx.abs > 1e-8
      inv_dx = 1.0 / dx
      tx1 = (min_x - x1) * inv_dx
      tx2 = (max_x - x1) * inv_dx
      near_x = [tx1, tx2].min
      far_x = [tx1, tx2].max
      t1 = [t1, near_x].max
      t2 = [t2, far_x].min
    elsif x1 < min_x || x1 > max_x
      return false
    end

    if dy.abs > 1e-8
      inv_dy = 1.0 / dy
      ty1 = (min_y - y1) * inv_dy
      ty2 = (max_y - y1) * inv_dy
      near_y = [ty1, ty2].min
      far_y = [ty1, ty2].max
      t1 = [t1, near_y].max
      t2 = [t2, far_y].min
    elsif y1 < min_y || y1 > max_y
      return false
    end

    t1 <= t2
  end

  # Checks collision between a line segment and a rotated rectangle.
  def self.is_line_rotated_rect_collision(line_p1, line_p2, rect_center, rect_width, rect_height, rect_angle)
    trig = get_cached_trig(-rect_angle)
    cos_angle = trig.cos
    sin_angle = trig.sin

    dx1 = line_p1.x - rect_center.x
    dy1 = line_p1.y - rect_center.y
    dx2 = line_p2.x - rect_center.x
    dy2 = line_p2.y - rect_center.y

    local_p1_x = (dx1 * cos_angle) - (dy1 * sin_angle)
    local_p1_y = (dx1 * sin_angle) + (dy1 * cos_angle)
    local_p2_x = (dx2 * cos_angle) - (dy2 * sin_angle)
    local_p2_y = (dx2 * sin_angle) + (dy2 * cos_angle)

    half_w = rect_width * 0.5
    half_h = rect_height * 0.5

    MathUtils.is_line_aabb_intersect(
      local_p1_x,
      local_p1_y,
      local_p2_x,
      local_p2_y,
      -half_w,
      -half_h,
      half_w,
      half_h,
    )
  end
end
# SPDX-SnippetEnd
