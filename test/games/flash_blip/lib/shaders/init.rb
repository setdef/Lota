# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2017 Matthias Richter
# SPDX-License-Identifier: MIT
#
# The MIT License (MIT)
#
# Copyright (c) 2017 Matthias Richter
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Translated to Ruby from moonshine's init.lua, as FLASH-BLIP carries it
# (test/fixtures/flash_blip/game/lib/shaders/init.lua, lines 1-171), by
# the rules of doc/contributors/design/translation.md: newCanvas becomes
# Lota::Graphics::Canvas.new (rules 2 and 25), the getters drop get and
# return Arrays (rules 3 and 4), and the setters become writers (rules 5
# and 6), with the blend modes symbols (rule 9).
#
# Lua builds moonshine's objects from tables and metatables, which Ruby
# has no meaning for, so they are classes. The module is Moonshine, and
# calling it, moonshine(effect), is Moonshine.call(effect), the same as
# Moonshine.chain(effect). A chain is a Moonshine::Chain: calling it with
# the function that draws the scene, chain(func), is chain.call { ... }
# (rule 12); chain.next and chain.chain add an effect and return the
# chain; chain.glow, the effect named glow, is what Lua's __index finds;
# and chain.parameters = { "glow" => { "strength" => 5 } } is what Lua's
# __newindex does with a table of parameters. An effect is a
# Moonshine::Effect, made by moonshine::Effect.new where Lua calls
# moonshine.Effect, and a property written to it, effect.strength = 5,
# calls its setter, as Lua's __newindex does. Moonshine.effects.glow is the
# constructor Lua's autoloading finds: each effect's file registers the
# function it returns in Moonshine.effect_modules under its name, as Lua's
# require hands back what a module returns.

module Moonshine
  class << self
    # The effects' modules, by the name of the file each is in, as Lua's
    # package.loaded holds what each module returned.
    attr_reader :effect_modules
  end

  @effect_modules = {}

  def self.draw_shader(buffer, shader)
    front, back = buffer.call
    Lota::Graphics.canvas = front
    Lota::Graphics.clear
    Lota::Graphics.shader = shader if shader != Lota::Graphics.shader
    Lota::Graphics.draw(back)
  end

  def self.chain(w, h = nil, effect = nil)
    # called as moonshine.chain(effect)'
    if h.nil?
      effect = w
      w, h, = Lota::Window.mode
    end
    raise "No effect" if effect.nil?

    Chain.new(w, h).next(effect)
  end

  # moonshine(...), Lua's __call on the module.
  def self.call(...)
    chain(...)
  end

  # A chain of effects, what moonshine.chain returns.
  class Chain
    def initialize(w, h)
      @front = Lota::Graphics::Canvas.new(w, h)
      @back = Lota::Graphics::Canvas.new(w, h)
      @buffer = lambda do
        @back, @front = @front, @back
        [@front, @back]
      end

      @disabled = {} # set of disabled effects
      @effects = []
      @fields = {}
    end

    def resize(w, h)
      @front = Lota::Graphics::Canvas.new(w, h)
      @back = Lota::Graphics::Canvas.new(w, h)
      self
    end

    def draw(*, &func)
      # save state
      canvas, = Lota::Graphics.canvas
      shader = Lota::Graphics.shader
      fg = Lota::Graphics.color

      # draw scene to front buffer
      Lota::Graphics.canvas = @buffer.call.first # take only front buffer
      Lota::Graphics.clear(*Lota::Graphics.background_color)
      func.call(*)

      # save more state
      blendmode, = Lota::Graphics.blend_mode

      # process all shaders
      Lota::Graphics.color = fg
      Lota::Graphics.blend_mode = :alpha, :premultiplied
      @effects.each do |e|
        (e.draw || Moonshine.method(:draw_shader)).call(@buffer, e.shader) unless @disabled[e.name]
      end

      # present result
      Lota::Graphics.shader = nil
      Lota::Graphics.canvas = canvas
      Lota::Graphics.draw(@front, 0, 0)

      # restore state
      Lota::Graphics.blend_mode = blendmode
      Lota::Graphics.shader = shader
    end

    # chain(func, ...), Lua's __call on a chain.
    def call(*, &)
      draw(*, &)
    end

    def next(e)
      e = e.call if e.is_a?(Proc)
      raise "Invalid effect: must provide `name'." unless e.name
      raise "Invalid effect: must provide `shader' or `draw'." unless e.shader || e.draw

      @effects << e
      self
    end
    alias chain next

    def disable(*names)
      names.each { |name| @disabled[name] = name }
      nil
    end

    def enable(*names)
      names.each { |name| @disabled.delete(name) }
      nil
    end

    # Lua's __newindex for the keys it treats as a table of parameters,
    # each effect's name mapped to its properties' names and values.
    def parameters=(parameters)
      # Lua visits these in pairs' order; each setter sets its own effect's property, so the
      # order cannot change what is drawn.
      parameters.each do |e, par|
        par.each do |k, v|
          effect(e).public_send(:"#{k}=", v)
        end
      end
    end
    alias params= parameters=
    alias settings= parameters=

    # The effect in the chain named +name+, as Lua's __index finds it.
    def effect(name)
      key = name.to_s
      return @fields[key] if @fields.key?(key)

      @effects.each do |e|
        return e if e.name == key
      end
      raise "Effect `#{key}' not in chain"
    end

    def method_missing(name, *args)
      key = name.to_s
      if key.end_with?("=") && args.size == 1
        # rawset(chain, k, v)
        @fields[key.chomp("=")] = args.first
      elsif args.empty? && !key.end_with?("=", "?", "!")
        effect(key)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      key = name.to_s
      key.end_with?("=") || @fields.key?(key) || @effects.any? { |e| e.name == key } || super
    end
  end

  # An effect, what moonshine.Effect returns: its name, its shader or the
  # function that draws it, and the setters its properties are written
  # through.
  class Effect
    attr_reader :name, :draw, :shader, :setters, :defaults

    def initialize(name:, setters:, draw: nil, shader: nil, defaults: nil)
      @name = name
      @draw = draw
      @shader = shader
      @setters = setters
      @defaults = defaults

      # set defaults
      # Lua visits these in pairs' order; each default sets a property of its own, so the order
      # cannot change what is drawn. Lua calls each setter twice, once
      # through the assert that checks it exists, and also passes the
      # property's name, which no setter reads.
      (defaults || {}).each do |k, v|
        raise "No setter for parameter `#{k}'" unless setters[k]

        setters[k].call(v)
        setters[k].call(v)
      end
    end

    # expose setters
    def method_missing(name, *args)
      key = name.to_s
      return super unless key.end_with?("=") && args.size == 1

      k = key.chomp("=")
      raise "Unknown property: `#{@name}.#{k}'" unless setters[k]

      setters[k].call(args.first)
    end

    def respond_to_missing?(name, include_private = false)
      name.to_s.end_with?("=") || super
    end
  end

  # autoloading effects
  class Effects
    def initialize(moonshine)
      @moonshine = moonshine
      @cache = {}
    end

    # The constructor of the effect named +key+.
    def [](key)
      key = key.to_s
      @cache.fetch(key) do
        begin
          require "lib/shaders/#{key}"
        rescue LoadError
          raise "No such effect: #{key}"
        end
        effect = @moonshine.effect_modules.fetch(key)

        # expose moonshine to effect
        con = -> (*args) { effect.call(@moonshine, *args) }

        # cache effect constructor
        @cache[key] = con
      end
    end

    def method_missing(name, *args)
      return super unless args.empty? && name.match?(/\A[a-z_][a-z0-9_]*\z/i)

      self[name]
    end

    def respond_to_missing?(name, include_private = false)
      name.match?(/\A[a-z_][a-z0-9_]*\z/i) || super
    end
  end

  @effects = Effects.new(self)

  class << self
    attr_reader :effects
  end
end
# SPDX-SnippetEnd
