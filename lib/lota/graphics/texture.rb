# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # An image on the graphics card, matching LÖVE's Texture class
    # (src/modules/graphics/Texture.h).
    #
    # Whatever a game draws, it draws from a texture or into one. Pixels
    # in memory are slow to draw; a texture keeps them where the graphics
    # card can reach them at once.
    #
    # LÖVE 12 has one class for every texture, where LÖVE 11 had separate
    # Image and Canvas classes. Lota::Graphics::Canvas.new makes a texture
    # you can draw into, and canvas? says whether a texture is one.
    #
    # Use it to draw an image with Lota::Graphics.draw, to read rendered
    # pixels back with Lota::Graphics.readback_texture, and as the target
    # of Lota::Graphics.canvas=.
    #
    # === Examples
    #
    #   texture = Lota::Graphics::Canvas.new(16, 16)
    #   texture.class   # => Lota::Graphics::Texture
    #   texture.canvas? # => true
    #
    #   player = Lota::Graphics::Texture.new("assets/player.png")
    #   Lota::Graphics.draw(player, 100, 100)
    class Texture
      include Object

      # The engine's Texture, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a Texture the engine made. Every Texture the engine hands
      # to Ruby passes through here, and the same engine texture comes back
      # as the same Texture, as LÖVE pushes the same object for it, so
      # Lota::Graphics.canvas is the Texture Lota::Graphics.canvas= set.
      # :nodoc:
      def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        texture = allocate
        texture.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, texture)
        texture
      end

      # Makes a texture from an image, or of a size with no pixels yet,
      # matching love.graphics.newTexture
      # (src/modules/graphics/wrap_Graphics.cpp, w_newTexture and
      # getImageData).
      #
      # [image] String name of an image file in the game's folder, a
      #   Lota::Filesystem::FileData holding an encoded image, or a
      #   Lota::Image::ImageData; or an Array of them, the texture's
      #   mipmaps from the largest down.
      # [width] Integer width, in place of an image, for a texture with no
      #   pixels yet, followed by its Integer height and, for an array
      #   texture, its Integer layer count.
      # [settings] LÖVE's settings table, as keywords (ADR 001, rule 10):
      #   +canvas+, whether you can also draw into it; +mipmaps+, +true+
      #   for mipmaps you give, +false+, or +:none+, +:manual+, or
      #   +:auto+, which makes them as you draw; +mipmapcount+; +format+,
      #   a pixel format such as +:rgba8+; +linear+; +msaa+; +dpiscale+;
      #   +readable+; +computewrite+; +viewformats+, an Array of formats;
      #   +debugname+; and, given a size, +type+ (+:"2d"+, +:array+,
      #   +:cube+, or +:volume+), +width+, +height+, and +layers+. Any value
      #   but +nil+ of a flag counts by its truthiness, as LÖVE reads a flag
      #   in its table.
      #
      # LÖVE decodes a PNG, JPEG, BMP, TGA, or one of its other formats to
      # pixels, and keeps a compressed texture format, such as DDS or
      # ASTC, compressed. A file named like "image@2x.png" holds pixels at
      # twice the density, so the texture's DPI scale is 2 and it draws at
      # half its pixel size, as LÖVE parses the name, unless +dpiscale+
      # says otherwise. A file name is a path in the game's folder, as
      # Lota::Graphics::Font.new reads one.
      #
      # Raises ArgumentError for a setting or a value LÖVE does not know,
      # TypeError for anything else, RuntimeError with LÖVE's message when
      # the file cannot be read or decoded, the settings cannot make a
      # texture, the image or graphics module is not open, or no window is,
      # and ThreadError off the main thread.
      #
      # === Examples
      #
      #   ship = Lota::Graphics::Texture.new("assets/ship.png")
      #   ship.canvas? # => false
      #
      #   paint = Lota::Graphics::Texture.new("assets/wall.png", canvas: true, mipmaps: :auto)
      #   paint.mipmap_mode # => :auto
      #
      #   blank = Lota::Graphics::Texture.new(256, 256, format: :rgba16f)
      #
      # :call-seq:
      #   new(image, **settings)
      #   new(width, height, layers = nil, **settings)
      def self.new(*arguments, **settings)
        native = Native::TextureSettings.new
        image = arguments.first
        if TextureSettings.number?(image)
          TextureSettings.read_size(native, arguments, 2..3, "array")
          TextureSettings.read(native, settings, opt: true, check_type: true, check_dimensions: false)
          return from_native(Native::Graphics.new_empty_texture(native))
        end

        TextureSettings.check_count(arguments, 1..1)
        dpiscaleset = TextureSettings.read(native, settings, opt: true, check_type: false, check_dimensions: false)
        from_native(Native::Graphics.new_texture(native, dpiscaleset, TextureSettings.images(image)))
      end

      # Whether you can draw into this texture, matching Texture:isCanvas
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_isCanvas).
      #
      # A texture made by Lota::Graphics::Canvas.new always is. So
      # <tt>Lota::Graphics::Canvas === texture</tt> asks this, and a
      # +case+ can tell canvases from other textures.
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16).canvas? # => true
      def canvas?
        @native.canvas?
      end

      # The Integer width of the texture in pixels, in units of its DPI
      # scale, matching Texture:getWidth
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getWidth).
      #
      # [mipmap] Integer mipmap to measure, counting from 1; the first, the
      #   full-size image, when +nil+ or left out.
      #
      # Raises RuntimeError ("Invalid mipmap index: 2") for a mipmap the
      # texture does not have, TypeError for one that is not a number, and
      # ThreadError off the main thread.
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(64, 32).width # => 64
      def width(mipmap = nil)
        @native.width(mipmap)
      end

      # The Integer height of the texture, as width measures its width,
      # matching Texture:getHeight (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_getHeight).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(64, 32).height # => 32
      def height(mipmap = nil)
        @native.height(mipmap)
      end

      # The texture's width and height, as width and height measure them,
      # as an Array (ADR 001, rule 4), matching Texture:getDimensions
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getDimensions).
      #
      # === Example
      #
      #   width, height = Lota::Graphics::Canvas.new(64, 32).dimensions # => [64, 32]
      def dimensions(mipmap = nil)
        [@native.width(mipmap), @native.height(mipmap)]
      end

      # The Integer depth of a volume texture, in layers, at +mipmap+, as
      # width measures it, and 1 for any other texture, matching
      # Texture:getDepth (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_getDepth).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(64, 32).depth # => 1
      def depth(mipmap = nil)
        @native.depth(mipmap)
      end

      # The Integer number of layers of an array texture, and 1 for a 2D
      # texture, matching Texture:getLayerCount
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getLayerCount).
      #
      # === Example
      #
      #   Lota::Graphics::ArrayImage.new(%w[a.png b.png]).layer_count # => 2
      def layer_count
        @native.layer_count
      end

      # The Integer number of mipmaps the texture has, 1 without any,
      # matching Texture:getMipmapCount
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getMipmapCount).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(64, 64, mipmaps: :auto).mipmap_count # => 7
      def mipmap_count
        @native.mipmap_count
      end

      # The Integer width of the texture in pixels, whatever its DPI scale,
      # at +mipmap+, as width measures it, matching Texture:getPixelWidth
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getPixelWidth).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(64, 32, dpiscale: 2).pixel_width # => 128
      def pixel_width(mipmap = nil)
        @native.pixel_width(mipmap)
      end

      # The Integer height of the texture in pixels, as pixel_width
      # measures its width, matching Texture:getPixelHeight
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getPixelHeight).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(64, 32, dpiscale: 2).pixel_height # => 64
      def pixel_height(mipmap = nil)
        @native.pixel_height(mipmap)
      end

      # The texture's pixel_width and pixel_height as an Array (ADR 001,
      # rule 4), matching Texture:getPixelDimensions
      # (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_getPixelDimensions).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(64, 32).pixel_dimensions # => [64, 32]
      def pixel_dimensions(mipmap = nil)
        [@native.pixel_width(mipmap), @native.pixel_height(mipmap)]
      end

      # The Float DPI scale the texture was made with, matching
      # Texture:getDPIScale (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_getDPIScale).
      #
      # === Example
      #
      #   Lota::Graphics::Texture.new("assets/ship@2x.png").dpi_scale # => 2.0
      def dpi_scale
        @native.dpi_scale
      end

      # The texture's type, +:"2d"+, +:array+, +:cube+, or +:volume+,
      # matching Texture:getTextureType
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getTextureType).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16).texture_type # => :"2d"
      def texture_type
        @native.texture_type.to_sym
      end

      # The texture's pixel format, as a Symbol such as +:rgba8+, matching
      # Texture:getFormat (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_getFormat).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16, format: :rgba16f).format # => :rgba16f
      def format
        @native.format.to_sym
      end

      # Whether the texture's pixels are linear, not sRGB, matching
      # Texture:isFormatLinear (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_isFormatLinear).
      #
      # === Example
      #
      #   Lota::Graphics::Texture.new("assets/ship.png").format_linear? # => false
      def format_linear?
        @native.format_linear?
      end

      # Whether the texture's pixels are in a compressed format, such as
      # DXT1, matching Texture:isCompressed
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_isCompressed).
      #
      # === Example
      #
      #   Lota::Graphics::Texture.new("assets/ship.dds").compressed? # => true
      def compressed?
        @native.compressed?
      end

      # Whether a compute shader can write to the texture, matching
      # Texture:isComputeWritable (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_isComputeWritable).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16).compute_writable? # => false
      def compute_writable?
        @native.compute_writable?
      end

      # Whether Lota::Graphics.readback_texture can read the texture,
      # matching Texture:isReadable (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_isReadable).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16).readable? # => true
      def readable?
        @native.readable?
      end

      # The Integer number of antialiasing samples the texture has, 1
      # without any, matching Texture:getMSAA
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getMSAA).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16, msaa: 4).msaa # => 4
      def msaa
        @native.msaa
      end

      # How the texture makes its mipmaps, +:none+, +:manual+, or +:auto+,
      # matching Texture:getMipmapMode
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getMipmapMode).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16, mipmaps: :auto).mipmap_mode # => :auto
      def mipmap_mode
        @native.mipmap_mode.to_sym
      end

      # The name the texture was given with the +debugname+ setting, or
      # +nil+, matching Texture:getDebugName
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getDebugName).
      #
      # === Example
      #
      #   Lota::Graphics::Canvas.new(16, 16, debugname: "shadows").debug_name # => "shadows"
      def debug_name
        @native.debug_name
      end

      # Sets how the texture is filtered when drawn smaller and larger,
      # matching Texture:setFilter (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_setFilter), as Lota::Graphics.default_filter= takes it:
      # the filter when drawn smaller, +:linear+ or +:nearest+, alone or in
      # an Array with the filter when drawn larger (the first by default)
      # and the Integer maximum anisotropy (1 by default).
      #
      # A texture starts with Lota::Graphics.default_filter. LÖVE clamps
      # the anisotropy to 1 through 255, and the graphics card to what it
      # supports, and so does Lota. Raises ArgumentError for an unknown
      # filter, RuntimeError with LÖVE's message when the engine refuses
      # it, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   card.filter = :linear
      #   card.filter = :linear, :nearest, 4
      def filter=(filter)
        min, mag, anisotropy = filter.is_a?(Array) ? filter : [filter]
        anisotropy = case anisotropy
        when Integer, Float then anisotropy
        when nil then 1
        else raise TypeError, "wrong argument type #{anisotropy.class} for anisotropy (expected Integer)"
        end
        @native.set_filter(EnumName.of(min), mag && EnumName.of(mag), anisotropy)
      end

      # The filters when drawn smaller and larger, as Symbols, and the
      # Integer maximum anisotropy, as an Array (ADR 001, rule 4), matching
      # Texture:getFilter (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_getFilter).
      #
      # === Example
      #
      #   min, mag, anisotropy = card.filter # => [:nearest, :nearest, 1]
      def filter
        min, mag, anisotropy = @native.filter
        [min.to_sym, mag.to_sym, anisotropy]
      end

      # Sets how the texture blends between its mipmaps, matching
      # Texture:setMipmapFilter (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_setMipmapFilter): +:linear+ or +:nearest+, alone or in an
      # Array with the Float sharpness (0 by default), or +nil+ to stop
      # using its mipmaps.
      #
      # A texture drawn smaller than its size samples the mipmap nearest
      # that size, so it does not shimmer as it would sampling the full
      # image. A higher sharpness picks a larger mipmap, as LÖVE negates it
      # into the engine's level-of-detail bias. Raises ArgumentError for an
      # unknown filter, RuntimeError with LÖVE's message when the engine
      # refuses it, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   card.mipmap_filter = :linear
      #   card.mipmap_filter = :nearest, 0.5
      #   card.mipmap_filter = nil
      def mipmap_filter=(filter)
        mode, sharpness = filter.is_a?(Array) ? filter : [filter]
        sharpness = case sharpness
        when Integer, Float then sharpness
        when nil then 0
        else raise TypeError, "wrong argument type #{sharpness.class} for sharpness (expected Float)"
        end
        @native.set_mipmap_filter(mode && EnumName.of(mode), sharpness)
      end

      # The mipmap filter, as a Symbol, +:none+ when the texture does not
      # use its mipmaps, and the Float sharpness, as an Array (ADR 001,
      # rule 4), matching Texture:getMipmapFilter
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getMipmapFilter).
      #
      # === Example
      #
      #   mode, sharpness = card.mipmap_filter # => [:linear, 0.0]
      def mipmap_filter
        mode, sharpness = @native.mipmap_filter
        [mode.is_a?(String) ? mode.to_sym : nil, sharpness.to_f]
      end

      # Sets how the texture repeats past its edges, matching
      # Texture:setWrap (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_setWrap): +:clamp+, +:repeat+, +:mirroredrepeat+, or
      # +:clampzero+ horizontally, alone or in an Array with the mode
      # vertically and in depth (each the first by default).
      #
      # It shows when a quad or a mesh reaches past the texture. Raises
      # ArgumentError for an unknown mode, RuntimeError with LÖVE's message
      # when the engine refuses it, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   tiles.wrap = :repeat
      #   tiles.wrap = :repeat, :clamp
      def wrap=(wrap)
        horizontal, vertical, depth = wrap.is_a?(Array) ? wrap : [wrap]
        @native.set_wrap(EnumName.of(horizontal), vertical && EnumName.of(vertical), depth && EnumName.of(depth))
      end

      # How the texture repeats horizontally, vertically, and in depth, as
      # Symbols in an Array (ADR 001, rule 4), matching Texture:getWrap
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_getWrap).
      #
      # === Example
      #
      #   horizontal, vertical = tiles.wrap # => [:clamp, :clamp, :clamp]
      def wrap
        @native.wrap.map(&:to_sym)
      end

      # Sets how a shader compares the depth texture's values when it
      # samples them, matching Texture:setDepthSampleMode
      # (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_setDepthSampleMode): a compare mode such as +:less+ or
      # +:equal+, or +nil+ to read the values as they are.
      #
      # Raises ArgumentError for an unknown mode, RuntimeError with LÖVE's
      # message when the texture holds no depth, and ThreadError off the
      # main thread.
      #
      # === Example
      #
      #   shadow_map.depth_sample_mode = :lequal
      def depth_sample_mode=(mode)
        @native.set_depth_sample_mode(mode && EnumName.of(mode))
      end

      # The compare mode depth_sample_mode= set, as a Symbol, or +nil+,
      # matching Texture:getDepthSampleMode
      # (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_getDepthSampleMode).
      #
      # === Example
      #
      #   shadow_map.depth_sample_mode # => nil
      def depth_sample_mode
        @native.depth_sample_mode&.to_sym
      end

      # Makes the texture's mipmaps again from its full-size image,
      # matching Texture:generateMipmaps
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_generateMipmaps).
      #
      # A texture with mipmaps +:auto+ makes them each time it is drawn
      # into; one with +:manual+ makes them only when asked. Returns +nil+.
      # Raises RuntimeError with LÖVE's message for a texture without
      # mipmaps, and ThreadError off the main thread.
      #
      # === Example
      #
      #   table_canvas = Lota::Graphics::Canvas.new(1024, 1024, mipmaps: :manual)
      #   table_canvas.render_to { draw_cards }
      #   table_canvas.generate_mipmaps
      def generate_mipmaps
        @native.generate_mipmaps
      end

      # Replaces pixels of the texture with an ImageData's, matching
      # Texture:replacePixels (src/modules/graphics/wrap_Texture.cpp,
      # w_Texture_replacePixels).
      #
      # [imagedata] Lota::Image::ImageData of the new pixels, in the
      #   texture's format.
      # [slice] Integer slice to replace, counting from 1, for a texture
      #   that is not 2D; a 2D texture ignores it.
      # [mipmap] Integer mipmap to replace, counting from 1; the first by
      #   default.
      # [x] Integer left edge to replace from, in pixels; 0 by default,
      #   with +y+.
      # [y] Integer top edge to replace from.
      # [reloadmipmaps] Whether a texture with mipmaps +:auto+ makes them
      #   again, which it does unless told +false+ with a position.
      #
      # LÖVE also replaces pixels with a CompressedImageData, which Lota
      # binds with love.image's compressed data. Returns +nil+. Raises
      # RuntimeError with LÖVE's message when the pixels do not fit, or
      # their format is not the texture's, and ThreadError off the main
      # thread.
      #
      # === Example
      #
      #   icon.replace_pixels(Lota::Image::ImageData.new("assets/icon-lit.png"))
      def replace_pixels(imagedata, slice = nil, mipmap = nil, x = nil, y = nil, reloadmipmaps = nil)
        unless imagedata.is_a?(Lota::Image::ImageData)
          raise TypeError, "wrong argument type #{imagedata.class} (expected Lota::Image::ImageData)"
        end

        @native.replace_pixels(imagedata.native, [slice, mipmap, x, y, reloadmipmaps])
        nil
      end

      # Draws to this canvas while the block runs, then draws where it drew
      # before, matching Texture:renderTo
      # (src/modules/graphics/wrap_Texture.cpp, w_Texture_renderTo), whose
      # function becomes the block (ADR 001, rule 12).
      #
      # [slice] Integer slice to draw to, counting from 1, for a texture
      #   that is not 2D; a 2D texture takes none.
      #
      # Every canvas and depth buffer set before comes back after the
      # block, also when the block raises, and what it raised is raised
      # again. Returns +nil+. Raises ArgumentError without a block, and
      # ThreadError off the main thread.
      #
      # === Example
      #
      #   background = Lota::Graphics::Canvas.new(640, 480)
      #   background.render_to do
      #     Lota::Graphics.rectangle(:fill, 10, 10, 44, 44)
      #   end
      def render_to(slice = nil, &block)
        raise ArgumentError, "no block given" unless block

        @native.render_to(slice, block)
        nil
      end
    end
  end
end
