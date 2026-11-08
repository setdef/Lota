# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # LÖVE's root type, Object, whose methods every one of LÖVE's objects
  # answers, whatever its class: +object_type+, +type+, and
  # <tt>type_of?</tt>, translated from Object:type and Object:typeOf
  # (src/common/runtime.cpp, w__type and w__typeOf; ADR 001, rule 16),
  # +release+, from Object:release (w__release), and +to_s+ and +==+, from
  # the __tostring and __eq LÖVE gives every object (w__tostring and
  # w__eq; rule 13).
  #
  # Every class that wraps an engine object inherits from it, as every
  # type in LÖVE inherits from Object, so every such object is a
  # Lota::Object. Lota::Native answers these methods for the engine class
  # it bound (ext/lota/native/binding.hpp, define_engine_class). LÖVE has no
  # function that makes a plain Object, so Lota::Object has no +new+ of
  # its own; each class that LÖVE makes objects of has the +new+ its
  # factory becomes (rule 2).
  #
  # A class that also has LÖVE's getType, such as Lota::Physics::Body,
  # answers it as +get_type+, and has no +type+, since +type+ there would
  # mean either: defining +get_type+ in a subclass takes +type+ away from
  # it and its subclasses (rule 16).
  #
  # It takes the name of LÖVE's root type, Object, so inside
  # <tt>module Lota</tt> a bare +Object+ means this class, and Ruby's
  # root class is written <tt>::Object</tt>.
  class Object
    private_class_method :new

    # Takes +type+ away when a subclass defines +get_type+, LÖVE's getType,
    # so that a call meant for either fails loudly instead of answering the
    # other (ADR 001, rule 16).
    private_class_method def self.method_added(name)
      super
      undef_method(:type) if name == :get_type && method_defined?(:type)
    end

    # The engine's object, which Lota::Native wraps, for Lota's own engine
    # objects.
    attr_reader :native
    protected :native

    # LÖVE's name for this object's type, as a String, matching
    # Object:type (src/common/runtime.cpp, w__type).
    #
    # It is the name of LÖVE's class, not Ruby's: a canvas is a
    # <tt>"Texture"</tt>, and a font a <tt>"Font"</tt>. It answers after
    # #release too, as in LÖVE.
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
    # [name] Symbol or String name of a LÖVE type, such as +:Texture+,
    #   +:Drawable+, or +:Object+, which are names, not text, so Symbols,
    #   as ADR 001's rule 9 makes LÖVE's names.
    #
    # Every object is an +:Object+. A name LÖVE has no type for is +false+,
    # as in LÖVE. Raises TypeError for a +name+ that is neither, where
    # LÖVE raises its "string expected" error.
    #
    # === Examples
    #
    #   texture = Lota::Graphics::Canvas.new(16, 16)
    #   texture.type_of?(:Texture)  # => true
    #   texture.type_of?(:Drawable) # => true
    #   texture.type_of?("Object")  # => true
    #   texture.type_of?(:Font)     # => false
    def type_of?(name)
      name = name.name if name.is_a?(Symbol)
      raise TypeError, "wrong argument type #{name.class} (expected Symbol or String)" unless name.is_a?(String)

      native.type_of?(name)
    end

    # Ends this object's use of its engine object, and returns whether it
    # was in use, matching Object:release (src/common/runtime.cpp,
    # w__release): +true+ the first time, and +false+ after.
    #
    # Every later call that uses the object, as its receiver or as an
    # argument, raises RuntimeError ("Cannot use object after it has been
    # released."), as in LÖVE; #object_type, #type_of?, #to_s, #==, and
    # #release still answer. The engine hands the object back, where it
    # still holds it, as a new Ruby object.
    #
    # Its reference goes at once, as LÖVE's does, so an engine object
    # nothing else holds is freed then: a File is closed, and a texture's
    # memory let go. Inside a call that is still using the object, such as
    # a block that #perform_atomic yields to, it goes as soon as that call
    # returns.
    #
    # === Example
    #
    #   image = Lota::Image::ImageData.new(16, 16)
    #   image.release # => true
    #   image.release # => false
    #   image.width   # raises RuntimeError
    def release
      native.release
    end

    # LÖVE's name for the object, as __tostring writes it
    # (src/common/runtime.cpp, w__tostring): its type, a colon, and the
    # engine object's address, as LuaJIT writes a pointer, or +NULL+ once
    # it is released.
    #
    # === Example
    #
    #   Lota::Graphics::Canvas.new(16, 16).to_s # => "Texture: 0x0127c3a4f0"
    def to_s
      native.to_s
    end

    # Whether +other+ is this object, or an object of the same class
    # around the same engine object, matching __eq
    # (src/common/runtime.cpp, w__eq), which Lua asks only of two objects
    # of one type. Once either is released, only the object itself is
    # equal to it.
    #
    # === Example
    #
    #   world.bodies.first == body # => true
    def ==(other)
      equal?(other) || (other.is_a?(Object) && native == other.native)
    end
  end
end
