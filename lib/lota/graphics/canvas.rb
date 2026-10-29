# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Makes a Lota::Graphics::Texture you can draw into, as LÖVE 12's
    # love.graphics.newCanvas makes a Texture, and matches the textures it
    # makes.
    #
    # Drawing normally goes straight to the window and is gone by the next
    # frame. Effects such as lighting, a minimap, or a screen-wide shader
    # need a picture they can draw once, keep, and use again.
    #
    # A canvas is that picture. LÖVE 12 has no Canvas class: a canvas is a
    # Texture made to be drawn into. So Canvas is a module, not a class.
    # Canvas.new returns a Texture, and <tt>Canvas === texture</tt> is
    # true for a texture you can draw into, so <tt>when Canvas</tt> works
    # in a +case+.
    #
    # Use it to render off-screen, to build an image once and reuse it,
    # and to read rendered pixels back with Lota::Graphics.readback_texture.
    #
    # === Examples
    #
    #   # A canvas the size of the window.
    #   canvas = Lota::Graphics::Canvas.new
    #
    #   # A 16 by 16 canvas, cleared to yellow.
    #   canvas = Lota::Graphics::Canvas.new(16, 16)
    #   Lota::Graphics.canvas = canvas
    #   Lota::Graphics.clear(1, 1, 0, 1)
    #   Lota::Graphics.canvas = nil
    #
    #   # Telling canvases from other textures.
    #   case texture
    #   when Lota::Graphics::Canvas then draw_into(texture)
    #   end
    module Canvas
      # Creates a Lota::Graphics::Texture to draw into, matching
      # love.graphics.newCanvas (src/modules/graphics/wrap_Graphics.cpp,
      # w_newCanvas and luax_checktexturesettings).
      #
      # [width] Integer width, in units of the screen's DPI scale; the
      #   window's width when +nil+ or left out.
      # [height] Integer height, likewise; the window's height when +nil+
      #   or left out.
      # [layers] Integer layer count, which makes an array texture; a 2D
      #   texture when left out.
      # [settings] LÖVE's settings table, as keywords (ADR 001, rule 10),
      #   as Lota::Graphics::Texture.new takes them, with +type+, +width+,
      #   +height+, and +layers+ among them: +msaa+, the antialiasing
      #   samples per pixel, which smooth the edges of shapes; +mipmaps+,
      #   +:auto+ to make the mipmaps a canvas drawn smaller needs each
      #   time it is drawn into, or +:manual+; +format+, such as +:depth24+
      #   for a depth buffer; +readable+; +dpiscale+; and +debugname+.
      #   Given settings and no size, the settings must hold the +width+
      #   and +height+, as LÖVE's table form does.
      #
      # The texture takes the screen's DPI scale unless +dpiscale+ says
      # otherwise, so on a high-density display it has more pixels than its
      # width and height say. It starts out transparent black
      # (src/modules/graphics/metal/Texture.mm and opengl/Texture.cpp clear
      # every new canvas). LÖVE reads a number setting, such as +msaa+, as
      # it reads a number in its table, so a value that is not a number
      # leaves the default, and the graphics card may use fewer samples
      # than asked for. The +canvas+ setting is always true.
      #
      # Raises ArgumentError for a setting or a value LÖVE does not know,
      # TypeError for a size that is not a number, RuntimeError when no
      # window is open or the settings cannot make a canvas, and
      # ThreadError off the main thread.
      #
      # === Examples
      #
      #   minimap = Lota::Graphics::Canvas.new(128, 128)
      #   minimap.class # => Lota::Graphics::Texture
      #
      #   smooth = Lota::Graphics::Canvas.new(800, 600, msaa: 4)
      #   table = Lota::Graphics::Canvas.new(2048, 2048, mipmaps: :auto)
      #   layers = Lota::Graphics::Canvas.new(type: :array, width: 64, height: 64, layers: 4)
      #
      # :call-seq:
      #   new(width = nil, height = nil, layers = nil, **settings)
      #   new(width:, height:, **settings)
      def self.new(*arguments, **settings)
        native = Native::TextureSettings.new
        if arguments.empty? && !settings.empty?
          dpiscaleset = TextureSettings.read(native, settings, opt: false, check_type: true, check_dimensions: true,
            canvas: true)
          return Texture.from_native(Native::Graphics.new_canvas(native, dpiscaleset))
        end

        TextureSettings.check_count(arguments, 0..3)
        width, height, layers = arguments
        size = Native::Graphics.canvas_size if width.nil? || height.nil?
        native.width = optional_integer(width, size&.first, "width")
        native.height = optional_integer(height, size&.last, "height")
        unless layers.nil?
          native.layers = TextureSettings.size(layers, "layers")
          native.set_type("array")
        end
        dpiscaleset = TextureSettings.read(native, settings, opt: true, check_type: true, check_dimensions: false,
          canvas: true)
        Texture.from_native(Native::Graphics.new_canvas(native, dpiscaleset))
      end

      # luaL_optinteger: +default+ when nil, the number otherwise.
      private_class_method def self.optional_integer(value, default, name)
        return default.to_i if value.nil?

        TextureSettings.size(value, name)
      end

      # Whether +object+ is a Lota::Graphics::Texture you can draw into,
      # as Texture#canvas? says, however you got it. Anything else is not
      # a canvas.
      #
      # === Example
      #
      #   Lota::Graphics::Canvas === Lota::Graphics::Canvas.new(16, 16) # => true
      #   Lota::Graphics::Canvas === :canvas                           # => false
      def self.===(object)
        case object
        when Texture then object.canvas?
        else false
        end
      end
    end
  end
end
