# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "graphics/texture_settings"
require_relative "graphics/texture"
require_relative "graphics/array_texture"
require_relative "graphics/array_image"
require_relative "graphics/graphics_buffer"
require_relative "graphics/graphics_readback"
require_relative "graphics/canvas"
require_relative "graphics/canvas_formats"
require_relative "graphics/compute_shader"
require_relative "graphics/cube_texture"
require_relative "graphics/cube_image"
require_relative "graphics/font"
require_relative "graphics/image"
require_relative "graphics/image_font"
require_relative "graphics/image_formats"
require_relative "graphics/mesh"
require_relative "graphics/particle_system"
require_relative "graphics/quad"
require_relative "graphics/shader"
require_relative "graphics/sprite_batch"
require_relative "graphics/stats"
require_relative "graphics/supported"
require_relative "graphics/system_limits"
require_relative "graphics/text"
require_relative "graphics/text_batch"
require_relative "graphics/texture_formats"
require_relative "graphics/texture_types"
require_relative "graphics/texture_view"
require_relative "graphics/video"
require_relative "graphics/volume_texture"
require_relative "graphics/volume_image"

module Lota
  # Drawing, translated from love.graphics.
  #
  # Everything a player sees passes through one graphics module. It owns
  # the window's drawing surface and a stack of state: where drawing goes,
  # in what color, through what transform. LÖVE keeps that module on the
  # main thread, because macOS draws windows only there.
  #
  # Lota::Graphics drives LÖVE's own renderer, so a frame drawn here
  # matches the same frame drawn in LÖVE. Its methods raise ThreadError
  # when called anywhere but the process's main thread, the one that
  # started Ruby.
  #
  # Use it to clear the screen or a canvas, to draw shapes in a color, to
  # choose where drawing goes, and to read pixels back.
  #
  # === Examples
  #
  #   # Clear a canvas to yellow and read it back.
  #   canvas = Lota::Graphics::Canvas.new(16, 16)
  #   Lota::Graphics.canvas = canvas
  #   Lota::Graphics.clear(1, 1, 0, 1)
  #   Lota::Graphics.canvas = nil
  #   pixels = Lota::Graphics.readback_texture(canvas)
  #
  #   # Clear whatever is the target to transparent black.
  #   Lota::Graphics.clear
  module Graphics
    # Sends drawing to +canvas+, or back to the window when +canvas+ is
    # +nil+, matching love.graphics.setCanvas
    # (src/modules/graphics/wrap_Graphics.cpp, w_setCanvas).
    #
    # [canvas] Lota::Graphics::Texture to draw into, made by
    #   Lota::Graphics::Canvas.new, or +nil+ for the window; or, as rule 6
    #   writes several values, an Array of what set_canvas takes without
    #   options.
    #
    # Everything drawn or cleared afterward lands on the canvas until you
    # set another target. The engine holds on to the active canvas, so it
    # survives even if you drop every reference to it. A canvas cannot be
    # drawn while it is the target. <tt>canvas = nil</tt> is LÖVE's
    # setCanvas() with no arguments. set_canvas takes the other forms:
    # several canvases, a mipmap or a layer, and a depth or stencil
    # buffer.
    #
    # Raises RuntimeError with LÖVE's message when the engine refuses the
    # target, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.canvas = shadow_map
    #   draw_shadows
    #   Lota::Graphics.canvas = nil
    def self.canvas=(canvas)
      canvas.is_a?(Array) ? set_canvas(*canvas) : set_canvas(canvas)
    end

    # Sends drawing to one or several canvases, with a depth or stencil
    # buffer if asked for, or back to the window, matching
    # love.graphics.setCanvas (src/modules/graphics/wrap_Graphics.cpp,
    # w_setCanvas).
    #
    # [canvases] Lota::Graphics::Texture targets, each made by
    #   Lota::Graphics::Canvas.new, which a shader writes to in order; a 2D
    #   texture may be followed by the Integer mipmap to draw to, counting
    #   from 1, and one texture that is not 2D by its Integer slice and
    #   optionally its mipmap. With options, the 2D textures alone, or in
    #   one Array, as in LÖVE's table form. None, or +nil+, draws to the
    #   window again.
    # [depthstencil] A Lota::Graphics::Texture with a depth or stencil
    #   format to use as the depth and stencil buffer, or such a target
    #   with its options, or +true+ for a
    #   temporary one of each, which lasts until the canvases change.
    # [depth] Whether to draw with a temporary depth buffer, when
    #   +depthstencil+ gives none.
    # [stencil] Whether to draw with a temporary stencil buffer, when
    #   +depthstencil+ gives none, as Lota::Graphics.stencil_state= needs to
    #   mask drawing into a canvas.
    #
    # The options are LÖVE's table of targets and options as keywords
    # (rule 10 of doc/contributors/design/translation.md). A target can also be
    # an Array of its texture and a Hash of its options, +layer+ or +face+ and
    # +mipmap+, each counting from 1, as LÖVE's table of tables gives each
    # target a table of its own: the layer a texture that is not 2D needs, and
    # the mipmap to draw to; +depthstencil+ takes one too. Returns +nil+. Raises
    # TypeError for a target that is not a Texture, RuntimeError with LÖVE's
    # message when the engine refuses the targets, as for a texture that is not
    # a canvas, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.set_canvas(mask, stencil: true)
    #   Lota::Graphics.set_canvas([albedo, normals], depth: true)
    #   Lota::Graphics.set_canvas(table_canvas, 2) # its second mipmap
    #   Lota::Graphics.set_canvas([[frames, layer: 3], [glow, mipmap: 2]])
    #   Lota::Graphics.set_canvas                  # the window again
    #
    # :call-seq:
    #   set_canvas(*canvases)
    #   set_canvas(*canvases, depthstencil: nil, depth: nil, stencil: nil)
    #   set_canvas(canvases, depthstencil: nil, depth: nil, stencil: nil)
    def self.set_canvas(*canvases, depthstencil: nil, depth: nil, stencil: nil)
      first = canvases.first
      return Native::Graphics.reset_canvas if first.nil?

      if !first.is_a?(Array) && depthstencil.nil? && depth.nil? && stencil.nil?
        return Native::Graphics.set_canvas(canvases.map { |target| native_target(target) })
      end

      targets = first.is_a?(Array) ? first : canvases
      tables = targets.first.is_a?(Array)
      Native::Graphics.set_canvas_with_options([
        targets.map { |target| tables ? render_target(target) : native_target(target) },
        depthstencil.is_a?(Array) ? render_target(depthstencil) : native_target(depthstencil),
        depth,
        stencil,
      ])
    end

    # A target of setCanvas's table of tables, as the engine reads it:
    # the texture's engine object, then the layer, face, and mipmap its
    # trailing Hash names, each nil when it names none. :nodoc:
    private_class_method def self.render_target(target)
      texture, options = target.is_a?(Array) ? target : [target]
      return [native_target(texture), nil, nil, nil] unless options.is_a?(Hash)

      [native_target(texture), options[:layer], options[:face], options[:mipmap]]
    end

    # A target LÖVE returns in getCanvas's table, as set_canvas takes one:
    # its Texture and a Hash of its layer or face and its mipmap. :nodoc:
    private_class_method def self.target_of(fields)
      native, layer, face, mipmap = fields
      [Texture.__send__(:from_native, native), { layer:, face:, mipmap: }.compact]
    end

    # A target's engine object, or the target as it is, which the engine
    # reads as LÖVE reads its arguments. :nodoc:
    private_class_method def self.native_target(target)
      target.is_a?(Texture) ? target.__send__(:native) : target
    end

    # Fills the active canvas, or the window, with one color, and clears
    # its stencil and depth buffers, matching love.graphics.clear
    # (src/modules/graphics/wrap_Graphics.cpp, w_clear).
    #
    # [red] Float or Integer, from 0 to 1; or, in place of the color,
    #   +false+ to leave the color as it is, or +true+ for transparent
    #   black.
    # [green] Float or Integer, from 0 to 1.
    # [blue] Float or Integer, from 0 to 1.
    # [alpha] Float or Integer, from 0 to 1; 1 when left out or +nil+.
    # [stencil] Integer the stencil buffer is cleared to, or +false+ to
    #   leave it; 0 when left out or anything else.
    # [depth] Float the depth buffer is cleared to, or +false+ to leave it;
    #   1 when left out or anything else.
    #
    # With no arguments it clears to transparent black. LÖVE reads each
    # component as a single-precision float, and so does Lota. The scissor
    # rectangle bounds what gets cleared. LÖVE also clears several
    # canvases to different colors, from a table of colors for each; Lota
    # binds that form later.
    #
    # Raises ArgumentError for one or two components, or more arguments
    # than LÖVE reads, TypeError for a component that is not a number, and
    # ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.clear(0.1, 0.1, 0.2)    # a dark blue background
    #   Lota::Graphics.clear(1, 1, 0, 0.5)     # half-transparent yellow
    #   Lota::Graphics.clear                   # transparent black
    #   Lota::Graphics.clear(false, 0, false)  # only the stencil, to 0
    #
    # :call-seq:
    #   clear()
    #   clear(red, green, blue, alpha = 1, stencil = 0, depth = 1)
    #   clear(color, stencil = 0, depth = 1)
    def self.clear(*arguments)
      first = arguments.first
      if [true, false].include?(first)
        raise ArgumentError, "wrong number of arguments (given #{arguments.size}, expected 1..3)" if arguments.size > 3

        return Native::Graphics.clear_buffers([first ? [0.0, 0.0, 0.0, 0.0] : nil, arguments[1], arguments[2]])
      end

      red, green, blue, alpha, stencil, depth = arguments
      case arguments.size
      when 0 then Native::Graphics.clear(0.0, 0.0, 0.0, 0.0)
      when 3, 4 then Native::Graphics.clear(number(red), number(green), number(blue), alpha.nil? ? 1.0 : number(alpha))
      when 5, 6
        color = [number(red), number(green), number(blue), alpha.nil? ? 1.0 : number(alpha)]
        Native::Graphics.clear_buffers([color, stencil, depth])
      else raise ArgumentError, "wrong number of arguments (given #{arguments.size}, expected 0 or 3..6)"
      end
    end

    # Tells the graphics card that the contents of the canvases drawn to,
    # or of the window, are no longer needed, matching love.graphics.discard
    # (src/modules/graphics/wrap_Graphics.cpp, w_discard), and returns
    # +nil+.
    #
    # [color] Whether to discard the color of every canvas set, or the
    #   window's; or an Array of whether to discard each canvas's, in the
    #   order Lota::Graphics.set_canvas set them.
    # [depthstencil] Whether to discard the depth and stencil buffers.
    #
    # Each is true unless it is +false+, as LÖVE reads it. A graphics card
    # that keeps a frame in tiles, as phones' do, can then skip loading
    # what it would overwrite; on some desktops it does nothing, and what
    # is discarded is undefined, so draw over it before reading it.
    # Raises ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.discard
    #   Lota::Graphics.discard([true, false], false)
    def self.discard(color = true, depthstencil = true)
      Native::Graphics.discard([color, depthstencil])
    end

    # Copies pixels of +texture+ back from the graphics card into a
    # Lota::Image::ImageData, matching love.graphics.readbackTexture
    # (src/modules/graphics/wrap_Graphics.cpp, w_readbackTexture).
    #
    # [texture] Lota::Graphics::Texture to read, such as a canvas.
    # [slice] Integer slice to read, counting from 1, which a texture that
    #   is not 2D needs; a 2D texture takes +nil+.
    # [mipmap] Integer mipmap to read, counting from 1; the first, the
    #   full-size image, by default.
    # [x] Integer left edge of the rectangle to read, in pixels, given
    #   with +y+, +width+, and +height+; the whole mipmap by default.
    # [y] Integer top edge of the rectangle.
    # [width] Integer width of the rectangle.
    # [height] Integer height of the rectangle.
    # [dest] Lota::Image::ImageData to read into, which comes back,
    #   instead of a new one.
    # [destx] Integer left edge in +dest+ to read to; 0 by default.
    # [desty] Integer top edge in +dest+ to read to; 0 by default.
    #
    # The copy waits for the graphics card to finish drawing, so it is
    # slow; read back for tests, screenshots, and tools, not every frame.
    #
    # Read into a +dest+ wider than the rectangle, Lota differs from LÖVE
    # on drivers whose OpenGL has glGetTextureSubImage, such as Mesa's on
    # Linux: LÖVE tells the driver the memory holds only the rectangle's
    # pixels, though the rows it writes are +dest+'s width apart
    # (src/modules/graphics/opengl/Texture.cpp, readbackInternal), so the
    # driver refuses the read and LÖVE leaves +dest+ as it was. For a
    # wider +dest+, on every driver, Lota reads the rectangle on its own
    # and copies its rows into +dest+, with LÖVE's checks and messages, so
    # the pixels arrive as they do where LÖVE's read works, such as on
    # macOS, and only where it fails does the result differ from LÖVE's.
    # Any other +dest+ is read as LÖVE reads it.
    #
    # Raises TypeError for a slice of a 2D texture that is not a number,
    # RuntimeError with LÖVE's message for a mipmap, slice, or rectangle
    # the texture does not have or a texture that is not readable, and
    # ThreadError off the main thread.
    #
    # === Examples
    #
    #   pixels = Lota::Graphics.readback_texture(canvas)
    #   pixels.pixel(0, 0) # => [1.0, 1.0, 0.0, 1.0]
    #
    #   small = Lota::Graphics.readback_texture(canvas, nil, 2) # its second mipmap
    def self.readback_texture(texture, slice = nil, mipmap = nil, x = nil, y = nil, width = nil, height = nil,
      dest = nil, destx = nil, desty = nil
    )
      unless dest.nil? || dest.is_a?(Lota::Image::ImageData)
        raise TypeError, "wrong argument type #{dest.class} for dest (expected Lota::Image::ImageData)"
      end

      native = Native::Graphics.readback_texture(texture.__send__(:native),
        [slice, mipmap, x, y, width, height, dest&.__send__(:native), destx, desty])
      dest || Lota::Image::ImageData.__send__(:from_native, native)
    end

    # Starts copying pixels of +texture+ back from the graphics card, and
    # returns a Lota::Graphics::GraphicsReadback that has them once it is
    # complete, matching love.graphics.readbackTextureAsync
    # (src/modules/graphics/wrap_Graphics.cpp, w_readbackTextureAsync).
    #
    # It takes what readback_texture takes, and returns at once, where
    # readback_texture waits for the graphics card. LÖVE finishes the copy
    # as it presents a frame; GraphicsReadback#wait finishes it now. It
    # copies into +dest+ row by row, so a +dest+ wider than the rectangle
    # takes the pixels on every driver.
    #
    # Raises what readback_texture raises.
    #
    # === Example
    #
    #   readback = Lota::Graphics.readback_texture_async(canvas)
    #   readback.wait
    #   readback.image_data.pixel(0, 0) # => [1.0, 1.0, 0.0, 1.0]
    def self.readback_texture_async(texture, slice = nil, mipmap = nil, x = nil, y = nil, width = nil, height = nil,
      dest = nil, destx = nil, desty = nil
    )
      unless dest.nil? || dest.is_a?(Lota::Image::ImageData)
        raise TypeError, "wrong argument type #{dest.class} for dest (expected Lota::Image::ImageData)"
      end

      native = Native::Graphics.readback_texture_async(texture.__send__(:native),
        [slice, mipmap, x, y, width, height, dest&.__send__(:native), destx, desty])
      GraphicsReadback.__send__(:from_native, native)
    end

    # Copies bytes of +buffer+ back from the graphics card into a
    # Lota::Data::ByteData, matching love.graphics.readbackBuffer
    # (src/modules/graphics/wrap_Graphics.cpp, w_readbackBuffer).
    #
    # [buffer] Lota::Graphics::GraphicsBuffer to read.
    # [offset] Integer byte to start from; 0 by default.
    # [size] Integer number of bytes to read; the rest of +buffer+ by
    #   default.
    # [dest] Lota::Data::ByteData to read into, which comes back, instead
    #   of a new one.
    # [destoffset] Integer byte in +dest+ to read to; 0 by default.
    #
    # The copy waits for the graphics card to finish drawing, so it is
    # slow; read back for tests and tools, not every frame.
    #
    # Raises TypeError for a +buffer+ or +dest+ of another class,
    # RuntimeError with LÖVE's message for a range the buffer does not
    # have or a buffer that cannot be read back, and ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   bytes = Lota::Graphics.readback_buffer(positions)
    #   bytes.size # => positions.size
    def self.readback_buffer(buffer, offset = nil, size = nil, dest = nil, destoffset = nil)
      check_readback(buffer, dest)
      native = Native::Graphics.readback_buffer(buffer.__send__(:native), offset || 0, size, dest&.__send__(:native),
        destoffset || 0)
      dest || Lota::Data::ByteData.__send__(:from_native, native)
    end

    # Starts copying bytes of +buffer+ back from the graphics card, and
    # returns a Lota::Graphics::GraphicsReadback that has them once it is
    # complete, matching love.graphics.readbackBufferAsync
    # (src/modules/graphics/wrap_Graphics.cpp, w_readbackBufferAsync).
    #
    # It takes what readback_buffer takes, and returns at once, where
    # readback_buffer waits for the graphics card. Its +buffer_data+ is the
    # bytes once it is complete.
    #
    # Raises what readback_buffer raises.
    #
    # === Example
    #
    #   readback = Lota::Graphics.readback_buffer_async(positions)
    #   readback.wait
    #   readback.buffer_data.size # => positions.size
    def self.readback_buffer_async(buffer, offset = nil, size = nil, dest = nil, destoffset = nil)
      check_readback(buffer, dest)
      native = Native::Graphics.readback_buffer_async(buffer.__send__(:native), offset || 0, size,
        dest&.__send__(:native), destoffset || 0)
      GraphicsReadback.__send__(:from_native, native)
    end

    # The buffer and the destination readback_buffer takes, or TypeError.
    # :nodoc:
    private_class_method def self.check_readback(buffer, dest)
      check_buffer(buffer, "buffer")
      return if dest.nil? || dest.is_a?(Lota::Data::ByteData)

      raise TypeError, "wrong argument type #{dest.class} for dest (expected Lota::Data::ByteData)"
    end

    # +buffer+, which must be a GraphicsBuffer, or TypeError, as
    # luax_checkbuffer reads one. :nodoc:
    private_class_method def self.check_buffer(buffer, name)
      return if buffer.is_a?(GraphicsBuffer)

      raise TypeError, "wrong argument type #{buffer.class} for #{name} (expected Lota::Graphics::GraphicsBuffer)"
    end

    # Copies bytes from one buffer to another on the graphics card,
    # matching love.graphics.copyBuffer
    # (src/modules/graphics/wrap_Graphics.cpp, w_copyBuffer).
    #
    # [source] Lota::Graphics::GraphicsBuffer to copy from.
    # [dest] Lota::Graphics::GraphicsBuffer to copy to.
    # [sourceoffset] Integer byte in +source+ to start from; 0 by default.
    # [destoffset] Integer byte in +dest+ to start at; 0 by default.
    # [size] Integer number of bytes; as many as both have left by
    #   default.
    #
    # Returns +nil+. Raises TypeError for a buffer of another class,
    # RuntimeError with LÖVE's message for a negative offset, a size that
    # is not positive, or a range the buffers do not have, and
    # ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.copy_buffer(staging, positions, 0, 0, 64)
    def self.copy_buffer(source, dest, sourceoffset = nil, destoffset = nil, size = nil)
      check_buffer(source, "source")
      check_buffer(dest, "dest")
      Native::Graphics.copy_buffer(source.__send__(:native), dest.__send__(:native), [sourceoffset, destoffset, size])
    end

    # Copies bytes of a buffer into a texture on the graphics card,
    # matching love.graphics.copyBufferToTexture
    # (src/modules/graphics/wrap_Graphics.cpp, w_copyBufferToTexture).
    #
    # [source] Lota::Graphics::GraphicsBuffer to copy from.
    # [dest] Lota::Graphics::Texture to copy to.
    # [sourceoffset] Integer byte in +source+ to start from; 0 by default.
    # [sourcewidth] Integer width in pixels of a row in +source+; the
    #   rectangle's width by default.
    # [slice] Integer slice to copy to, counting from 1, which a texture
    #   that is not 2D needs.
    # [mipmap] Integer mipmap to copy to, counting from 1; the first by
    #   default.
    # [x] Integer left edge of the rectangle to copy to, given with +y+,
    #   +width+, and +height+; the whole mipmap by default.
    # [y] Integer top edge of the rectangle.
    # [width] Integer width of the rectangle.
    # [height] Integer height of the rectangle.
    #
    # Returns +nil+. Raises TypeError for a +source+ or +dest+ of another
    # class, RuntimeError with LÖVE's message for a negative offset or a
    # range, mipmap, slice, or rectangle the buffer or texture does not
    # have, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.copy_buffer_to_texture(pixels, canvas)
    def self.copy_buffer_to_texture(source, dest, sourceoffset = nil, sourcewidth = nil, slice = nil, mipmap = nil,
      x = nil, y = nil, width = nil, height = nil
    )
      check_buffer(source, "source")
      Native::Graphics.copy_buffer_to_texture(source.__send__(:native), texture_argument(dest, "dest"),
        [sourceoffset, sourcewidth, slice, mipmap, x, y, width, height])
    end

    # Copies pixels of a texture into a buffer on the graphics card,
    # matching love.graphics.copyTextureToBuffer
    # (src/modules/graphics/wrap_Graphics.cpp, w_copyTextureToBuffer).
    #
    # [source] Lota::Graphics::Texture to copy from.
    # [dest] Lota::Graphics::GraphicsBuffer to copy to.
    # [slice] Integer slice to copy from, counting from 1, which a texture
    #   that is not 2D needs.
    # [mipmap] Integer mipmap to copy from, counting from 1; the first by
    #   default.
    # [x] Integer left edge of the rectangle to copy, given with +y+,
    #   +width+, and +height+; the whole mipmap by default.
    # [y] Integer top edge of the rectangle.
    # [width] Integer width of the rectangle.
    # [height] Integer height of the rectangle.
    # [destoffset] Integer byte in +dest+ to start at; 0 by default.
    # [destwidth] Integer width in pixels of a row in +dest+; the
    #   rectangle's width by default.
    #
    # Returns +nil+. Raises TypeError for a +source+ or +dest+ of another
    # class, or a missing +slice+ for a texture that is not 2D,
    # RuntimeError with LÖVE's message for a negative offset or a range,
    # mipmap, slice, or rectangle the texture or buffer does not have,
    # and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.copy_texture_to_buffer(canvas, pixels)
    def self.copy_texture_to_buffer(source, dest, slice = nil, mipmap = nil, x = nil, y = nil, width = nil,
      height = nil, destoffset = nil, destwidth = nil
    )
      native = texture_argument(source, "source")
      check_buffer(dest, "dest")
      if slice.nil? && source.texture_type != :"2d"
        raise TypeError, "wrong argument type nil for slice (expected Integer)"
      end

      Native::Graphics.copy_texture_to_buffer(native, dest.__send__(:native),
        [slice, mipmap, x, y, width, height, destoffset, destwidth])
    end

    # The engine's Texture of +texture+, which must be a Texture, or
    # TypeError, as luax_checktexture reads one. :nodoc:
    private_class_method def self.texture_argument(texture, name)
      return texture.__send__(:native) if texture.is_a?(Texture)

      raise TypeError, "wrong argument type #{texture.class} for #{name} (expected Lota::Graphics::Texture)"
    end

    # Whether drawing reaches the screen, matching love.graphics.isActive
    # (src/modules/graphics/wrap_Graphics.cpp, w_isActive).
    #
    # The graphics module is only completely active when there is an open
    # window, a context to draw with, and the system has not put the game in
    # the background. Lota's loop draws a frame only while this is +true+.
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.active? # => true
    def self.active?
      Native::Graphics.active?
    end

    # Whether the graphics module has a window to draw in, matching
    # love.graphics.isCreated (src/modules/graphics/wrap_Graphics.cpp,
    # w_isCreated).
    #
    # It is +false+ until the window first opens, as when the settings
    # open none (<tt>t.window = false</tt>). Raises ThreadError off the main
    # thread.
    #
    # === Example
    #
    #   Lota::Graphics.created? # => true
    def self.created?
      Native::Graphics.created?
    end

    # Puts the drawing state back as it starts, matching
    # love.graphics.reset (src/modules/graphics/wrap_Graphics.cpp,
    # w_reset).
    #
    # The color, the background color, the font, the line's width and
    # style, the canvas, the default filter, and the rest of LÖVE's drawing
    # state return to their defaults, and the transformation to the origin
    # (Graphics::reset and restoreState, src/modules/graphics/Graphics.cpp).
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.reset
    def self.reset
      Native::Graphics.reset
    end

    # Resets the current transformation, matching love.graphics.origin
    # (src/modules/graphics/wrap_Graphics.cpp, w_origin).
    #
    # Afterward, (0, 0) is the window's top-left corner again, with no
    # rotation or scale. Lota's loop calls it before each draw. Raises
    # ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.origin
    def self.origin
      Native::Graphics.origin
    end

    # Saves the current transformation, or all of the drawing state, so
    # pop can bring it back, matching love.graphics.push
    # (src/modules/graphics/wrap_Graphics.cpp, w_push). With a block, it
    # pops once the block is done, also when the block raises, and returns
    # what the block returns (rule 11 of
    # doc/contributors/design/translation.md).
    #
    # [stack] +:transform+ (the default, also when +nil+) saves the
    #   transformation alone, and +:all+ the color, font, canvas, and the
    #   rest of the state too.
    # [transform] Lota::Math::Transform to apply once the state is saved,
    #   as apply_transform does. LÖVE ignores anything else here, and so
    #   does Lota.
    #
    # Raises ArgumentError for an unknown stack type, RuntimeError
    # (<tt>"Maximum stack depth reached (more pushes than pops?)"</tt>)
    # past LÖVE's depth of 128, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.push do
    #     Lota::Graphics.translate(100, 50)
    #     Lota::Graphics.rectangle(:fill, 0, 0, 10, 10)
    #   end
    #
    #   Lota::Graphics.push(:all)
    #   Lota::Graphics.color = 1, 0, 0
    #   Lota::Graphics.pop
    #
    #   Lota::Graphics.push(:transform, camera) { Lota::Graphics.draw(map) }
    def self.push(stack = nil, transform = nil)
      Native::Graphics.push(stack && EnumName.of(stack), transform.is_a?(Math::Transform) ? transform.__send__(:native) : nil)
      return nil unless block_given?

      begin
        yield
      ensure
        Native::Graphics.pop
      end
    end

    # Brings back the state the latest push saved, matching
    # love.graphics.pop (src/modules/graphics/wrap_Graphics.cpp, w_pop).
    #
    # Raises RuntimeError (<tt>"Minimum stack depth reached (more pops
    # than pushes?)"</tt>) with nothing pushed, and ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Graphics.pop
    def self.pop
      Native::Graphics.pop
    end

    # Moves what is drawn after it by +x+ and +y+, matching
    # love.graphics.translate (src/modules/graphics/wrap_Graphics.cpp,
    # w_translate).
    #
    # [x] Float or Integer distance to the right.
    # [y] Float or Integer distance down.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.translate(100, 50)
    def self.translate(x, y)
      Native::Graphics.translate(x, y)
    end

    # Scales what is drawn after it, matching love.graphics.scale
    # (src/modules/graphics/wrap_Graphics.cpp, w_scale).
    #
    # [sx] Float or Integer horizontal factor; 1 when left out.
    # [sy] Float or Integer vertical factor; +sx+ when +nil+ or left out.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.scale(2)
    def self.scale(sx = 1, sy = nil)
      Native::Graphics.scale(sx, sy)
    end

    # Shears what is drawn after it, matching love.graphics.shear
    # (src/modules/graphics/wrap_Graphics.cpp, w_shear).
    #
    # [kx] Float or Integer horizontal shearing factor.
    # [ky] Float or Integer vertical shearing factor.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.shear(0.5, 0)
    def self.shear(kx, ky)
      Native::Graphics.shear(kx, ky)
    end

    # Rotates what is drawn after it by +angle+, matching
    # love.graphics.rotate (src/modules/graphics/wrap_Graphics.cpp,
    # w_rotate).
    #
    # [angle] Float or Integer rotation in radians, clockwise on screen,
    #   around the current origin.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.rotate(Math::PI / 2)
    def self.rotate(angle)
      Native::Graphics.rotate(angle)
    end

    # Multiplies the current transformation by a Transform, or by a
    # placement, so what is drawn after it goes through both, matching
    # love.graphics.applyTransform
    # (src/modules/graphics/wrap_Graphics.cpp, w_applyTransform).
    #
    # [transform] Lota::Math::Transform; or else the first of up to nine
    #   numbers, in the order Lota::Math::Transform.new takes them, each
    #   taking its default when +nil+ or left out.
    #
    # Raises TypeError for an argument that is neither, and ThreadError
    # off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.apply_transform(camera)
    #   Lota::Graphics.apply_transform(100, 50, Math::PI / 4)
    def self.apply_transform(transform = nil, *placement)
      return Native::Graphics.apply_transform(transform.__send__(:native)) if transform.is_a?(Math::Transform)

      Native::Graphics.apply_placement(standard_placement(transform, *placement))
    end

    # Replaces the current transformation with a Transform, or with a
    # placement, matching love.graphics.replaceTransform
    # (src/modules/graphics/wrap_Graphics.cpp, w_replaceTransform).
    #
    # [transform] As apply_transform takes it.
    #
    # Raises TypeError for an argument that is neither, and ThreadError
    # off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.replace_transform(camera)
    def self.replace_transform(transform = nil, *placement)
      return Native::Graphics.replace_transform(transform.__send__(:native)) if transform.is_a?(Math::Transform)

      Native::Graphics.replace_placement(standard_placement(transform, *placement))
    end

    # Moves a point from where it would be drawn to where it appears on
    # the screen, through the current transformation, matching
    # love.graphics.transformPoint (src/modules/graphics/wrap_Graphics.cpp,
    # w_transformPoint).
    #
    # [x] Float or Integer.
    # [y] Float or Integer.
    #
    # Returns the point's x and y on the screen, as an Array of Floats
    # (rule 4 of doc/contributors/design/translation.md). Raises ThreadError off
    # the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.translate(1, 5)
    #   Lota::Graphics.transform_point(0, 0) # => [1.0, 5.0]
    def self.transform_point(x, y)
      Native::Graphics.transform_point(x, y)
    end

    # Moves a point on the screen back to where it would be drawn, through
    # the inverse of the current transformation, matching
    # love.graphics.inverseTransformPoint
    # (src/modules/graphics/wrap_Graphics.cpp, w_inverseTransformPoint).
    # A game uses it to find what the mouse points at.
    #
    # [x] Float or Integer.
    # [y] Float or Integer.
    #
    # Returns the point's x and y before the transformation, as an Array of
    # Floats (rule 4 of doc/contributors/design/translation.md). Raises
    # ThreadError off the main thread.
    #
    # === Example
    #
    #   world_x, world_y = Lota::Graphics.inverse_transform_point(*Lota::Mouse.position)
    def self.inverse_transform_point(x, y)
      Native::Graphics.inverse_transform_point(x, y)
    end

    # Sets the projection that maps what is drawn onto the window or the
    # canvas, matching love.graphics.setProjection
    # (src/modules/graphics/wrap_Graphics.cpp, w_setProjection).
    #
    # [projection] Lota::Math::Transform, whose matrix becomes the
    #   projection; or the layout and sixteen elements of a matrix, as
    #   Lota::Math::Transform#matrix= takes them.
    #
    # LÖVE projects orthographically, so that a unit is a pixel, until it
    # is set; reset_projection goes back to that. Raises ArgumentError for
    # an unknown layout or a count of elements other than sixteen,
    # TypeError for an element that is not a number, and ThreadError off
    # the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.projection = :row, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1
    def self.projection=(projection)
      if projection.is_a?(Math::Transform)
        Native::Graphics.set_projection(projection.__send__(:native))
      else
        layout, elements = Math::Transform.__send__(:layout_and_elements, projection)
        Native::Graphics.set_projection_matrix(layout, elements)
      end
    end

    # Goes back to LÖVE's own orthographic projection, matching
    # love.graphics.resetProjection
    # (src/modules/graphics/wrap_Graphics.cpp, w_resetProjection).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.reset_projection
    def self.reset_projection
      Native::Graphics.reset_projection
    end

    # The color the loop clears the window to before each draw, as an
    # Array of red, green, blue, and alpha, each from 0.0 to 1.0, matching
    # love.graphics.getBackgroundColor
    # (src/modules/graphics/wrap_Graphics.cpp, w_getBackgroundColor).
    #
    # It starts as opaque black. Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   red, green, blue, alpha = Lota::Graphics.background_color # => [0.0, 0.0, 0.0, 1.0]
    def self.background_color
      Native::Graphics.background_color
    end

    # Shows what was drawn since the last present, matching
    # love.graphics.present (src/modules/graphics/wrap_Graphics.cpp,
    # w_present).
    #
    # Drawing goes to a hidden buffer, so the player never sees a frame
    # half drawn; presenting swaps it onto the screen. Lota's loop presents
    # once a frame, after your draw callback. It does nothing while the
    # module is not active. Raises RuntimeError while a canvas is the
    # target, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.clear(0, 0, 0)
    #   Lota::Graphics.present
    def self.present
      Native::Graphics.present
    end

    # Sets the color everything is drawn in, matching
    # love.graphics.setColor (src/modules/graphics/wrap_Graphics.cpp,
    # w_setColor).
    #
    # [color] Red, green, blue, and optionally alpha, each a Float or
    #   Integer from 0 to 1, as one Array; alpha is 1 when left out.
    #
    # Shapes take this color as they are drawn, and keep it, so set it
    # before each thing you draw in a different color. It starts as opaque
    # white. LÖVE stores each component as a single-precision float,
    # clamped to 0 through 1, and so does Lota.
    #
    # An Array is LÖVE's table form, which reads its first four elements
    # and ignores any after them (<tt>lua_rawgeti</tt> for 1 through 4).
    # Raises TypeError, with LÖVE's message, for a red, green, or blue that
    # is not a number, as when the Array has fewer than three elements
    # (<tt>luaL_checknumber</tt> at the table's elements), and for an alpha
    # that is neither a number nor +nil+. Raises ThreadError off the main
    # thread.
    #
    # === Examples
    #
    #   Lota::Graphics.color = 1, 0, 0       # opaque red
    #   Lota::Graphics.color = 0, 0, 1, 0.5  # half-transparent blue
    #   Lota::Graphics.color = [1, 1, 1]     # an Array works too
    def self.color=(color)
      elements = color.is_a?(::Array) ? color : [color]
      red = color_element(elements, 0)
      green = color_element(elements, 1)
      blue = color_element(elements, 2)
      alpha = elements[3].nil? ? 1.0 : color_element(elements, 3)
      Native::Graphics.set_color(red, green, blue, alpha)
    end

    # The number at +index+ of a color's elements, or the TypeError
    # <tt>luaL_checknumber</tt> raises for it at the stack slot
    # +lua_rawgeti+ pushed it to, which counts from the top: LÖVE's
    # message names the function by Lota's name (rule 23 of
    # doc/contributors/design/translation.md). :nodoc:
    private_class_method def self.color_element(elements, index)
      value = elements[index]
      return value if value.is_a?(Numeric)

      lua_type = case value
      when nil then "nil"
      when true, false then "boolean"
      when String then "string"
      when ::Array, ::Hash then "table"
      else "userdata"
      end
      raise TypeError, "bad argument ##{index - 4} to 'Lota::Graphics.color=' (number expected, got #{lua_type})"
    end

    # The color everything is drawn in, as an Array of red, green, blue,
    # and alpha, each from 0.0 to 1.0, matching love.graphics.getColor
    # (src/modules/graphics/wrap_Graphics.cpp, w_getColor).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   red, green, blue, alpha = Lota::Graphics.color # => [1.0, 1.0, 1.0, 1.0]
    def self.color
      Native::Graphics.color
    end

    # Sets how wide lines and outlines are drawn, matching
    # love.graphics.setLineWidth (src/modules/graphics/wrap_Graphics.cpp,
    # w_setLineWidth).
    #
    # [width] Float or Integer width, in the current coordinate system's
    #   units.
    #
    # It starts at 1, and applies to every shape drawn with +:line+.
    # LÖVE stores it as a single-precision float, and so does Lota.
    # Raises TypeError for a width that is not a number, and ThreadError
    # off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.line_width = 3
    def self.line_width=(width)
      Native::Graphics.set_line_width(width)
    end

    # How wide lines and outlines are drawn, as a Float, matching
    # love.graphics.getLineWidth (src/modules/graphics/wrap_Graphics.cpp,
    # w_getLineWidth).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.line_width # => 1.0
    def self.line_width
      Native::Graphics.line_width
    end

    # Sets how the edges of lines and outlines are drawn, matching
    # love.graphics.setLineStyle (src/modules/graphics/wrap_Graphics.cpp,
    # w_setLineStyle).
    #
    # [style] +:smooth+, the default, blends a line's edges into what is
    #   behind it; +:rough+ draws them sharp, for pixel art.
    #
    # Raises ArgumentError for an unknown style, and ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Graphics.line_style = :rough
    def self.line_style=(style)
      Native::Graphics.set_line_style(EnumName.of(style))
    end

    # How the edges of lines and outlines are drawn, +:smooth+ or
    # +:rough+, matching love.graphics.getLineStyle
    # (src/modules/graphics/wrap_Graphics.cpp, w_getLineStyle).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.line_style # => :smooth
    def self.line_style
      Native::Graphics.line_style.to_sym
    end

    # Draws a rectangle in the current color, matching
    # love.graphics.rectangle (src/modules/graphics/wrap_Graphics.cpp,
    # w_rectangle).
    #
    # [mode] +:fill+ to fill it, or +:line+ to draw its outline.
    # [x] Float or Integer position of its left edge.
    # [y] Float or Integer position of its top edge.
    # [width] Float or Integer width.
    # [height] Float or Integer height.
    # [rx] Float or Integer horizontal radius of its rounded corners;
    #   square corners when +nil+ or left out.
    # [ry] Float or Integer vertical radius of the corners; +rx+ when +nil+
    #   or left out.
    # [segments] Integer count of straight sides each corner is drawn
    #   with; when +nil+ or left out, LÖVE picks enough for the corner's
    #   size on screen.
    #
    # Positions and sizes are in the current coordinate system, which
    # starts as the window's or the canvas's pixels, with (0, 0) at the
    # top left. LÖVE reads each as a single-precision float, and so does
    # Lota.
    #
    # Raises ArgumentError for an unknown +mode+, TypeError for a position,
    # size, or radius that is not a number or a count of segments that is
    # not an Integer, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.rectangle(:fill, 100, 100, 50, 30)
    #   Lota::Graphics.rectangle(:line, 500, 500, 70, 20)
    #   Lota::Graphics.rectangle(:fill, 10, 10, 56, 12, 4, 4) # rounded corners
    def self.rectangle(mode, x, y, width, height, rx = nil, ry = nil, segments = nil)
      Native::Graphics.rectangle(EnumName.of(mode), x, y, width, height, rx, ry, segments)
    end

    # Draws a circle in the current color, matching love.graphics.circle
    # (src/modules/graphics/wrap_Graphics.cpp, w_circle).
    #
    # [mode] +:fill+ to fill it, or +:line+ to draw its outline.
    # [x] Float or Integer position of its center.
    # [y] Float or Integer position of its center.
    # [radius] Float or Integer radius.
    # [segments] Integer count of straight sides it is drawn with; when
    #   +nil+ or left out, LÖVE picks enough for the circle's size on
    #   screen.
    #
    # A circle is drawn as a polygon, so few segments show as corners.
    # LÖVE reads the position and radius as single-precision floats, and
    # so does Lota.
    #
    # Raises ArgumentError for an unknown +mode+, TypeError for a position
    # or radius that is not a number or a count of segments that is not an
    # Integer, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.circle(:fill, 300, 300, 10)
    #   Lota::Graphics.circle(:line, 300, 300, 10, 16)
    def self.circle(mode, x, y, radius, segments = nil)
      Native::Graphics.circle(EnumName.of(mode), x, y, radius, segments)
    end

    # Draws an ellipse in the current color, matching
    # love.graphics.ellipse (src/modules/graphics/wrap_Graphics.cpp,
    # w_ellipse).
    #
    # [mode] +:fill+ to fill it, or +:line+ to draw its outline.
    # [x] Float or Integer position of its center.
    # [y] Float or Integer position of its center.
    # [radius_x] Float or Integer horizontal radius.
    # [radius_y] Float or Integer vertical radius; +radius_x+ when +nil+
    #   or left out, which draws a circle.
    # [segments] Integer count of straight sides it is drawn with; when
    #   +nil+ or left out, LÖVE picks enough for the ellipse's size on
    #   screen.
    #
    # LÖVE reads the position and radii as single-precision floats, and so
    # does Lota.
    #
    # Raises ArgumentError for an unknown +mode+, TypeError for a position
    # or radius that is not a number or a count of segments that is not an
    # Integer, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.ellipse(:fill, 400, 300, 100, 50)
    #   Lota::Graphics.ellipse(:line, 400, 300, 10, 10, 32)
    def self.ellipse(mode, x, y, radius_x, radius_y = nil, segments = nil)
      Native::Graphics.ellipse(EnumName.of(mode), x, y, radius_x, radius_y, segments)
    end

    # Draws an arc, part of a circle, in the current color, matching
    # love.graphics.arc (src/modules/graphics/wrap_Graphics.cpp, w_arc).
    #
    # [drawmode] +:fill+ to fill it, or +:line+ to draw its outline.
    # [arcmode] How its ends are joined, when given: +:pie+ (the default)
    #   draws lines from both ends to the center, +:open+ leaves the ends
    #   apart, and +:closed+ joins them with a line. Leave it out and the
    #   position comes second.
    # [x] Float or Integer position of the circle's center.
    # [y] Float or Integer position of the circle's center.
    # [radius] Float or Integer radius.
    # [angle1] Float angle the arc starts at, in radians, measured
    #   clockwise from the right, as the window's y axis points down.
    # [angle2] Float angle it ends at, in radians.
    # [segments] Integer count of straight sides it is drawn with; when
    #   +nil+ or left out, LÖVE picks enough for the arc's size on screen.
    #
    # LÖVE tells the arc mode from the position by its type, a string
    # rather than a number, and so does Lota: a Symbol or a String second
    # is the arc mode.
    #
    # Raises ArgumentError for an unknown draw or arc mode or the wrong
    # count of arguments, TypeError for a position, radius, or angle that
    # is not a number, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.arc(:fill, 400, 300, 100, 0, Math::PI / 2)
    #   Lota::Graphics.arc(:line, :open, 400, 300, 100, 0, Math::PI, 16)
    def self.arc(drawmode, *arguments)
      arcmode = EnumName.of(arguments.shift) if arguments.first.is_a?(Symbol) || arguments.first.is_a?(String)
      unless arguments.size.between?(5, 6)
        raise ArgumentError, "wrong number of arguments (given #{arguments.size + 1}, expected 6..8)"
      end

      Native::Graphics.arc(EnumName.of(drawmode), arcmode, arguments)
    end

    # Draws lines between points in the current color and line width,
    # matching love.graphics.line (src/modules/graphics/wrap_Graphics.cpp,
    # w_line).
    #
    # [points] The x and y of each point in turn, at least two points, as
    #   numbers or as one Array of them.
    #
    # The line joins each point to the next. LÖVE reads each coordinate
    # as a single-precision float, and so does Lota.
    #
    # Raises RuntimeError with LÖVE's message for an odd count of
    # coordinates or fewer than two points, TypeError for a coordinate
    # that is not a number, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.line(100, 100, 200, 150)
    #   Lota::Graphics.line([0, 0, 8, 8, 16, 0])
    def self.line(*points)
      first = points.first
      unless first.is_a?(Array) || first.is_a?(Integer) || first.is_a?(Float)
        raise TypeError, "wrong argument type #{first.class} (expected Array or Float)"
      end

      Native::Graphics.line((points.size == 1 && first.is_a?(Array)) ? first : points)
    end

    # Draws +drawable+ in the current color, matching love.graphics.draw
    # (src/modules/graphics/wrap_Graphics.cpp, w_draw).
    #
    # [drawable] Lota::Graphics::Texture, such as a canvas, or
    #   Lota::Graphics::SpriteBatch.
    # [quad] Lota::Graphics::Quad of the part of a texture to draw; the
    #   whole drawable when left out.
    # [x] Float or Integer position of its left edge; 0 when +nil+ or
    #   left out.
    # [y] Float or Integer position of its top edge; 0 likewise.
    # [r] Float angle in radians; 0 likewise.
    # [sx] Float or Integer horizontal scale; 1 likewise.
    # [sy] Float or Integer vertical scale; +sx+ likewise.
    # [ox] Float or Integer horizontal origin offset; 0 likewise.
    # [oy] Float or Integer vertical origin offset; 0 likewise.
    # [kx] Float or Integer horizontal shearing factor; 0 likewise.
    # [ky] Float or Integer vertical shearing factor; 0 likewise.
    #
    # [transform] Lota::Math::Transform that places it, in place of the
    #   numbers.
    #
    # The current color tints what is drawn, so white draws it as it is.
    # LÖVE reads each number as a single-precision float, and so does
    # Lota. A drawable is a Lota::Graphics::Texture, SpriteBatch,
    # TextBatch, Mesh, ParticleSystem, or Video; a Video shows its current
    # frame.
    #
    # Raises TypeError for a drawable Lota cannot draw, for a quad with a
    # drawable that is not a Texture, for +nil+ in place of a quad with
    # numbers after it, as LÖVE raises, or for a number of the wrong type;
    # ArgumentError for more than nine numbers; RuntimeError with LÖVE's
    # message when the engine refuses the draw, as for a canvas drawn into
    # itself; and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.draw(canvas)
    #   Lota::Graphics.draw(canvas, 100, 50, 0, 2) # twice the size
    #   Lota::Graphics.draw(sheet, grass, 16, 16)  # part of a texture
    #
    # :call-seq:
    #   draw(drawable, x = 0, y = 0, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
    #   draw(texture, quad, x = 0, y = 0, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
    #   draw(drawable, transform)
    #   draw(texture, quad, transform)
    def self.draw(drawable, quad = nil, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil, kx = nil, ky = nil)
      return draw_with_transform(drawable, nil, quad) if quad.is_a?(Math::Transform)
      return draw_with_transform(drawable, transform_quad(quad), x) if x.is_a?(Math::Transform)

      placement = placement_after(quad, x, y, r, sx, sy, ox, oy, kx, ky)
      if quad.is_a?(Quad)
        raise TypeError, "wrong argument type #{drawable.class} (expected Lota::Graphics::Texture)" unless drawable.is_a?(Texture)

        return Native::Graphics.draw_quad(drawable.__send__(:native), quad.__send__(:native), placement)
      end

      case drawable
      when Texture then Native::Graphics.draw(drawable.__send__(:native), placement)
      when SpriteBatch then Native::Graphics.draw_sprite_batch(drawable.__send__(:native), placement)
      when TextBatch then Native::Graphics.draw_text_batch(drawable.__send__(:native), placement)
      when Mesh then Native::Graphics.draw_mesh(drawable.__send__(:native), placement)
      when ParticleSystem then Native::Graphics.draw_particle_system(drawable.__send__(:native), placement)
      when Video then Native::Graphics.draw_video(drawable.__send__(:native), placement)
      else raise TypeError, not_drawable(drawable)
      end
    end

    # The Quad a Transform follows, where luax_checkstandardtransform
    # reads the Transform after a Quad; after anything else, LÖVE reads a
    # number where the Transform is, and raises.
    private_class_method def self.transform_quad(quad)
      return quad if quad.is_a?(Quad)

      raise TypeError, "wrong argument type Lota::Math::Transform (expected Float or Integer)"
    end

    # w_draw placed by a Transform (wrap_Graphics.cpp:3245-3279 and
    # wrap_SpriteBatch.h:33-64), which luax_checkstandardtransform reads
    # in place of the numbers.
    private_class_method def self.draw_with_transform(drawable, quad, transform)
      if quad.is_a?(Quad)
        raise TypeError, "wrong argument type #{drawable.class} (expected Lota::Graphics::Texture)" unless drawable.is_a?(Texture)

        return Native::Graphics.draw_quad_with_transform(drawable.__send__(:native), quad.__send__(:native), transform.__send__(:native))
      end

      case drawable
      when Texture then Native::Graphics.draw_with_transform(drawable.__send__(:native), transform.__send__(:native))
      when SpriteBatch then Native::Graphics.draw_sprite_batch_with_transform(drawable.__send__(:native), transform.__send__(:native))
      when TextBatch then Native::Graphics.draw_text_batch_with_transform(drawable.__send__(:native), transform.__send__(:native))
      when Mesh then Native::Graphics.draw_mesh_with_transform(drawable.__send__(:native), transform.__send__(:native))
      when ParticleSystem then Native::Graphics.draw_particle_system_with_transform(drawable.__send__(:native), transform.__send__(:native))
      when Video then Native::Graphics.draw_video_with_transform(drawable.__send__(:native), transform.__send__(:native))
      else raise TypeError, not_drawable(drawable)
      end
    end

    # The message for a +drawable+ draw cannot draw.
    private_class_method def self.not_drawable(drawable)
      "wrong argument type #{drawable.class} " \
        "(expected Lota::Graphics::Texture, Lota::Graphics::SpriteBatch, Lota::Graphics::TextBatch, " \
        "Lota::Graphics::Mesh, Lota::Graphics::ParticleSystem, or Lota::Graphics::Video)"
    end

    # Draws one layer of an array texture in the current color, matching
    # love.graphics.drawLayer (src/modules/graphics/wrap_Graphics.cpp,
    # w_drawLayer).
    #
    # [texture] Lota::Graphics::Texture of type +:array+, such as one
    #   Lota::Graphics::ArrayImage.new makes.
    # [layer] Integer layer to draw, counting from 1.
    # [quad] Lota::Graphics::Quad of the part of the layer to draw; the
    #   whole layer when left out.
    # [x] Placement as for draw: up to nine numbers, or a
    #   Lota::Math::Transform.
    #
    # Returns +nil+. Raises TypeError for a texture that is not a Texture,
    # a layer that is not a number, or +nil+ in place of a quad with
    # numbers after it, as LÖVE raises; RuntimeError with LÖVE's message
    # for a texture that is not an array texture or a layer it does not
    # have; and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.draw_layer(frames, 2, 100, 100)
    #   Lota::Graphics.draw_layer(frames, 3, 100, 100, 0, 2, 2, 16, 16)
    #
    # :call-seq:
    #   draw_layer(texture, layer, x = 0, y = 0, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
    #   draw_layer(texture, layer, quad, x = 0, y = 0, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
    #   draw_layer(texture, layer, transform)
    #   draw_layer(texture, layer, quad, transform)
    def self.draw_layer(texture, layer, quad = nil, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil,
      kx = nil, ky = nil
    )
      raise TypeError, "wrong argument type #{texture.class} (expected Lota::Graphics::Texture)" unless texture.is_a?(Texture)
      raise TypeError, "wrong argument type #{layer.class} for layer (expected Integer)" unless layer.is_a?(Integer) || layer.is_a?(Float)

      if quad.is_a?(Math::Transform)
        return Native::Graphics.draw_layer_with_transform(texture.__send__(:native), layer.to_i, nil, quad.__send__(:native))
      end
      if x.is_a?(Math::Transform)
        return Native::Graphics.draw_layer_with_transform(texture.__send__(:native), layer.to_i, transform_quad(quad).__send__(:native),
          x.__send__(:native))
      end

      Native::Graphics.draw_layer(texture.__send__(:native), layer.to_i, quad.is_a?(Quad) ? quad.__send__(:native) : nil,
        placement_after(quad, x, y, r, sx, sy, ox, oy, kx, ky))
    end

    # Draws copies of a mesh at once, matching love.graphics.drawInstanced
    # (src/modules/graphics/wrap_Graphics.cpp, w_drawInstanced).
    #
    # [mesh] Lota::Graphics::Mesh to draw.
    # [instancecount] Integer number of copies.
    # [x] Placement as for draw: up to nine numbers, or a
    #   Lota::Math::Transform.
    #
    # A vertex shader tells the copies apart by +gl_InstanceID+, or by an
    # attribute attached to the mesh with +:perinstance+ steps. Returns
    # +nil+. Raises TypeError for a mesh that is not a Mesh or a number of
    # the wrong type, RuntimeError with LÖVE's message when the renderer
    # cannot draw instances, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.draw_instanced(tile, 1000)
    #   Lota::Graphics.draw_instanced(tile, 1000, 100, 100, 0, 2)
    #
    # :call-seq:
    #   draw_instanced(mesh, instancecount, x = 0, y = 0, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
    #   draw_instanced(mesh, instancecount, transform)
    def self.draw_instanced(mesh, instancecount, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil,
      kx = nil, ky = nil
    )
      raise TypeError, "wrong argument type #{mesh.class} (expected Lota::Graphics::Mesh)" unless mesh.is_a?(Mesh)

      if x.is_a?(Math::Transform)
        return Native::Graphics.draw_instanced_with_transform(mesh.__send__(:native), instancecount, x.__send__(:native))
      end

      Native::Graphics.draw_instanced(mesh.__send__(:native), instancecount, standard_placement(x, y, r, sx, sy, ox, oy, kx, ky))
    end

    # Draws a mesh as a buffer of arguments says, matching
    # love.graphics.drawIndirect (src/modules/graphics/wrap_Graphics.cpp,
    # w_drawIndirect).
    #
    # [mesh] Lota::Graphics::Mesh to draw.
    # [argsbuffer] Lota::Graphics::GraphicsBuffer of draw arguments, made with
    #   +indirectarguments: true+.
    # [argsindex] Integer element of it to read, counting from 1.
    # [x] Placement as for draw_instanced.
    #
    # Returns +nil+. Raises what draw_instanced raises, and RuntimeError
    # with LÖVE's message when the renderer cannot draw indirectly.
    #
    # === Example
    #
    #   Lota::Graphics.draw_indirect(tile, arguments, 1, 100, 100)
    #
    # :call-seq:
    #   draw_indirect(mesh, argsbuffer, argsindex, x = 0, y = 0, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
    #   draw_indirect(mesh, argsbuffer, argsindex, transform)
    def self.draw_indirect(mesh, argsbuffer, argsindex, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil,
      oy = nil, kx = nil, ky = nil
    )
      raise TypeError, "wrong argument type #{mesh.class} (expected Lota::Graphics::Mesh)" unless mesh.is_a?(Mesh)
      unless argsbuffer.is_a?(GraphicsBuffer)
        raise TypeError, "wrong argument type #{argsbuffer.class} (expected Lota::Graphics::GraphicsBuffer)"
      end

      if x.is_a?(Math::Transform)
        return Native::Graphics.draw_indirect_with_transform(mesh.__send__(:native), argsbuffer.__send__(:native), argsindex, x.__send__(:native))
      end

      Native::Graphics.draw_indirect(mesh.__send__(:native), argsbuffer.__send__(:native), argsindex,
        standard_placement(x, y, r, sx, sy, ox, oy, kx, ky))
    end

    # Runs a compute shader, matching love.graphics.dispatchThreadgroups
    # (src/modules/graphics/wrap_Graphics.cpp, w_dispatchThreadgroups).
    #
    # [shader] Lota::Graphics::Shader with a compute stage.
    # [x] Integer number of thread groups along x.
    # [y] Integer along y, 1 when left out.
    # [z] Integer along z, 1 when left out.
    #
    # Returns +nil+. Raises TypeError for a shader that is not a Shader,
    # RuntimeError with LÖVE's message for one with no compute stage or a
    # renderer that cannot run it, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.dispatch_threadgroups(simulate, 64)
    def self.dispatch_threadgroups(shader, x, y = nil, z = nil)
      raise TypeError, "wrong argument type #{shader.class} (expected Lota::Graphics::Shader)" unless shader.is_a?(Shader)

      Native::Graphics.dispatch_threadgroups(shader.__send__(:native), x, y, z)
    end

    # Runs a compute shader for the groups a buffer says, matching
    # love.graphics.dispatchIndirect (src/modules/graphics/wrap_Graphics.cpp,
    # w_dispatchIndirect).
    #
    # [shader] Lota::Graphics::Shader with a compute stage.
    # [argsbuffer] Lota::Graphics::GraphicsBuffer of the groups, made with
    #   +indirectarguments: true+.
    # [argsindex] Integer element of it to read, counting from 1, 1 when
    #   left out.
    #
    # Returns +nil+. Raises what dispatch_threadgroups raises.
    #
    # === Example
    #
    #   Lota::Graphics.dispatch_indirect(simulate, groups)
    def self.dispatch_indirect(shader, argsbuffer, argsindex = nil)
      raise TypeError, "wrong argument type #{shader.class} (expected Lota::Graphics::Shader)" unless shader.is_a?(Shader)
      unless argsbuffer.is_a?(GraphicsBuffer)
        raise TypeError, "wrong argument type #{argsbuffer.class} (expected Lota::Graphics::GraphicsBuffer)"
      end

      Native::Graphics.dispatch_indirect(shader.__send__(:native), argsbuffer.__send__(:native), argsindex)
    end

    # Draws with a shader that reads its vertices itself, matching
    # love.graphics.drawFromShader
    # (src/modules/graphics/wrap_Graphics.cpp, w_drawFromShader).
    #
    # [source] A primitive type, such as +:triangles+, to draw +count+
    #   vertices of, or the Lota::Graphics::GraphicsBuffer of indices (made
    #   with +index: true+) to draw +count+ indices of.
    # [count] Integer number of vertices or indices.
    # [instancecount] Integer number of instances; 1 by default.
    # [indexstart] Integer first index to draw, counting from 1, 1 by
    #   default; only with a buffer.
    # [texture] Lota::Graphics::Texture to give the shader as its main
    #   texture, or +nil+. It follows +instancecount+ when +source+ is a
    #   primitive type, and +indexstart+ when it is a buffer.
    #
    # Returns +nil+. Raises TypeError for a texture that is not a Texture,
    # ArgumentError with LÖVE's message for a primitive type that does not
    # exist, RuntimeError with LÖVE's message for a draw the shader or
    # renderer cannot make, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.draw_from_shader(:triangles, 6)
    #   Lota::Graphics.draw_from_shader(indices, 6, 100) # 100 instances
    #
    # Its forms:
    #
    #   draw_from_shader(primitive, vertexcount, instancecount = 1, texture = nil)
    #   draw_from_shader(indexbuffer, indexcount, instancecount = 1, indexstart = 1, texture = nil)
    def self.draw_from_shader(source, count, instancecount = nil, *rest)
      if source.is_a?(GraphicsBuffer)
        indexstart, texture = rest
        Native::Graphics.draw_from_shader_indexed(source.__send__(:native), [count, instancecount, indexstart],
          drawn_texture(texture))
      else
        Native::Graphics.draw_from_shader_primitive(EnumName.of(source), [count, instancecount], drawn_texture(rest.first))
      end
    end

    # Draws with a shader that reads its vertices itself, for the draw a
    # buffer says, matching love.graphics.drawFromShaderIndirect
    # (src/modules/graphics/wrap_Graphics.cpp, w_drawFromShaderIndirect).
    #
    # [source] A primitive type, such as +:triangles+, or the
    #   Lota::Graphics::GraphicsBuffer of indices (made with +index: true+)
    #   to draw.
    # [argsbuffer] Lota::Graphics::GraphicsBuffer of the draw's arguments,
    #   made with +indirectarguments: true+.
    # [argsindex] Integer element of it to read, counting from 1, 1 when
    #   left out.
    # [texture] Lota::Graphics::Texture to give the shader as its main
    #   texture, or +nil+.
    #
    # Returns +nil+. Raises what draw_from_shader raises.
    #
    # === Example
    #
    #   Lota::Graphics.draw_from_shader_indirect(:triangles, arguments)
    def self.draw_from_shader_indirect(source, argsbuffer, argsindex = nil, texture = nil)
      check_buffer(argsbuffer, "argsbuffer")
      args = argsbuffer.__send__(:native)
      if source.is_a?(GraphicsBuffer)
        Native::Graphics.draw_from_shader_indirect_indexed(source.__send__(:native), args, argsindex, drawn_texture(texture))
      else
        Native::Graphics.draw_from_shader_indirect_primitive(EnumName.of(source), args, argsindex, drawn_texture(texture))
      end
    end

    # The engine's Texture of +texture+ when it is one, and +texture+ itself
    # otherwise, nil or a value the engine refuses with TypeError. :nodoc:
    private_class_method def self.drawn_texture(texture)
      texture.is_a?(Texture) ? texture.__send__(:native) : texture
    end

    # The Lota::Graphics::GraphicsBuffer of indices that draws quads from four
    # vertices each, or +nil+ before the window is open, matching love.graphics.getQuadIndexBuffer
    # (src/modules/graphics/wrap_Graphics.cpp, w_getQuadIndexBuffer).
    #
    # === Example
    #
    #   Lota::Graphics.quad_index_buffer.buffer_type?(:index) # => true
    def self.quad_index_buffer
      native = Native::Graphics.quad_index_buffer
      native && GraphicsBuffer.__send__(:from_native, native)
    end

    # The window's width, in units of the screen's DPI scale, matching
    # love.graphics.getWidth (src/modules/graphics/wrap_Graphics.cpp,
    # w_getWidth).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.width # => 800
    def self.width
      Native::Graphics.width
    end

    # The window's height, in units of the screen's DPI scale, matching
    # love.graphics.getHeight (src/modules/graphics/wrap_Graphics.cpp,
    # w_getHeight).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.height # => 600
    def self.height
      Native::Graphics.height
    end

    # The window's width and height, as an Array, matching
    # love.graphics.getDimensions (src/modules/graphics/wrap_Graphics.cpp,
    # w_getDimensions).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   width, height = Lota::Graphics.dimensions # => [800, 600]
    def self.dimensions
      [Native::Graphics.width, Native::Graphics.height]
    end

    # How many pixels the screen has to a unit, as a Float, matching
    # love.graphics.getDPIScale (src/modules/graphics/wrap_Graphics.cpp,
    # w_getDPIScale): 2.0 on most Retina displays, and 1.0 where the
    # window is not high-DPI.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.dpi_scale # => 2.0
    def self.dpi_scale
      Native::Graphics.dpi_scale
    end

    # The window's width in pixels, as an Integer, matching
    # love.graphics.getPixelWidth (src/modules/graphics/wrap_Graphics.cpp,
    # w_getPixelWidth): width times dpi_scale.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.pixel_width # => 1600
    def self.pixel_width
      Native::Graphics.pixel_width
    end

    # The window's height in pixels, as an Integer, matching
    # love.graphics.getPixelHeight (src/modules/graphics/wrap_Graphics.cpp,
    # w_getPixelHeight): height times dpi_scale.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.pixel_height # => 1200
    def self.pixel_height
      Native::Graphics.pixel_height
    end

    # The window's width and height in pixels, as an Array of Integers,
    # matching love.graphics.getPixelDimensions
    # (src/modules/graphics/wrap_Graphics.cpp, w_getPixelDimensions).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   width, height = Lota::Graphics.pixel_dimensions # => [1600, 1200]
    def self.pixel_dimensions
      Native::Graphics.pixel_dimensions
    end

    # Sets the font text is drawn in, matching love.graphics.setFont
    # (src/modules/graphics/wrap_Graphics.cpp, w_setFont).
    #
    # [font] Lota::Graphics::Font.
    #
    # Lota::Graphics.print and Lota::Graphics.printf draw in this font
    # until you set another. Raises TypeError for anything but a Font, and
    # ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.font = Lota::Graphics::Font.new(24)
    def self.font=(font)
      raise TypeError, "wrong argument type #{font.class} (expected Lota::Graphics::Font)" unless font.is_a?(Font)

      Native::Graphics.set_font(font.__send__(:native))
    end

    # The font text is drawn in, matching love.graphics.getFont
    # (src/modules/graphics/wrap_Graphics.cpp, w_getFont).
    #
    # Until you set one, it is LÖVE's default font, Noto Sans at 13 pixels,
    # which LÖVE makes the first time it is asked for. Raises RuntimeError
    # when the window is not open, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.font # => #<Lota::Graphics::Font ...>
    def self.font
      Font.__send__(:from_native, Native::Graphics.font)
    end

    # Makes a Lota::Graphics::Font as Lota::Graphics::Font.new does, draws
    # text in it from now on, and returns it, matching the deprecated
    # love.graphics.setNewFont (src/modules/graphics/wrap_Graphics.cpp,
    # w_setNewFont).
    #
    # It takes what Font.new takes. LÖVE 12 deprecates it with no
    # replacement: make the font once, as a game's load does, and set it
    # with font=, rather than make a new one each time. Prints LÖVE's
    # notice of the deprecation the first time it is called, and raises
    # what Font.new raises.
    #
    # === Example
    #
    #   Lota::Graphics.set_new_font(24) # => a Font, now the font
    def self.set_new_font(*, hinting: nil, dpiscale: nil, sdf: false)
      Deprecation.mark("Lota::Graphics.set_new_font", :function, :noreplacement,
        where: Deprecation.where(caller_locations(1, 1)))
      font = Font.new(*, hinting:, dpiscale:, sdf:)
      self.font = font
      font
    end

    # Draws text in the current font and color, or in a Font given first,
    # matching love.graphics.print (src/modules/graphics/wrap_Graphics.cpp,
    # w_print).
    #
    # [text] String, or an Array of colored text: Strings, each drawn in
    #   the color given by the Array of red, green, blue, and optionally
    #   alpha before it, as love.graphics.print's table of colored text.
    # [font] Lota::Graphics::Font to draw in, before the position, or left
    #   out for the current font.
    # [x] Float or Integer position of the text's left edge; 0 when +nil+
    #   or left out.
    # [y] Float or Integer position of its top edge; 0 likewise.
    # [r] Float angle in radians; 0 likewise.
    # [sx] Float or Integer horizontal scale; 1 likewise.
    # [sy] Float or Integer vertical scale; +sx+ likewise.
    # [ox] Float or Integer horizontal origin offset; 0 likewise.
    # [oy] Float or Integer vertical origin offset; 0 likewise.
    # [kx] Float or Integer horizontal shearing factor; 0 likewise.
    # [ky] Float or Integer vertical shearing factor; 0 likewise.
    #
    # A newline in the text starts a new line. Colored text is multiplied
    # by the current color. LÖVE reads each number as a single-precision
    # float, and so does Lota. A Font given draws this text alone; the
    # current font stays as it was. A Lota::Math::Transform takes the place
    # of the nine numbers, as it does for draw.
    #
    # Raises TypeError for text or a number of the wrong type,
    # ArgumentError for a tenth number, and ThreadError off the main
    # thread.
    #
    # === Examples
    #
    #   Lota::Graphics.print("Score: 100", 10, 10)
    #   Lota::Graphics.print("Score: 100", big_font, 10, 10)
    #   Lota::Graphics.print([[1, 0, 0], "red ", [0, 0, 1], "blue"], 10, 30)
    #   Lota::Graphics.print("Score: 100", big_font, transform)
    #
    # :call-seq:
    #   print(text, font = nil, x = 0, y = 0, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
    #   print(text, font = nil, transform)
    def self.print(text, font = nil, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil, kx = nil,
      ky = nil
    )
      if font.is_a?(Math::Transform)
        return Native::Graphics.print_with_transform(colored_text(text), nil, font.__send__(:native))
      elsif font.is_a?(Font) && x.is_a?(Math::Transform)
        return Native::Graphics.print_with_transform(colored_text(text), font.__send__(:native), x.__send__(:native))
      end

      unless font.is_a?(Font)
        raise ArgumentError, "wrong number of arguments (given 10 numbers, expected 0..9)" unless ky.nil?

        return Native::Graphics.print(colored_text(text), nil,
          placement(number(font || 0), number(x || 0), y, r, sx, sy, ox, oy, kx))
      end

      Native::Graphics.print(colored_text(text), font.__send__(:native), placement(number(x || 0), y || 0, r, sx, sy, ox, oy, kx, ky))
    end

    # Draws text in the current font and color, or in a Font given first,
    # wrapped and aligned within a width, matching love.graphics.printf
    # (src/modules/graphics/wrap_Graphics.cpp, w_printf).
    #
    # [text] String, or an Array of colored text, as for print.
    # [font] Lota::Graphics::Font to draw in, before the position, or left
    #   out for the current font.
    # [x] Float or Integer position of the text's left edge.
    # [y] Float or Integer position of its top edge.
    # [limit] Float or Integer width at which lines wrap, and within which
    #   they are aligned.
    # [align] +:left+ (the default, also when +nil+), +:center+, +:right+,
    #   or +:justify+.
    # [r] Float angle in radians; 0 when +nil+ or left out.
    # [sx] Float or Integer horizontal scale; 1 likewise.
    # [sy] Float or Integer vertical scale; +sx+ likewise.
    # [ox] Float or Integer horizontal origin offset; 0 likewise.
    # [oy] Float or Integer vertical origin offset; 0 likewise.
    # [kx] Float or Integer horizontal shearing factor; 0 likewise.
    # [ky] Float or Integer vertical shearing factor; 0 likewise.
    #
    # Lines break at a newline, and wrap between words that would cross
    # the limit. A Lota::Math::Transform takes the place of the position
    # and the numbers after the alignment.
    #
    # Raises ArgumentError for an unknown alignment or a twelfth argument
    # after the text, TypeError for text or a number of the wrong type,
    # and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.printf("Congratulations!\nYou have finished the game!", 300, 250, 200, :center)
    #   Lota::Graphics.printf("Victory!", big_font, 8, 8, 240, :center)
    #   Lota::Graphics.printf("Victory!", big_font, transform, 240, :center)
    #
    # :call-seq:
    #   printf(text, font = nil, x, y, limit, align = :left, r = 0, sx = 1, sy = sx, ox = 0, oy = 0, kx = 0, ky = 0)
    #   printf(text, font = nil, transform, limit, align = :left)
    def self.printf(text, font, x, y = nil, limit = nil, align = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil,
      kx = nil, ky = nil
    )
      if font.is_a?(Math::Transform)
        return Native::Graphics.printf_with_transform(colored_text(text), nil, font.__send__(:native), number(x), alignment(y))
      elsif font.is_a?(Font) && x.is_a?(Math::Transform)
        return Native::Graphics.printf_with_transform(colored_text(text), font.__send__(:native), x.__send__(:native), number(y),
          alignment(limit))
      end

      arguments = [x, y, limit, align, r, sx, sy, ox, oy, kx, ky]
      unless font.is_a?(Font)
        raise ArgumentError, "wrong number of arguments (given 12 after the text, expected 3..11)" unless ky.nil?

        arguments = [font, *arguments.first(10)]
        font = nil
      end
      x, y, limit, align, r, sx, sy, ox, oy, kx, ky = arguments
      Native::Graphics.printf(colored_text(text), font&.__send__(:native),
        placement(number(x), number(y), optional_number(r), optional_number(sx), optional_number(sy),
          optional_number(ox), optional_number(oy), optional_number(kx), optional_number(ky)),
        number(limit), alignment(align))
    end

    # +value+, a number LÖVE reads with luaL_checknumber, or TypeError.
    private_class_method def self.number(value)
      return value if value.is_a?(Integer) || value.is_a?(Float)

      raise TypeError, "wrong argument type #{value.class} (expected Float or Integer)"
    end

    # +value+, a number LÖVE reads with luaL_optnumber: nil for its
    # default, or TypeError.
    private_class_method def self.optional_number(value)
      value.nil? ? nil : number(value)
    end

    # printf's alignment as the String the engine reads, or nil for its
    # default.
    private_class_method def self.alignment(value)
      case value
      when nil then nil
      when Symbol, String then EnumName.of(value)
      else raise TypeError, "wrong argument type #{value.class} for the alignment (expected Symbol)"
      end
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # luax_checkcoloredstring (src/modules/font/wrap_Font.cpp:33-76): text
    # as parts, each a String and the color it is drawn in, white until a
    # color comes before it, with alpha 1 when left out.
    # Lota::Graphics::Font#wrap reads text as print does. :nodoc:
    private_class_method def self.colored_text(text)
      return [[text, 1.0, 1.0, 1.0, 1.0]] if text.is_a?(String)

      color = [1.0, 1.0, 1.0, 1.0] #: [Float | Integer, Float | Integer, Float | Integer, Float | Integer]
      parts = [] #: Array[[String, Float | Integer, Float | Integer, Float | Integer, Float | Integer]]
      Array(text).each do |part|
        case part
        when Array then color = [part.fetch(0), part.fetch(1), part.fetch(2), part.fetch(3, 1.0)]
        when String then parts << [part, color[0], color[1], color[2], color[3]]
        else raise TypeError, "wrong argument type #{part.class} (expected String or Array)"
        end
      end
      parts
    end

    # The numbers of luax_checkstandardtransform
    # (src/modules/graphics/wrap_SpriteBatch.h:33-64) and w_printf, each
    # taking its default when +nil+: the vertical scale defaults to the
    # horizontal.
    private_class_method def self.placement(x, y, r, sx, sy, ox, oy, kx, ky)
      sx ||= 1
      [x, y, r || 0, sx, sy || sx, ox || 0, oy || 0, kx || 0, ky || 0]
    end

    # The placement luax_checkstandardtransform reads where it finds no
    # Transform: up to nine numbers, the position 0 when +nil+ or left
    # out. More than nine is an ArgumentError, as for any Ruby method.
    # :nodoc:
    private_class_method def self.standard_placement(*numbers)
      raise ArgumentError, "wrong number of arguments (given #{numbers.size}, expected 0..9)" if numbers.size > 9

      x, y, r, sx, sy, ox, oy, kx, ky = numbers
      placement(x || 0, y || 0, r, sx, sy, ox, oy, kx, ky)
    end

    # The placement the numbers after a Quad give, or, when +quad+ is not
    # a Quad, the numbers from +quad+ on, as w_draw and
    # w_SpriteBatch_add_or_set read them (wrap_Graphics.cpp:3245-3263 and
    # wrap_SpriteBatch.cpp:36-44). A +nil+ in place of the quad, with a
    # number after it, is a missing quad, which LÖVE reports as a type
    # error; without a quad there are nine numbers, not ten. The position
    # is 0 when +nil+ or left out. :nodoc:
    private_class_method def self.placement_after(quad, x, y, r, sx, sy, ox, oy, kx, ky)
      return placement(x || 0, y || 0, r, sx, sy, ox, oy, kx, ky) if quad.is_a?(Quad)

      raise TypeError, "wrong argument type nil (expected Lota::Graphics::Quad)" if quad.nil? && !x.nil?
      raise ArgumentError, "wrong number of arguments (given 10 numbers, expected 0..9)" unless ky.nil?

      placement(quad || 0, x || 0, y, r, sx, sy, ox, oy, kx)
    end

    # SPDX-SnippetEnd

    # Sets the filters that textures and fonts made afterward are sampled
    # with, matching love.graphics.setDefaultFilter
    # (src/modules/graphics/wrap_Graphics.cpp, w_setDefaultFilter).
    #
    # [filter] The filter used when drawing smaller, +:linear+ or
    #   +:nearest+; then optionally the one used when drawing larger, the
    #   same as the first when left out; then optionally the Integer
    #   maximum anisotropy, 1 when left out, as one value or an Array.
    #
    # +:nearest+ keeps pixel art's hard edges, and +:linear+ smooths. It
    # starts as +:linear+ for both. LÖVE clamps the anisotropy to 1
    # through 255, and so does Lota. Raises ArgumentError for an unknown
    # filter, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.default_filter = :nearest
    #   Lota::Graphics.default_filter = :linear, :nearest, 4
    def self.default_filter=(filter)
      min, mag, anisotropy = filter.is_a?(Array) ? filter : [filter]
      anisotropy = case anisotropy
      when Integer, Float then anisotropy
      when nil then 1
      else raise TypeError, "wrong argument type #{anisotropy.class} for anisotropy (expected Integer)"
      end
      Native::Graphics.set_default_filter(EnumName.of(min), mag && EnumName.of(mag), anisotropy)
    end

    # The filters textures and fonts are made with, as an Array of the
    # filter used when drawing smaller, the one used when drawing larger,
    # and the Integer maximum anisotropy, matching
    # love.graphics.getDefaultFilter
    # (src/modules/graphics/wrap_Graphics.cpp, w_getDefaultFilter).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   min, mag, anisotropy = Lota::Graphics.default_filter # => [:linear, :linear, 1]
    def self.default_filter
      min, mag, anisotropy = Native::Graphics.default_filter
      [min.to_sym, mag.to_sym, anisotropy]
    end

    # Sets how textures made afterward with mipmaps blend between them,
    # matching love.graphics.setDefaultMipmapFilter
    # (src/modules/graphics/wrap_Graphics.cpp, w_setDefaultMipmapFilter):
    # +:linear+, +:nearest+, or +:none+, alone or in an Array with the
    # Float sharpness (0 by default), or +nil+ for +:none+.
    #
    # It starts as +:linear+. A texture without mipmaps uses none,
    # whatever this says, and Lota::Graphics::Texture#mipmap_filter=
    # changes one texture's. A higher sharpness picks a
    # larger mipmap, as LÖVE negates it into the engine's level-of-detail
    # bias. Raises ArgumentError for an unknown filter, TypeError for a
    # sharpness that is not a number, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.default_mipmap_filter = :linear
    #   Lota::Graphics.default_mipmap_filter = :nearest, 0.5
    #   Lota::Graphics.default_mipmap_filter = nil
    def self.default_mipmap_filter=(filter)
      mode, sharpness = filter.is_a?(Array) ? filter : [filter]
      sharpness = case sharpness
      when Integer, Float then sharpness
      when nil then 0
      else raise TypeError, "wrong argument type #{sharpness.class} for sharpness (expected Float)"
      end
      Native::Graphics.set_default_mipmap_filter(mode && EnumName.of(mode), sharpness)
    end

    # The mipmap filter textures are made with, as a Symbol, and the Float
    # sharpness, as an Array (rule 4 of doc/contributors/design/translation.md),
    # matching love.graphics.getDefaultMipmapFilter
    # (src/modules/graphics/wrap_Graphics.cpp, w_getDefaultMipmapFilter).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   mode, sharpness = Lota::Graphics.default_mipmap_filter # => [:linear, 0.0]
    def self.default_mipmap_filter
      mode, sharpness = Native::Graphics.default_mipmap_filter
      [mode.is_a?(String) ? mode.to_sym : nil, sharpness.to_f]
    end

    # Sets the color the window is cleared to before each frame, matching
    # love.graphics.setBackgroundColor
    # (src/modules/graphics/wrap_Graphics.cpp, w_setBackgroundColor).
    #
    # [color] Red, green, blue, and optionally alpha, each a Float or
    #   Integer from 0 to 1, as several values or one Array; alpha is 1
    #   when left out.
    #
    # It starts as opaque black. Lota's loop clears the window to it at
    # the start of each frame, as LÖVE's does. LÖVE stores each component
    # as a single-precision float, and so does Lota.
    #
    # Raises ArgumentError for any count of components but 3 or 4,
    # TypeError for one that is not a number, and ThreadError off the main
    # thread.
    #
    # === Examples
    #
    #   Lota::Graphics.background_color = 0.1, 0.1, 0.2
    #   Lota::Graphics.background_color = [1, 1, 1, 0]
    def self.background_color=(color)
      components = Array(color)
      unless components.size == 3 || components.size == 4
        raise ArgumentError, "wrong number of arguments (given #{components.size}, expected 3 or 4)"
      end

      Native::Graphics.set_background_color(components.fetch(0), components.fetch(1), components.fetch(2),
        components.fetch(3, 1.0))
    end

    # Sets how what is drawn mixes with what is already there, matching
    # love.graphics.setBlendMode (src/modules/graphics/wrap_Graphics.cpp,
    # w_setBlendMode).
    #
    # [mode] The blend mode, such as +:alpha+, +:add+, +:subtract+,
    #   +:multiply+, +:lighten+, +:darken+, +:screen+, +:replace+, or
    #   +:none+; then optionally how the colors drawn treat alpha,
    #   +:alphamultiply+, the default, or +:premultiplied+, as one value or
    #   an Array.
    #
    # It starts as +:alpha+ with +:alphamultiply+, which draws translucent
    # colors over what is behind them.
    #
    # Raises ArgumentError for an unknown mode, RuntimeError with LÖVE's
    # message for a mode this renderer cannot draw, and ThreadError off the
    # main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.blend_mode = :add
    #   Lota::Graphics.blend_mode = :multiply, :premultiplied
    def self.blend_mode=(mode)
      blend, alpha = Array(mode)
      Native::Graphics.set_blend_mode(EnumName.of(blend), alpha && EnumName.of(alpha))
    end

    # The blend mode and how it treats alpha, as an Array of two Symbols,
    # matching love.graphics.getBlendMode
    # (src/modules/graphics/wrap_Graphics.cpp, w_getBlendMode).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   mode, alphamode = Lota::Graphics.blend_mode # => [:alpha, :alphamultiply]
    def self.blend_mode
      Native::Graphics.blend_mode.map(&:to_sym)
    end

    # Sets how what is drawn mixes with what is already there, by the
    # graphics card's own terms, matching love.graphics.setBlendState
    # (src/modules/graphics/wrap_Graphics.cpp, w_setBlendState).
    #
    # [state] Three values, an operation and a source and a destination
    #   factor, for the color and alpha alike; or six, the color's
    #   operation, the alpha's, the color's source factor, the alpha's, the
    #   color's destination factor, and the alpha's; or +nil+ to turn
    #   blending off. An operation is +:add+, +:subtract+,
    #   +:reversesubtract+, +:min+, or +:max+; a factor is +:zero+, +:one+,
    #   +:srccolor+, +:oneminussrccolor+, +:srcalpha+,
    #   +:oneminussrcalpha+, +:dstcolor+, +:oneminusdstcolor+,
    #   +:dstalpha+, +:oneminusdstalpha+, or +:srcalphasaturated+.
    #
    # Each pixel becomes the operation of the color drawn times its source
    # factor and the color there times its destination factor. A state no
    # blend mode makes is the mode +:custom+ to Lota::Graphics.blend_mode.
    #
    # Raises ArgumentError for an unknown operation or factor or a count
    # of values but 3 or 6, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.blend_state = :add, :one, :zero # as blend_mode = :replace, :premultiplied
    #   Lota::Graphics.blend_state = nil
    def self.blend_state=(state)
      values = Array(state)
      names = if values.first.nil? then [] #: Array[String]
      elsif [3, 6].include?(values.size) then values.map { |value| EnumName.of(value) }
      else raise ArgumentError, "wrong number of arguments (given #{values.size}, expected 3 or 6)"
      end
      Native::Graphics.set_blend_state(names)
    end

    # The blend operations and factors, as an Array of six Symbols in the
    # order blend_state= takes the long form, or of six +nil+ while blending
    # is off, matching love.graphics.getBlendState
    # (src/modules/graphics/wrap_Graphics.cpp, w_getBlendState).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.blend_state # => [:add, :add, :srcalpha, :one, :oneminussrcalpha, :oneminussrcalpha]
    def self.blend_state
      Native::Graphics.blend_state.map { |name| name&.to_sym }
    end

    # Where drawing goes, as an Array (rule 4 of
    # doc/contributors/design/translation.md), matching love.graphics.getCanvas
    # (src/modules/graphics/wrap_Graphics.cpp, w_getCanvas): empty while it goes
    # to the window; the canvases Lota::Graphics.canvas= or set_canvas set, each
    # a Lota::Graphics::Texture, in order; or, where LÖVE returns its table
    # of tables, for a depth and stencil texture, a mipmap but the first,
    # or a texture that is not 2D, one Array of the targets, each its
    # Texture and a Hash of its +layer+ or +face+ and its +mipmap+, as
    # set_canvas takes them, ending in a Hash of the +depthstencil+ target
    # when there is one.
    #
    # Where Lua keeps one result, Ruby takes +.first+, the canvas or +nil+.
    # Each Texture is the same Ruby object that was set. Raises ThreadError
    # off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.canvas = shadow_map
    #   Lota::Graphics.canvas       # => [#<Lota::Graphics::Texture ...>]
    #   Lota::Graphics.canvas.first # => #<Lota::Graphics::Texture ...>
    #
    #   Lota::Graphics.canvas = nil
    #   Lota::Graphics.canvas # => []
    #
    #   Lota::Graphics.set_canvas(table_canvas, 2)
    #   Lota::Graphics.canvas # => [[[#<Lota::Graphics::Texture ...>, {mipmap: 2}]]]
    def self.canvas
      tables, colors, depthstencil = Native::Graphics.canvas
      return colors.map { |fields| Texture.__send__(:from_native, fields.first) } unless tables

      table = colors.map { |fields| target_of(fields) }
      [depthstencil ? table + [{ depthstencil: target_of(depthstencil) }] : table]
    end

    # Sets which color channels drawing writes, matching
    # love.graphics.setColorMask (src/modules/graphics/wrap_Graphics.cpp,
    # w_setColorMask).
    #
    # [mask] Whether red, green, blue, and alpha are written, as four
    #   booleans in one Array or several values; one boolean for all four;
    #   or +nil+ to write every channel again.
    #
    # A channel that is masked keeps what the target already holds there.
    # Every channel is written to start with.
    #
    # Raises ArgumentError for two or three values, and ThreadError off the
    # main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.color_mask = true, true, false, true # leave blue alone
    #   Lota::Graphics.color_mask = nil
    def self.color_mask=(mask)
      r, g, b, a = mask.is_a?(Array) ? mask : [mask]
      Native::Graphics.set_color_mask(r, g, b, a)
    end

    # Which color channels drawing writes, as an Array of four booleans
    # for red, green, blue, and alpha, matching love.graphics.getColorMask
    # (src/modules/graphics/wrap_Graphics.cpp, w_getColorMask).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   r, g, b, a = Lota::Graphics.color_mask # => [true, true, true, true]
    def self.color_mask
      Native::Graphics.color_mask
    end

    # Sets how drawing tests and writes the depth buffer, matching
    # love.graphics.setDepthMode (src/modules/graphics/wrap_Graphics.cpp,
    # w_setDepthMode).
    #
    # [mode] An Array of the compare mode, one of +:equal+, +:notequal+,
    #   +:less+, +:lequal+, +:gequal+, +:greater+, +:never+, or +:always+,
    #   and whether drawing writes its depth; or +nil+ to turn the depth
    #   test off.
    #
    # It starts as +:always+ without writing. Drawing tests and writes
    # depth only on a target with a depth buffer.
    #
    # Raises ArgumentError for an unknown compare mode or one without
    # whether to write, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.depth_mode = :lequal, true
    #   Lota::Graphics.depth_mode = nil
    def self.depth_mode=(mode)
      compare, write = mode
      Native::Graphics.set_depth_mode(compare && EnumName.of(compare), write)
    end

    # The depth test's compare mode and whether drawing writes depth, as
    # an Array of a Symbol and a boolean, matching
    # love.graphics.getDepthMode (src/modules/graphics/wrap_Graphics.cpp,
    # w_getDepthMode).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   comparemode, write = Lota::Graphics.depth_mode # => [:always, false]
    def self.depth_mode
      compare, write = Native::Graphics.depth_mode
      [compare.to_sym, write]
    end

    # Sets which winding of a triangle's vertices counts as its front,
    # matching love.graphics.setFrontFaceWinding
    # (src/modules/graphics/wrap_Graphics.cpp, w_setFrontFaceWinding).
    #
    # [winding] +:ccw+, counterclockwise, the default, or +:cw+.
    #
    # The mesh cull mode removes faces by it.
    #
    # Raises ArgumentError for an unknown winding, and ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Graphics.front_face_winding = :cw
    def self.front_face_winding=(winding)
      Native::Graphics.set_front_face_winding(EnumName.of(winding))
    end

    # Which winding counts as a triangle's front, +:ccw+ or +:cw+,
    # matching love.graphics.getFrontFaceWinding
    # (src/modules/graphics/wrap_Graphics.cpp, w_getFrontFaceWinding).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.front_face_winding # => :ccw
    def self.front_face_winding
      Native::Graphics.front_face_winding.to_sym
    end

    # Sets the shader drawing uses, matching love.graphics.setShader
    # (src/modules/graphics/wrap_Graphics.cpp, w_setShader).
    #
    # [shader] A Lota::Graphics::Shader, or +nil+ for LÖVE's own, which
    #   draws textures and colors as they are.
    #
    # Lota::Graphics.push(:all) saves it and pop restores it. Raises
    # TypeError for anything but a Shader or +nil+, and ThreadError off
    # the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.shader = dissolve
    #   Lota::Graphics.draw(card, 100, 100)
    #   Lota::Graphics.shader = nil
    def self.shader=(shader)
      case shader
      when nil then Native::Graphics.set_shader
      when Shader then Native::Graphics.set_shader(shader.__send__(:native))
      else raise TypeError, "wrong argument type #{shader.class} (expected Lota::Graphics::Shader)"
      end
    end

    # The shader drawing uses, or +nil+ while it uses LÖVE's own,
    # matching love.graphics.getShader
    # (src/modules/graphics/wrap_Graphics.cpp, w_getShader).
    #
    # It is the same Ruby object that was set. Raises ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Graphics.shader # => nil
    def self.shader
      native = Native::Graphics.shader
      native && Shader.__send__(:from_native, native)
    end

    # Whether shader source compiles, matching love.graphics.validateShader
    # (src/modules/graphics/wrap_Graphics.cpp, w_validateShader), without
    # making a shader.
    #
    # [gles] Whether to check it as OpenGL ES would compile it, true or
    #   false.
    # [first] The source, as Lota::Graphics::Shader.new takes it.
    # [second] The other stage's source, or +nil+.
    # [defines] As Lota::Graphics::Shader.new takes them.
    # [debugname] As Lota::Graphics::Shader.new takes it.
    # [write] As Lota::Graphics::Shader.new takes it.
    #
    # Returns an Array of LÖVE's results (rule 4 of
    # doc/contributors/design/translation.md): +[true]+, or +false+ and LÖVE's
    # message, so <tt>.first</tt> is whether it compiles. Raises TypeError for a
    # +gles+ that is not true or false, and as Lota::Graphics::Shader.new raises
    # for its sources and options.
    #
    # === Example
    #
    #   ok, message = Lota::Graphics.validate_shader(false, "nothing here")
    #   ok # => false
    def self.validate_shader(gles, first, second = nil, defines: nil, debugname: nil, write: nil)
      raise TypeError, "wrong argument type #{gles.class} (expected true or false)" unless [true, false].include?(gles)

      stages, pairs, name = Shader.__send__(:source, first, second, defines, debugname)
      Native::Graphics.validate_shader(gles, stages, name, pairs, write ? true : false)
    end

    # Sets how lines are joined where they meet, matching
    # love.graphics.setLineJoin (src/modules/graphics/wrap_Graphics.cpp,
    # w_setLineJoin).
    #
    # [join] +:miter+, the default, extends the edges to a point;
    #   +:bevel+ cuts the corner off; +:none+ leaves each segment's end
    #   square.
    #
    # Raises ArgumentError for an unknown join, and ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Graphics.line_join = :bevel
    def self.line_join=(join)
      Native::Graphics.set_line_join(EnumName.of(join))
    end

    # How lines are joined, +:miter+, +:bevel+, or +:none+, matching
    # love.graphics.getLineJoin (src/modules/graphics/wrap_Graphics.cpp,
    # w_getLineJoin).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.line_join # => :miter
    def self.line_join
      Native::Graphics.line_join.to_sym
    end

    # Sets which faces of a mesh's triangles are left undrawn, matching
    # love.graphics.setMeshCullMode
    # (src/modules/graphics/wrap_Graphics.cpp, w_setMeshCullMode).
    #
    # [mode] +:none+, the default, draws both faces; +:back+ or +:front+
    #   leaves that face out, by the front face winding.
    #
    # Raises ArgumentError for an unknown mode, and ThreadError off the
    # main thread.
    #
    # === Example
    #
    #   Lota::Graphics.mesh_cull_mode = :back
    def self.mesh_cull_mode=(mode)
      Native::Graphics.set_mesh_cull_mode(EnumName.of(mode))
    end

    # Which faces of a mesh are left undrawn, +:none+, +:back+, or
    # +:front+, matching love.graphics.getMeshCullMode
    # (src/modules/graphics/wrap_Graphics.cpp, w_getMeshCullMode).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.mesh_cull_mode # => :none
    def self.mesh_cull_mode
      Native::Graphics.mesh_cull_mode.to_sym
    end

    # Sets the size points are drawn at, matching love.graphics.setPointSize
    # (src/modules/graphics/wrap_Graphics.cpp, w_setPointSize).
    #
    # [size] Float or Integer width of each point, in pixels; it starts
    #   at 1.
    #
    # Raises TypeError for a size that is not a number, and ThreadError
    # off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.point_size = 4
    def self.point_size=(size)
      Native::Graphics.set_point_size(size)
    end

    # The size points are drawn at, as a Float, matching
    # love.graphics.getPointSize (src/modules/graphics/wrap_Graphics.cpp,
    # w_getPointSize).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.point_size # => 1.0
    def self.point_size
      Native::Graphics.point_size
    end

    # Limits drawing to a rectangle, or lets it reach everywhere again,
    # matching love.graphics.setScissor
    # (src/modules/graphics/wrap_Graphics.cpp, w_setScissor).
    #
    # [rect] The x and y of the rectangle's top left, its width, and its
    #   height, as one Array or several values; or +nil+ to stop clipping.
    #
    # The rectangle is in the target's coordinates, which the current
    # transformation does not move. LÖVE reads each side as a single-precision float,
    # and so does Lota. <tt>scissor = nil</tt> is LÖVE's setScissor() with
    # no arguments.
    #
    # Raises ArgumentError for any count of sides but 4, TypeError for a
    # side that is not a number, RuntimeError with LÖVE's message for a
    # negative size, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.scissor = 0, 0, 400, 300
    #   Lota::Graphics.scissor = nil
    def self.scissor=(rect)
      if rect.nil?
        Native::Graphics.reset_scissor
        return
      end

      sides = Array(rect)
      raise ArgumentError, "wrong number of arguments (given #{sides.size}, expected 4)" unless sides.size == 4

      Native::Graphics.set_scissor(number(sides.fetch(0)), number(sides.fetch(1)), number(sides.fetch(2)),
        number(sides.fetch(3)))
    end

    # The rectangle drawing is limited to, as an Array of its x, y, width,
    # and height, or an empty Array when drawing is not limited, matching
    # love.graphics.getScissor (src/modules/graphics/wrap_Graphics.cpp,
    # w_getScissor), which returns no values then.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   x, y, width, height = Lota::Graphics.scissor # => []
    def self.scissor
      Native::Graphics.scissor
    end

    # Limits drawing to where the current scissor and a rectangle overlap,
    # matching love.graphics.intersectScissor
    # (src/modules/graphics/wrap_Graphics.cpp, w_intersectScissor).
    #
    # [x] Float or Integer position of the rectangle's left edge.
    # [y] Float or Integer position of its top edge.
    # [width] Float or Integer width.
    # [height] Float or Integer height.
    #
    # With no scissor set, the rectangle becomes the scissor.
    #
    # Raises TypeError for a side that is not a number, RuntimeError with
    # LÖVE's message for a negative size, and ThreadError off the main
    # thread.
    #
    # === Example
    #
    #   Lota::Graphics.intersect_scissor(0, 0, 4, 4)
    def self.intersect_scissor(x, y, width, height)
      Native::Graphics.intersect_scissor(x, y, width, height)
    end

    # How many pushes are waiting for their pop, as an Integer, matching
    # love.graphics.getStackDepth (src/modules/graphics/wrap_Graphics.cpp,
    # w_getStackDepth).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.push { Lota::Graphics.stack_depth } # => 1
    def self.stack_depth
      Native::Graphics.stack_depth
    end

    # Sets how drawing tests and changes the stencil buffer, or turns the
    # stencil off, matching love.graphics.setStencilState
    # (src/modules/graphics/wrap_Graphics.cpp, w_setStencilState).
    #
    # [state] An Array of what drawing does to the stencil, one of
    #   +:keep+, +:zero+, +:replace+, +:increment+, +:decrement+,
    #   +:incrementwrap+, +:decrementwrap+, or +:invert+; the compare mode
    #   it tests with, as Lota::Graphics.depth_mode= names them; then
    #   optionally the Integer value it compares and writes, 0 when left
    #   out, and the read and write masks, every bit when left out. +nil+
    #   turns the stencil off.
    #
    # It starts as +:keep+ and +:always+ with a value of 0. Drawing tests
    # and changes the stencil only on a target with a stencil buffer.
    #
    # Raises ArgumentError for an unknown action or compare mode or a
    # missing compare mode, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.stencil_state = :replace, :always, 1
    #   Lota::Graphics.stencil_state = :keep, :greater, 0
    #   Lota::Graphics.stencil_state = nil
    def self.stencil_state=(state)
      action, compare, value, read_mask, write_mask = state
      Native::Graphics.set_stencil_state(action && EnumName.of(action), compare && EnumName.of(compare),
        value.nil? ? 0 : integer(value), optional_number(read_mask), optional_number(write_mask))
    end

    # The stencil's action, compare mode, value, read mask, and write
    # mask, as an Array, matching love.graphics.getStencilState
    # (src/modules/graphics/wrap_Graphics.cpp, w_getStencilState).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   action, comparemode, value = Lota::Graphics.stencil_state # => [:keep, :always, 0, ...]
    def self.stencil_state
      action, compare, *numbers = Native::Graphics.stencil_state
      [action.to_sym, compare.to_sym, *numbers]
    end

    # Sets the stencil to one of its common uses, matching
    # love.graphics.setStencilMode (src/modules/graphics/wrap_Graphics.cpp,
    # w_setStencilMode).
    #
    # [mode] +:draw+, which writes the value into the stencil wherever
    #   drawing goes and masks off the color; +:test+, which draws only
    #   where the stencil holds the value; or +:off+; alone or in an Array
    #   with the Integer value, 1 when left out. +nil+ turns the stencil
    #   off.
    #
    # Each mode sets the stencil state and the color mask, which
    # Lota::Graphics.stencil_state and Lota::Graphics.color_mask then
    # report. Drawing tests and changes the stencil only on a target with
    # a stencil buffer.
    #
    # Raises ArgumentError for an unknown mode or a value without one,
    # RuntimeError with LÖVE's message for a canvas without a stencil
    # buffer, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.stencil_mode = :draw
    #   Lota::Graphics.circle(:fill, 100, 100, 50)
    #   Lota::Graphics.stencil_mode = :test
    #   Lota::Graphics.draw(picture) # only inside the circle
    #   Lota::Graphics.stencil_mode = nil
    def self.stencil_mode=(mode)
      name, value = mode.is_a?(Array) ? mode : [mode]
      Native::Graphics.set_stencil_mode(name && EnumName.of(name), value.nil? ? nil : integer(value))
    end

    # The stencil's mode and Integer value, as an Array (rule 4 of
    # doc/contributors/design/translation.md), matching
    # love.graphics.getStencilMode (src/modules/graphics/wrap_Graphics.cpp,
    # w_getStencilMode). The mode is +:custom+ for a stencil state no mode sets.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   mode, value = Lota::Graphics.stencil_mode # => [:off, 0]
    def self.stencil_mode
      mode, value = Native::Graphics.stencil_mode
      [mode.to_sym, value]
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # Draws what the block draws into the stencil buffer, and not to the
    # screen, matching the deprecated love.graphics.stencil, which LÖVE
    # writes in Lua (src/modules/graphics/wrap_Graphics.lua:55-80).
    #
    # [action] How drawing changes the stencil, as
    #   Lota::Graphics.stencil_state= names it; +:replace+ when left out.
    # [value] The Integer value the action uses; 1 when left out.
    # [keepvalues] Whether to keep the stencil's values; when left out, it
    #   clears them to 0 first.
    #
    # It writes with the compare mode +:always+ and the color masked off while
    # the block runs, then puts the stencil state and color mask back, also when
    # the block raises, as LÖVE puts them back before it raises the function's
    # error again. The block is LÖVE's function (rule 12 of
    # doc/contributors/design/translation.md). Lota::Graphics.stencil_mode= and
    # stencil_state= replace it; prints LÖVE's notice of the deprecation the
    # first time it is called.
    #
    # Raises what the block raises, LocalJumpError without a block,
    # RuntimeError with LÖVE's message for a canvas without a stencil
    # buffer, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.stencil { Lota::Graphics.circle(:fill, 100, 100, 50) }
    #   Lota::Graphics.stencil_test = :greater, 0
    def self.stencil(action = nil, value = nil, keepvalues = nil)
      Deprecation.mark("Lota::Graphics.stencil", :function, :replaced, "Lota::Graphics.stencil_mode= or stencil_state=",
        where: Deprecation.where(caller_locations(1, 1)))
      action = :replace if action.nil?
      clear(false, true, false) unless keepvalues
      value = 1 if value.nil?
      state = stencil_state
      mask = color_mask
      self.stencil_state = action, :always, value
      self.color_mask = false
      begin
        yield
      ensure
        self.stencil_state = state
        self.color_mask = mask
      end
    end

    # Draws only where the stencil compares as +test+ says with a value,
    # or everywhere again, matching the deprecated
    # love.graphics.setStencilTest, which LÖVE writes in Lua
    # (src/modules/graphics/wrap_Graphics.lua:82-90).
    #
    # [test] The compare mode, as Lota::Graphics.depth_mode= names them,
    #   alone or in an Array with the Integer value, 0 when left out; or
    #   +nil+ to stop testing the stencil.
    #
    # It sets the stencil state, with the action +:keep+. Lota::Graphics.stencil_mode=
    # and stencil_state= replace it; prints LÖVE's notice of the
    # deprecation the first time it is called. Raises what stencil_state=
    # raises.
    #
    # === Example
    #
    #   Lota::Graphics.stencil_test = :greater, 0
    def self.stencil_test=(test)
      Deprecation.mark("Lota::Graphics.stencil_test=", :function, :replaced,
        "Lota::Graphics.stencil_mode= or stencil_state=", where: Deprecation.where(caller_locations(1, 1)))
      mode, value = test.is_a?(Array) ? test : [test]
      self.stencil_state = mode.nil? ? nil : [:keep, mode, value].compact
    end

    # The stencil's compare mode and Integer value, as an Array (rule 4 of
    # doc/contributors/design/translation.md), matching the deprecated
    # love.graphics.getStencilTest, which LÖVE writes in Lua
    # (src/modules/graphics/wrap_Graphics.lua:92-96).
    #
    # Lota::Graphics.stencil_mode and stencil_state replace it; prints
    # LÖVE's notice of the deprecation the first time it is called. Raises
    # ThreadError off the main thread.
    #
    # === Example
    #
    #   mode, value = Lota::Graphics.stencil_test # => [:always, 0]
    def self.stencil_test
      Deprecation.mark("Lota::Graphics.stencil_test", :function, :replaced, "Lota::Graphics.stencil_mode or stencil_state",
        where: Deprecation.where(caller_locations(1, 1)))
      state = stencil_state
      [state.fetch(1), state.fetch(2)]
    end

    # SPDX-SnippetEnd

    # Whether colors are blended in linear space, as a game asks with
    # +t.gammacorrect+, matching love.graphics.isGammaCorrect
    # (src/modules/graphics/wrap_Graphics.cpp, w_isGammaCorrect).
    #
    # === Example
    #
    #   Lota::Graphics.gamma_correct? # => false
    def self.gamma_correct?
      Native::Graphics.gamma_correct?
    end

    # Whether the game asked for the computer's integrated graphics over a
    # faster, hungrier card, with +t.graphics.lowpower+, matching
    # love.graphics.isLowPowerPreferred
    # (src/modules/graphics/wrap_Graphics.cpp, w_isLowPowerPreferred).
    #
    # === Example
    #
    #   Lota::Graphics.low_power_preferred? # => false
    def self.low_power_preferred?
      Native::Graphics.low_power_preferred?
    end

    # Sets whether shapes are drawn as the outlines of their triangles,
    # matching love.graphics.setWireframe
    # (src/modules/graphics/wrap_Graphics.cpp, w_setWireframe).
    #
    # [enable] +true+ to draw wireframes, +false+ to draw shapes whole, as
    #   they start.
    #
    # OpenGL ES has no wireframes, and LÖVE leaves it unchanged there.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.wireframe = true
    def self.wireframe=(enable)
      Native::Graphics.set_wireframe(enable)
    end

    # Whether shapes are drawn as wireframes, matching
    # love.graphics.isWireframe (src/modules/graphics/wrap_Graphics.cpp,
    # w_isWireframe).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.wireframe? # => false
    def self.wireframe?
      Native::Graphics.wireframe?
    end

    # The renderer's name, version, vendor, and device, as an Array of
    # four Strings, matching love.graphics.getRendererInfo
    # (src/modules/graphics/wrap_Graphics.cpp, w_getRendererInfo).
    #
    # The name is the renderer's, such as +"Metal"+ on macOS or
    # +"OpenGL"+ on Linux; the rest are what the driver reports.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   name, version, vendor, device = Lota::Graphics.renderer_info
    def self.renderer_info
      Native::Graphics.renderer_info
    end

    # The renderer's counts, as a frozen Lota::Graphics::Stats, matching
    # love.graphics.getStats (src/modules/graphics/wrap_Graphics.cpp,
    # w_getStats). LÖVE also fills in a table it is given; a frozen record
    # cannot be filled, so Lota takes none (rule 29 of
    # doc/contributors/design/translation.md).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.stats.drawcalls # => 12
    def self.stats
      Stats.new(**Native::Graphics.stats.transform_keys(&:to_sym))
    end

    # Which optional features the renderer has, as a frozen
    # Lota::Graphics::Supported, matching love.graphics.getSupported
    # (src/modules/graphics/wrap_Graphics.cpp, w_getSupported).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.supported.instancing # => true
    def self.supported
      Supported.new(**Native::Graphics.supported.transform_keys(&:to_sym))
    end

    # The renderer's limits, as a frozen Lota::Graphics::SystemLimits,
    # matching love.graphics.getSystemLimits
    # (src/modules/graphics/wrap_Graphics.cpp, w_getSystemLimits).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.system_limits.texturesize # => 16384.0
    def self.system_limits
      SystemLimits.new(**Native::Graphics.system_limits.transform_keys(&:to_sym))
    end

    # Which pixel formats a texture with these settings can have, as a
    # frozen Lota::Graphics::TextureFormats, matching
    # love.graphics.getTextureFormats
    # (src/modules/graphics/wrap_Graphics.cpp, w_getTextureFormats), whose
    # table of settings becomes keywords (rule 10 of
    # doc/contributors/design/translation.md).
    #
    # [canvas] +true+ or +false+: whether the texture is to be drawn
    #   into; required, as LÖVE requires it.
    # [computewrite] Whether compute shaders are to write to it.
    # [shaderatomics] Whether shaders are to use atomic operations on it.
    # [readable] +true+, +false+, or +nil+: whether shaders are to read
    #   it; when +nil+, true for every format but the depth and stencil
    #   formats.
    #
    # Raises TypeError when +canvas+, or +readable+ when given, is not
    # +true+ or +false+, as LÖVE raises, and ThreadError off the main
    # thread.
    #
    # === Example
    #
    #   Lota::Graphics.texture_formats(canvas: true).rgba16f # => true
    def self.texture_formats(canvas:, computewrite: false, shaderatomics: false, readable: nil)
      boolean!(:canvas, canvas)
      boolean!(:readable, readable) unless readable.nil?
      formats = Native::Graphics.texture_formats(canvas, computewrite ? true : false, shaderatomics ? true : false,
        readable)
      TextureFormats.new(**formats.transform_keys(&:to_sym))
    end

    # Which pixel formats a canvas can have, as a frozen
    # Lota::Graphics::CanvasFormats, matching the deprecated
    # love.graphics.getCanvasFormats
    # (src/modules/graphics/wrap_Graphics.cpp, w_getCanvasFormats).
    #
    # [readable] +true+ or +false+: whether shaders are to read the canvas;
    #   when left out or anything else, true for every format but the
    #   depth and stencil formats. LÖVE's table to fill in is dropped
    #   (rule 29 of doc/contributors/design/translation.md).
    #
    # Compressed formats, which no canvas can have, are left out.
    # Lota::Graphics.texture_formats replaces it; prints LÖVE's notice of
    # the deprecation the first time it is called. Raises ThreadError off
    # the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.canvas_formats.rgba16f # => true
    def self.canvas_formats(readable = nil)
      Deprecation.mark("Lota::Graphics.canvas_formats", :function, :replaced, "Lota::Graphics.texture_formats",
        where: Deprecation.where(caller_locations(1, 1)))
      flag = if readable == true then true
      elsif readable == false then false
      end
      formats = Native::Graphics.canvas_formats(flag)
      CanvasFormats.new(**formats.transform_keys(&:to_sym))
    end

    # Which pixel formats a texture can be drawn from, as a frozen
    # Lota::Graphics::ImageFormats, matching the deprecated
    # love.graphics.getImageFormats
    # (src/modules/graphics/wrap_Graphics.cpp, w_getImageFormats).
    #
    # The depth and stencil formats, which no image holds, are left out.
    # Lota::Graphics.texture_formats replaces it; prints LÖVE's notice of
    # the deprecation the first time it is called. Raises ThreadError off
    # the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.image_formats["DXT1"] # => false
    def self.image_formats
      Deprecation.mark("Lota::Graphics.image_formats", :function, :replaced, "Lota::Graphics.texture_formats",
        where: Deprecation.where(caller_locations(1, 1)))
      ImageFormats.new(**Native::Graphics.image_formats.transform_keys(&:to_sym))
    end

    # luax_checkboolflag and luax_checkboolean (src/common/runtime.cpp):
    # +value+ must be +true+ or +false+, where luax_boolflag would take
    # any value's truthiness. :nodoc:
    private_class_method def self.boolean!(name, value)
      return if [true, false].include?(value)

      raise TypeError, "wrong argument type #{value.class} for #{name} (expected true or false)"
    end

    # Which types of texture the renderer has, as a frozen
    # Lota::Graphics::TextureTypes, matching love.graphics.getTextureTypes
    # (src/modules/graphics/wrap_Graphics.cpp, w_getTextureTypes).
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.texture_types["2d"] # => true
    def self.texture_types
      TextureTypes.new(**Native::Graphics.texture_types.transform_keys(&:to_sym))
    end

    # Draws what LÖVE has batched so far, matching love.graphics.flushBatch
    # (src/modules/graphics/wrap_Graphics.cpp, w_flushBatch). LÖVE draws a
    # batch on its own when it must; a game flushes only to measure, or to
    # order its own rendering.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.flush_batch
    def self.flush_batch
      Native::Graphics.flush_batch
    end

    # Captures the next frame the window shows, matching
    # love.graphics.captureScreenshot
    # (src/modules/graphics/wrap_Graphics.cpp, w_captureScreenshot).
    #
    # [target] A String file name, to save the frame in the save
    #   directory, in the format its extension names (+png+ or +tga+); or
    #   any object that answers +call+, or a block, which LÖVE keeps to
    #   call with the frame as a Lota::Image::ImageData (rule 31 of
    #   doc/contributors/design/translation.md), as Signal.trap keeps its
    #   handler.
    #
    # The capture happens once the frame is presented, at the end of the
    # loop's draw. LÖVE prints, rather than raises, an error in saving the
    # file, and so does Lota; an error the callable raises comes out of
    # Lota::Graphics.present. LÖVE also sends the frame to a Channel, a form
    # that waits for Lota's counterpart of love.thread. Raises ArgumentError for an
    # extension LÖVE cannot encode, or for both a target and a block,
    # TypeError for a target that is neither, and ThreadError off the main
    # thread.
    #
    # === Examples
    #
    #   Lota::Graphics.capture_screenshot("screenshot.png")
    #   Lota::Graphics.capture_screenshot { |image_data| frames << image_data }
    def self.capture_screenshot(target = nil, &block)
      raise ArgumentError, "wrong number of arguments (given 1 and a block, expected 1 or a block)" if target && block

      case (callable = block || target)
      when String then Native::Graphics.capture_screenshot_to_file(callable)
      when nil then raise TypeError, "wrong argument type NilClass (expected String or an object that answers call)"
      else
        unless callable.respond_to?(:call)
          raise TypeError, "wrong argument type #{callable.class} (expected String or an object that answers call)"
        end

        Native::Graphics.capture_screenshot(-> (image) { callable.call(Lota::Image::ImageData.__send__(:from_native, image)) })
      end
    end

    # Draws points in the current color and point size, matching
    # love.graphics.points (src/modules/graphics/wrap_Graphics.cpp,
    # w_points).
    #
    # [points] The x and y of each point in turn, as numbers or as one
    #   Array of them; or one Array of Arrays, one for each point, of its x
    #   and y and optionally the red, green, blue, and alpha, from 0 to 1,
    #   that it is drawn in (1 for each that is left out).
    #
    # LÖVE reads each coordinate as a single-precision float, and so does
    # Lota.
    #
    # Raises RuntimeError with LÖVE's message for an odd count of
    # coordinates, TypeError for a coordinate that is not a number or a
    # point that is not an Array, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.points(10, 10, 20, 20)
    #   Lota::Graphics.points([1, 1, 7, 7, 14, 1])
    #   Lota::Graphics.points([[1, 1, 1, 0, 0], [7, 7, 0, 1, 0, 0.5]])
    def self.points(*points)
      rows = points.first
      return Native::Graphics.points_with_colors(rows) if points.size == 1 && rows.is_a?(Array) && rows.first.is_a?(Array)

      Native::Graphics.points(coordinates(points))
    end

    # Draws a polygon in the current color, matching
    # love.graphics.polygon (src/modules/graphics/wrap_Graphics.cpp,
    # w_polygon).
    #
    # [mode] +:fill+ to fill it, or +:line+ to draw its outline.
    # [vertices] The x and y of each vertex in turn, at least three
    #   vertices, as numbers or as one Array of them.
    #
    # The last vertex joins the first. LÖVE fills a polygon as a fan of
    # triangles from its first vertex, so a filled polygon draws as
    # expected only when it is convex. LÖVE reads each coordinate as a
    # single-precision float, and so does Lota.
    #
    # Raises ArgumentError for an unknown +mode+, RuntimeError with LÖVE's
    # message for an odd count of coordinates or fewer than three
    # vertices, TypeError for a coordinate that is not a number, and
    # ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.polygon(:fill, 100, 100, 200, 100, 150, 200)
    #   Lota::Graphics.polygon(:line, [0, 0, 16, 0, 8, 16])
    def self.polygon(mode, *vertices)
      Native::Graphics.polygon(EnumName.of(mode), coordinates(vertices))
    end

    # The coordinates in +values+, given as numbers or as one Array of
    # them, as w_points and w_polygon read a single table argument in
    # place of the numbers. :nodoc:
    private_class_method def self.coordinates(values)
      first = values.first
      return first if values.size == 1 && first.is_a?(Array)

      values.map { |value| number(value) }
    end

    # +value+, a number LÖVE reads with luaL_optinteger, which LuaJIT cuts
    # to the whole number toward 0, or TypeError.
    private_class_method def self.integer(value)
      case value
      when Integer then value
      when Float then value.truncate
      else raise TypeError, "wrong argument type #{value.class} (expected Integer)"
      end
    end
  end
end
