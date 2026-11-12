# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's lib/vector.lua
# (test/fixtures/flash_blip/game/lib/vector.lua, lines 1-93). The Lua table
# Vector, which its instances take as their metatable, becomes the class
# Vector, so Vector:new(x, y) is Vector.new(x, y), and each method keeps its
# name, snake_cased where Lua's is camelCase (addWithAngle is
# add_with_angle). A vector is an object of its own, compared by identity as
# Lua compares tables, and its x and y are read and written as Lua's fields
# are. Lua numbers are all doubles, so where Lua divides, Ruby divides as
# Floats with fdiv.

# Define a Vector object with useful methods.
class Vector
  attr_accessor :x, :y

  # Creates a new Vector instance.
  def initialize(x, y)
    @x = x
    @y = y
  end

  # Returns a copy of the vector.
  def copy
    Vector.new(x, y)
  end

  # Adds another vector to the current vector.
  def add(other_vector)
    self.x = x + other_vector.x
    self.y = y + other_vector.y
    self
  end

  # Adds a vector defined by an angle and length.
  def add_with_angle(angle, length)
    self.x = x + (Math.cos(angle) * length)
    self.y = y + (Math.sin(angle) * length)
    self
  end

  # Rotates the vector by a given angle.
  def rotate(angle)
    cos_angle = Math.cos(angle)
    sin_angle = Math.sin(angle)
    new_x = (x * cos_angle) - (y * sin_angle)
    new_y = (x * sin_angle) + (y * cos_angle)
    self.x = new_x
    self.y = new_y
    self
  end

  # Normalizes the vector (makes it a unit vector).
  def normalize
    len = Math.sqrt((x * x) + (y * y))
    if len > 0
      self.x = x.fdiv(len)
      self.y = y.fdiv(len)
    end
    self
  end

  # Multiplies the vector by a scalar.
  def mul(scalar)
    self.x = x * scalar
    self.y = y * scalar
    self
  end

  # Subtracts another vector and returns the result as a new vector.
  def sub(other_vector)
    Vector.new(x - other_vector.x, y - other_vector.y)
  end

  # Divides the vector by a scalar and returns the result as a new vector.
  def div(scalar)
    if scalar != 0
      Vector.new(x.fdiv(scalar), y.fdiv(scalar))
    else
      Vector.new(x, y) # Returns a copy to avoid division by zero.
    end
  end

  # Returns the length (magnitude) of the vector.
  def length
    Math.sqrt((x * x) + (y * y))
  end

  # Returns the distance to another vector.
  def distance(other)
    dx = x - other.x
    dy = y - other.y
    Math.sqrt((dx * dx) + (dy * dy))
  end

  # Returns the angle of the vector in radians.
  def angle
    Math.atan2(y, x)
  end

  # Returns the dot product of two vectors.
  def dot(other)
    (x * other.x) + (y * other.y)
  end
end
# SPDX-SnippetEnd
