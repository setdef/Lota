# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # What every one of LÖVE's objects answers, whatever its class:
  # +object_type+, +type+, and <tt>type_of?</tt>, translated from
  # Object:type and Object:typeOf (src/common/runtime.cpp, w__type and
  # w__typeOf; ADR 001, rule 16).
  #
  # LÖVE gives every object it hands to Lua these methods, and Lota gives
  # them to every class that wraps an engine object, by including this
  # module. Lota::Native answers both for the engine class it bound
  # (ext/lota/native/binding.hpp, define_engine_class), which each class
  # returns from its +native+ reader.
  #
  # A class that also has LÖVE's getType, such as Lota::Physics::Body,
  # answers it as +get_type+, and has no +type+, since +type+ there would
  # mean either: defining +get_type+ in a class that includes this module
  # takes +type+ away from it and its subclasses (rule 16).
  #
  # It takes the name of LÖVE's root type, Object, so inside
  # <tt>module Lota</tt> a bare +Object+ means this module, and Ruby's
  # root class is written <tt>::Object</tt>.
  module Object
    # Rule 16 for the class that includes Lota::Object. :nodoc:
    module TypeRule
      # Takes +type+ away when the class defines +get_type+, LÖVE's
      # getType, so that a call meant for either fails loudly instead of
      # answering the other (ADR 001, rule 16). :nodoc:
      def method_added(name)
        super
        undef_method(:type) if name == :get_type && method_defined?(:type)
      end
    end

    # Gives the class that includes Lota::Object rule 16's TypeRule.
    # :nodoc:
    def self.included(base)
      super
      base.extend(TypeRule)
    end

    # LÖVE's name for this object's type, as a String, matching
    # Object:type (src/common/runtime.cpp, w__type).
    #
    # It is the name of LÖVE's class, not Ruby's: a canvas is a
    # <tt>"Texture"</tt>, and a font a <tt>"Font"</tt>.
    #
    # === Example
    #
    #   Lota::Graphics::Canvas.new(16, 16).object_type # => "Texture"
    def object_type
      native.object_type
    end

    # Another name for #object_type, as ADR 001's rule 16 gives it, on
    # every class but those with LÖVE's getType, which answer +get_type+
    # instead and have no +type+.
    #
    # === Example
    #
    #   Lota::Graphics::Canvas.new(16, 16).type # => "Texture"
    def type
      object_type
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
