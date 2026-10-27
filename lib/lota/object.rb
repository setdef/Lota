# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # What every one of LÖVE's objects answers, whatever its class: +type+
  # and <tt>type_of?</tt>, translated from Object:type and Object:typeOf
  # (src/common/runtime.cpp, w__type and w__typeOf; ADR 001, rule 16).
  #
  # LÖVE gives every object it hands to Lua these methods, and Lota gives
  # them to every class that wraps an engine object, by including this
  # module. Lota::Native answers both for the engine class it bound
  # (ext/lota/native/binding.hpp, define_engine_class), which each class
  # returns from its +native+ reader.
  #
  # It takes the name of LÖVE's root type, Object, so inside
  # <tt>module Lota</tt> a bare +Object+ means this module, and Ruby's
  # root class is written <tt>::Object</tt>.
  module Object
    # LÖVE's name for this object's type, as a String, matching
    # Object:type (src/common/runtime.cpp, w__type).
    #
    # It is the name of LÖVE's class, not Ruby's: a canvas is a
    # <tt>"Texture"</tt>, and a font a <tt>"Font"</tt>.
    #
    # === Example
    #
    #   Lota::Graphics::Canvas.new(16, 16).type # => "Texture"
    def type
      native.type
    end

    # Whether this object is of the LÖVE type +name+, or of a type that
    # inherits from it, matching Object:typeOf (src/common/runtime.cpp,
    # w__typeOf).
    #
    # [name] String name of a LÖVE type, such as <tt>"Texture"</tt>,
    #   <tt>"Drawable"</tt>, or <tt>"Object"</tt>.
    #
    # Every object is an <tt>"Object"</tt>. A name LÖVE has no type for is
    # +false+, as in LÖVE. Raises TypeError for a +name+ that is not a
    # String, where LÖVE raises its "string expected" error.
    #
    # === Examples
    #
    #   texture = Lota::Graphics::Canvas.new(16, 16)
    #   texture.type_of?("Texture")  # => true
    #   texture.type_of?("Drawable") # => true
    #   texture.type_of?("Object")   # => true
    #   texture.type_of?("Font")     # => false
    def type_of?(name)
      raise TypeError, "wrong argument type #{name.class} (expected String)" unless name.is_a?(String)

      native.type_of?(name)
    end
  end
end
