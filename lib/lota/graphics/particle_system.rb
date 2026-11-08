# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Particles that an emitter makes, moves, fades, and draws, matching
    # LÖVE's ParticleSystem class (src/modules/graphics/ParticleSystem.h).
    #
    # Smoke, sparks, rain, and magic are many small sprites that share
    # their rules: where they start, how fast they go, how long they live,
    # and how they change as they age. A particle system keeps those
    # rules and every particle, and draws all of them in one call.
    # Set its rules, #start it, #update it every frame with the time that
    # passed, and draw it with Lota::Graphics.draw.
    #
    # Its angles are in radians. A pair of numbers, such as #speed,
    # is the least and the most a particle may start with, and a single
    # number sets both.
    #
    # === Example
    #
    #   spark = Lota::Graphics::Image.new("assets/spark.png")
    #   fire = Lota::Graphics::ParticleSystem.new(spark, 500)
    #   fire.particle_lifetime = 0.5, 1.5
    #   fire.emission_rate = 100
    #   fire.speed = 20, 60
    #   fire.colors = 1, 0.8, 0.2, 1, 1, 0, 0, 0 # yellow fading to nothing
    #   fire.emission_area = :normal, 4, 2
    #
    #   def Lota.update(dt) = fire.update(dt)
    #   def Lota.draw = Lota::Graphics.draw(fire, 400, 500)
    class ParticleSystem < Object
      # Wraps a ParticleSystem the engine made. :nodoc:
      private_class_method def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        system = allocate
        system.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, system)
        system
      end

      # Makes a particle system, matching love.graphics.newParticleSystem
      # (src/modules/graphics/wrap_Graphics.cpp, w_newParticleSystem), named by ADR
      # 001, rule 2.
      #
      # [texture] Lota::Graphics::Texture each particle shows.
      # [size] Integer most particles alive at once, 1000 when +nil+ or left
      #   out.
      #
      # Raises TypeError for a texture that is not a Texture, RuntimeError with
      # LÖVE's message for a size under 1 or over the most the engine holds, or when
      # no window is open, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   Lota::Graphics::ParticleSystem.new(spark)
      #   Lota::Graphics::ParticleSystem.new(spark, 5000)
      def self.new(texture, size = nil)
        Native::Graphics.check_created
        raise TypeError, "wrong argument type #{texture.class} (expected Lota::Graphics::Texture)" unless texture.is_a?(Texture)

        from_native(Native::Graphics.new_particle_system(texture.__send__(:native), size))
      end

      # Makes this particle system a copy of +system+ by Ruby's +clone+ or +dup+,
      # matching ParticleSystem:clone (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_clone): a new one with the same rules and texture, which it
      # keeps apart from +system+'s (ADR 001, section 7).
      #
      # === Example
      #
      #   second = fire.clone
      #   second.position = 100, 0
      def initialize_copy(system)
        super
        @native = system.native.clone
        @native.instance_variable_set(:@lota, self)
      end

      # Sets the texture each particle shows, matching ParticleSystem:setTexture
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_setTexture).
      #
      # Raises TypeError for a texture that is not a Texture.
      #
      # === Example
      #
      #   fire.texture = flame
      def texture=(texture)
        raise TypeError, "wrong argument type #{texture.class} (expected Lota::Graphics::Texture)" unless texture.is_a?(Texture)

        @native.set_texture(texture.native)
      end

      # The Lota::Graphics::Texture each particle shows, matching
      # ParticleSystem:getTexture (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getTexture).
      #
      # === Example
      #
      #   fire.texture.width # => 16
      def texture
        Texture.__send__(:from_native, @native.texture)
      end

      # Sets the most particles alive at once, matching ParticleSystem:setBufferSize
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setBufferSize).
      #
      # [size] Integer from 1 to the most the engine holds.
      #
      # Raises RuntimeError with LÖVE's message for a size outside that.
      #
      # === Example
      #
      #   fire.buffer_size = 2000
      def buffer_size=(size)
        @native.set_buffer_size(size)
      end

      # The Integer most particles alive at once, matching
      # ParticleSystem:getBufferSize (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getBufferSize).
      #
      # === Example
      #
      #   fire.buffer_size # => 1000
      def buffer_size
        @native.buffer_size
      end

      # Sets where a new particle goes among the others, which decides which is
      # drawn on top, matching ParticleSystem:setInsertMode
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setInsertMode).
      #
      # [mode] +:top+ (the default), +:bottom+, or +:random+.
      #
      # Raises ArgumentError for an unknown mode.
      #
      # === Example
      #
      #   fire.insert_mode = :random
      def insert_mode=(mode)
        @native.set_insert_mode(EnumName.of(mode))
      end

      # Where a new particle goes among the others, a Symbol, matching
      # ParticleSystem:getInsertMode (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getInsertMode).
      #
      # === Example
      #
      #   fire.insert_mode # => :top
      def insert_mode
        @native.insert_mode.to_sym
      end

      # Sets how many particles are made each second, matching
      # ParticleSystem:setEmissionRate
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setEmissionRate).
      #
      # [rate] Float or Integer particles a second.
      #
      # === Example
      #
      #   fire.emission_rate = 100
      def emission_rate=(rate)
        @native.set_emission_rate(rate)
      end

      # The Float particles made each second, matching
      # ParticleSystem:getEmissionRate
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getEmissionRate).
      #
      # === Example
      #
      #   fire.emission_rate # => 0.0
      def emission_rate
        @native.emission_rate
      end

      # Sets how many seconds the emitter makes particles for after it starts,
      # matching ParticleSystem:setEmitterLifetime
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setEmitterLifetime).
      #
      # [lifetime] Float or Integer seconds; -1 makes particles forever.
      #
      # === Example
      #
      #   fire.emitter_lifetime = 10
      def emitter_lifetime=(lifetime)
        @native.set_emitter_lifetime(lifetime)
      end

      # The Float seconds the emitter makes particles for, -1 for ever, matching
      # ParticleSystem:getEmitterLifetime
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getEmitterLifetime).
      #
      # === Example
      #
      #   fire.emitter_lifetime # => -1.0
      def emitter_lifetime
        @native.emitter_lifetime
      end

      # Sets how long a particle lives, matching ParticleSystem:setParticleLifetime
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setParticleLifetime).
      #
      # [lifetime] The least and the most Float or Integer seconds, as two values or
      #   an Array; one value sets both. A particle has no life, and so none are
      #   counted, until this is set.
      #
      # Raises RuntimeError with LÖVE's message for a negative lifetime.
      #
      # === Example
      #
      #   fire.particle_lifetime = 1, 2
      def particle_lifetime=(lifetime)
        min, max = range(lifetime)
        @native.set_particle_lifetime(min, max)
      end

      # The least and the most seconds a particle lives, as an Array, matching
      # ParticleSystem:getParticleLifetime
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getParticleLifetime).
      #
      # === Example
      #
      #   least, most = fire.particle_lifetime
      def particle_lifetime
        @native.particle_lifetime
      end

      # Moves the emitter, and leaves the particles where they are, matching
      # ParticleSystem:setPosition (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setPosition).
      #
      # [position] The Float or Integer x and y, as two values or an Array.
      #
      # === Example
      #
      #   fire.position = 100, 200
      def position=(position)
        x, y = pair(position)
        @native.set_position(x, y)
      end

      # Where the emitter is, as an Array of x and y, matching
      # ParticleSystem:getPosition (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getPosition).
      #
      # === Example
      #
      #   x, y = fire.position
      def position
        @native.position
      end

      # Moves the emitter, and the particles with it, matching ParticleSystem:moveTo
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_moveTo).
      #
      # [x] Float or Integer new x.
      # [y] Float or Integer new y.
      #
      # === Example
      #
      #   fire.move_to(100, 200)
      def move_to(x, y)
        @native.move_to(x, y)
      end

      # Sets the shape particles start in around the emitter, matching
      # ParticleSystem:setEmissionArea
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setEmissionArea).
      #
      # [area] The distribution, a Symbol, then its Float or Integer x and y
      #   extents, then optionally the angle its particles face and whether they
      #   face away from the emitter's center, as an Array. The distributions are
      #   +:uniform+, +:normal+, +:ellipse+, +:borderellipse+, +:borderrectangle+,
      #   and +:none+, which needs no extents; +nil+ is +:none+.
      #
      # Raises ArgumentError for an unknown distribution, and RuntimeError with
      # LÖVE's message for a negative extent.
      #
      # === Examples
      #
      #   fire.emission_area = :normal, 4, 2
      #   fire.emission_area = :borderellipse, 8, 8, 0, true
      #   fire.emission_area = :none
      def emission_area=(area)
        values = area.is_a?(Array) ? area : [area]
        distribution = values[0]
        @native.set_emission_area(distribution.nil? ? nil : EnumName.of(distribution), number(values[1]),
          number(values[2]), number(values[3]) || 0.0, values[4] == true)
      end

      # The shape particles start in, as an Array of the distribution (a Symbol),
      # its x and y extents, the angle, and whether particles face away from the
      # center, matching ParticleSystem:getEmissionArea
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getEmissionArea).
      #
      # === Example
      #
      #   distribution, dx, dy, angle, relative = fire.emission_area
      def emission_area
        distribution, *rest = @native.emission_area
        [distribution.to_sym, *rest]
      end

      # Sets the direction particles go in, in radians, matching
      # ParticleSystem:setDirection (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setDirection).
      #
      # [direction] Float or Integer angle, 0 to the right and a quarter turn down.
      #
      # === Example
      #
      #   fire.direction = -Math::PI / 2 # up
      def direction=(direction)
        @native.set_direction(direction)
      end

      # The Float direction particles go in, in radians, matching
      # ParticleSystem:getDirection (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getDirection).
      #
      # === Example
      #
      #   fire.direction # => 0.0
      def direction
        @native.direction
      end

      # Sets how far from the direction particles may go, in radians, matching
      # ParticleSystem:setSpread (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setSpread).
      #
      # [spread] Float or Integer angle the direction may vary by in either way.
      #
      # === Example
      #
      #   fire.spread = Math::PI / 4
      def spread=(spread)
        @native.set_spread(spread)
      end

      # The Float spread, in radians, matching ParticleSystem:getSpread
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_getSpread).
      #
      # === Example
      #
      #   fire.spread # => 0.0
      def spread
        @native.spread
      end

      # Sets how fast particles start, matching ParticleSystem:setSpeed
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_setSpeed).
      #
      # [speed] The least and the most Float or Integer, as two values or an Array;
      #   one value sets both.
      #
      # === Example
      #
      #   fire.speed = 20, 60
      def speed=(speed)
        min, max = range(speed)
        @native.set_speed(min, max)
      end

      # The least and the most speed a particle starts with, as an Array, matching
      # ParticleSystem:getSpeed (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getSpeed).
      #
      # === Example
      #
      #   least, most = fire.speed
      def speed
        @native.speed
      end

      # Sets the acceleration along the x and y axes, matching
      # ParticleSystem:setLinearAcceleration
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setLinearAcceleration).
      #
      # [acceleration] The least x and y, then optionally the most x and y, each a
      #   Float or Integer, as several values or an Array; the most are the least
      #   when left out.
      #
      # === Example
      #
      #   fire.linear_acceleration = 0, -20, 0, -60
      def linear_acceleration=(acceleration)
        values = acceleration.is_a?(Array) ? acceleration : [acceleration]
        unless values.size.between?(2, 4)
          raise ArgumentError, "wrong number of arguments (given #{values.size}, expected 2..4)"
        end

        @native.set_linear_acceleration(values.fetch(0), values.fetch(1), values[2], values[3])
      end

      # The least x and y and the most x and y acceleration, as an Array, matching
      # ParticleSystem:getLinearAcceleration
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getLinearAcceleration).
      #
      # === Example
      #
      #   min_x, min_y, max_x, max_y = fire.linear_acceleration
      def linear_acceleration
        @native.linear_acceleration
      end

      # Sets the acceleration toward or away from the emitter, matching
      # ParticleSystem:setRadialAcceleration
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setRadialAcceleration).
      #
      # [acceleration] The least and the most Float or Integer, as two values or an
      #   Array; one value sets both.
      #
      # === Example
      #
      #   fire.radial_acceleration = 10, 30
      def radial_acceleration=(acceleration)
        min, max = range(acceleration)
        @native.set_radial_acceleration(min, max)
      end

      # The least and the most radial acceleration, as an Array, matching
      # ParticleSystem:getRadialAcceleration
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getRadialAcceleration).
      #
      # === Example
      #
      #   least, most = fire.radial_acceleration
      def radial_acceleration
        @native.radial_acceleration
      end

      # Sets the acceleration at right angles to the direction away from the
      # emitter, matching ParticleSystem:setTangentialAcceleration
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setTangentialAcceleration).
      #
      # [acceleration] The least and the most Float or Integer, as two values or an
      #   Array; one value sets both.
      #
      # === Example
      #
      #   fire.tangential_acceleration = 10, 30
      def tangential_acceleration=(acceleration)
        min, max = range(acceleration)
        @native.set_tangential_acceleration(min, max)
      end

      # The least and the most tangential acceleration, as an Array, matching
      # ParticleSystem:getTangentialAcceleration
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getTangentialAcceleration).
      #
      # === Example
      #
      #   least, most = fire.tangential_acceleration
      def tangential_acceleration
        @native.tangential_acceleration
      end

      # Sets how fast particles slow down, matching ParticleSystem:setLinearDamping
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setLinearDamping).
      #
      # [damping] The least and the most Float or Integer, as two values or an
      #   Array; one value sets both.
      #
      # === Example
      #
      #   fire.linear_damping = 1, 2
      def linear_damping=(damping)
        min, max = range(damping)
        @native.set_linear_damping(min, max)
      end

      # The least and the most linear damping, as an Array, matching
      # ParticleSystem:getLinearDamping
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getLinearDamping).
      #
      # === Example
      #
      #   least, most = fire.linear_damping
      def linear_damping
        @native.linear_damping
      end

      # Sets the size of a particle through its life, matching
      # ParticleSystem:setSizes (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setSizes).
      #
      # [sizes] One to eight Float or Integer scales, as several values or an Array;
      #   a particle goes from the first to the last as it ages.
      #
      # Raises RuntimeError with LÖVE's message for more than eight, and TypeError
      # for a value that is not a number.
      #
      # === Example
      #
      #   fire.sizes = 1, 2, 4, 1
      def sizes=(sizes)
        @native.set_sizes(sizes.is_a?(Array) ? sizes : [sizes])
      end

      # The sizes of a particle through its life, as an Array, matching
      # ParticleSystem:getSizes (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getSizes).
      #
      # === Example
      #
      #   fire.sizes # => [1.0]
      def sizes
        @native.sizes
      end

      # Sets how much the size of each particle varies, from 0 to 1, matching
      # ParticleSystem:setSizeVariation
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setSizeVariation).
      #
      # [variation] Float or Integer from 0, no variation, to 1.
      #
      # Raises RuntimeError with LÖVE's message for a value outside that.
      #
      # === Example
      #
      #   fire.size_variation = 0.5
      def size_variation=(variation)
        @native.set_size_variation(variation)
      end

      # The Float size variation, matching ParticleSystem:getSizeVariation
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getSizeVariation).
      #
      # === Example
      #
      #   fire.size_variation # => 0.0
      def size_variation
        @native.size_variation
      end

      # Sets the angle particles start turned by, in radians, matching
      # ParticleSystem:setRotation (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setRotation).
      #
      # [rotation] The least and the most Float or Integer, as two values or an
      #   Array; one value sets both.
      #
      # === Example
      #
      #   fire.rotation = 0, Math::PI
      def rotation=(rotation)
        min, max = range(rotation)
        @native.set_rotation(min, max)
      end

      # The least and the most starting angle, as an Array, matching
      # ParticleSystem:getRotation (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getRotation).
      #
      # === Example
      #
      #   least, most = fire.rotation
      def rotation
        @native.rotation
      end

      # Sets how fast particles turn, in radians a second, matching
      # ParticleSystem:setSpin (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setSpin).
      #
      # [spin] The speed at the start and at the end of a particle's life, each a
      #   Float or Integer, as two values or an Array; one value sets both.
      #
      # === Example
      #
      #   fire.spin = 1, 2
      def spin=(spin)
        start, finish = range(spin)
        @native.set_spin(start, finish)
      end

      # The spin at the start and at the end of a particle's life, as an Array,
      # matching ParticleSystem:getSpin
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_getSpin).
      #
      # === Example
      #
      #   start, finish = fire.spin
      def spin
        @native.spin
      end

      # Sets how much the spin of each particle varies, from 0 to 1, matching
      # ParticleSystem:setSpinVariation
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setSpinVariation).
      #
      # [variation] Float or Integer from 0, no variation, to 1.
      #
      # === Example
      #
      #   fire.spin_variation = 1
      def spin_variation=(variation)
        @native.set_spin_variation(variation)
      end

      # The Float spin variation, matching ParticleSystem:getSpinVariation
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getSpinVariation).
      #
      # === Example
      #
      #   fire.spin_variation # => 0.0
      def spin_variation
        @native.spin_variation
      end

      # Sets the point of each particle that turns and is placed, in pixels of the
      # texture, matching ParticleSystem:setOffset
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_setOffset).
      #
      # [offset] The Float or Integer x and y, as two values or an Array. It is the
      #   texture's center to begin with.
      #
      # === Example
      #
      #   fire.offset = 0, 10
      def offset=(offset)
        x, y = pair(offset)
        @native.set_offset(x, y)
      end

      # The offset of each particle, as an Array of x and y, matching
      # ParticleSystem:getOffset (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getOffset).
      #
      # === Example
      #
      #   x, y = fire.offset
      def offset
        @native.offset
      end

      # Sets the colors of a particle through its life, matching
      # ParticleSystem:setColors (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setColors).
      #
      # [colors] One to eight colors, each red, green, blue, and alpha from 0 to 1,
      #   as an Array of Arrays (alpha may be left out of those) or as the numbers
      #   of every color one after another; a particle fades from the first to the
      #   last as it ages.
      #
      # Raises RuntimeError with LÖVE's message for more than eight colors or a part
      # of one, and TypeError for a value that is not a number.
      #
      # === Examples
      #
      #   fire.colors = 1, 1, 1, 1, 1, 0, 0, 0
      #   fire.colors = [[1, 1, 1, 1], [1, 0, 0, 0]]
      def colors=(colors)
        values = colors.is_a?(Array) ? colors : [colors]
        @native.set_colors(values, values.first.is_a?(Array))
      end

      # The colors of a particle through its life, as an Array of Arrays of red,
      # green, blue, and alpha, matching ParticleSystem:getColors
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_getColors).
      #
      # === Example
      #
      #   fire.colors # => [[1.0, 1.0, 1.0, 1.0]]
      def colors
        @native.colors
      end

      # Sets the parts of the texture particles show, one for each particle in turn,
      # matching ParticleSystem:setQuads
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_setQuads).
      #
      # [quads] Lota::Graphics::Quad objects, as several values or an Array; none
      #   shows the whole texture.
      #
      # Raises TypeError for a quad that is not a Quad.
      #
      # === Example
      #
      #   fire.quads = flame_1, flame_2
      def quads=(quads)
        list = quads.is_a?(Array) ? quads : [quads]
        list.each do |quad|
          raise TypeError, "wrong argument type #{quad.class} (expected Lota::Graphics::Quad)" unless quad.is_a?(Quad)
        end
        natives = list.map do |quad|
          # A Symbol's proc calls only public methods, and native is protected.
          quad.native
        end
        @native.set_quads(natives)
      end

      # The Lota::Graphics::Quad objects particles show, as an Array, matching
      # ParticleSystem:getQuads (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_getQuads).
      #
      # === Example
      #
      #   fire.quads.size # => 2
      def quads
        @native.quads.map { |quad| Quad.__send__(:from_native, quad) }
      end

      # Sets whether a particle turns to face the way it moves, matching
      # ParticleSystem:setRelativeRotation
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_setRelativeRotation).
      #
      # [enable] true or false.
      #
      # === Example
      #
      #   fire.relative_rotation = true
      def relative_rotation=(enable)
        raise TypeError, "wrong argument type #{enable.class} (expected true or false)" unless enable == true || enable == false

        @native.set_relative_rotation(enable)
      end

      # Whether a particle turns to face the way it moves, matching
      # ParticleSystem:hasRelativeRotation
      # (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_hasRelativeRotation).
      #
      # === Example
      #
      #   fire.relative_rotation? # => false
      def relative_rotation?
        @native.relative_rotation?
      end

      # The Integer number of particles alive, matching ParticleSystem:getCount
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_getCount).
      #
      # === Example
      #
      #   fire.count # => 120
      def count
        @native.count
      end

      # Starts the emitter making particles, or lets a paused one go on, matching
      # ParticleSystem:start (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_start).
      #
      # === Example
      #
      #   fire.start
      def start
        @native.start
      end

      # Stops the emitter and resets it, and the particles die, matching
      # ParticleSystem:stop (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_stop).
      #
      # === Example
      #
      #   fire.stop
      def stop
        @native.stop
      end

      # Pauses the emitter and its particles, matching ParticleSystem:pause
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_pause).
      #
      # === Example
      #
      #   fire.pause
      def pause
        @native.pause
      end

      # Removes every particle and starts the emitter again, matching
      # ParticleSystem:reset (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_reset).
      #
      # === Example
      #
      #   fire.reset
      def reset
        @native.reset
      end

      # Makes particles at once, however many the buffer has room for, matching
      # ParticleSystem:emit (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_emit).
      #
      # [count] Integer number to make.
      #
      # === Example
      #
      #   fire.emit(10)
      def emit(count)
        @native.emit(count)
      end

      # Whether the emitter is making particles or particles are alive, matching
      # ParticleSystem:isActive (src/modules/graphics/wrap_ParticleSystem.cpp,
      # w_ParticleSystem_isActive).
      #
      # === Example
      #
      #   fire.active? # => true
      def active?
        @native.active?
      end

      # Whether the system is paused, matching ParticleSystem:isPaused
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_isPaused).
      #
      # === Example
      #
      #   fire.paused? # => false
      def paused?
        @native.paused?
      end

      # Whether the system is stopped, matching ParticleSystem:isStopped
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_isStopped).
      #
      # === Example
      #
      #   fire.stopped? # => false
      def stopped?
        @native.stopped?
      end

      # Moves the particles on and makes new ones, by the seconds that passed,
      # matching ParticleSystem:update
      # (src/modules/graphics/wrap_ParticleSystem.cpp, w_ParticleSystem_update).
      #
      # [dt] Float or Integer seconds, as Lota.update receives them.
      #
      # === Example
      #
      #   fire.update(dt)
      def update(dt)
        @native.update(dt)
      end

      # The least and the most a writer of a range takes, as two values or
      # an Array; one value is both. :nodoc:
      private def range(value)
        values = value.is_a?(Array) ? value : [value]
        raise ArgumentError, "wrong number of arguments (given #{values.size}, expected 1..2)" unless values.size.between?(1, 2)

        [values.fetch(0), values[1]]
      end

      # +value+ when it is a number or +nil+; TypeError for anything else.
      # :nodoc:
      private def number(value)
        case value
        when Float, Integer, nil then value
        else raise TypeError, "wrong argument type #{value.class} (expected Float)"
        end
      end

      # The two numbers of a writer that takes exactly two, as two values or
      # an Array. :nodoc:
      private def pair(value)
        values = value.is_a?(Array) ? value : [value]
        raise ArgumentError, "wrong number of arguments (given #{values.size}, expected 2)" unless values.size == 2

        [values.fetch(0), values.fetch(1)]
      end
    end
  end
end
