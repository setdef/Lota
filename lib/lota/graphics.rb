# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "graphics/texture"
require_relative "graphics/canvas"
require_relative "graphics/font"

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
    #   Lota::Graphics::Canvas.new, or +nil+ for the window.
    #
    # Everything drawn or cleared afterward lands on the canvas until you
    # set another target. The engine holds on to the active canvas, so it
    # survives even if you drop every reference to it. A canvas cannot be
    # drawn while it is the target. <tt>canvas = nil</tt> is LÖVE's
    # setCanvas() with no arguments. LÖVE also takes several canvases at
    # once, a mipmap level, and a table of options; Lota binds those forms
    # later.
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
      if canvas
        Native::Graphics.set_canvas(canvas.native)
      else
        Native::Graphics.reset_canvas
      end
    end

    # Fills the active canvas, or the window, with one color, matching
    # love.graphics.clear (src/modules/graphics/wrap_Graphics.cpp, w_clear).
    #
    # [red] Float or Integer, from 0 to 1.
    # [green] Float or Integer, from 0 to 1.
    # [blue] Float or Integer, from 0 to 1.
    # [alpha] Float or Integer, from 0 to 1; 1 when left out.
    #
    # With no arguments it clears to transparent black. Either way it also
    # clears the stencil buffer to 0 and the depth buffer to 1. LÖVE
    # reads each component as a single-precision float, and so does Lota.
    # The scissor rectangle, once Lota binds it, bounds what gets cleared.
    # LÖVE also clears several canvases to different colors and chooses
    # whether to clear stencil and depth; Lota binds those forms later.
    #
    # Raises ArgumentError for any count of components but 0, 3, or 4, and
    # ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.clear(0.1, 0.1, 0.2)    # a dark blue background
    #   Lota::Graphics.clear(1, 1, 0, 0.5)     # half-transparent yellow
    #   Lota::Graphics.clear                   # transparent black
    def self.clear(*color)
      case color.size
      when 0 then Native::Graphics.clear(0.0, 0.0, 0.0, 0.0)
      when 3, 4 then Native::Graphics.clear(color.fetch(0), color.fetch(1), color.fetch(2), color.fetch(3, 1.0))
      else raise ArgumentError, "wrong number of arguments (given #{color.size}, expected 0, 3, or 4)"
      end
    end

    # Copies every pixel of +texture+ back from the graphics card into a
    # new Lota::Image::ImageData, matching love.graphics.readbackTexture
    # (src/modules/graphics/wrap_Graphics.cpp, w_readbackTexture).
    #
    # [texture] Lota::Graphics::Texture to read, such as a canvas.
    #
    # The copy waits for the graphics card to finish drawing, so it is
    # slow; read back for tests, screenshots, and tools, not every frame.
    # LÖVE also reads one slice, mipmap, or rectangle, and into an
    # ImageData you already have; Lota binds those forms later.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   pixels = Lota::Graphics.readback_texture(canvas)
    #   pixels.pixel(0, 0) # => [1.0, 1.0, 0.0, 1.0]
    def self.readback_texture(texture)
      Image::ImageData.from_native(Native::Graphics.readback_texture(texture.native))
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
    #   Integer from 0 to 1, as several values or one Array; alpha is 1
    #   when left out.
    #
    # Shapes take this color as they are drawn, and keep it, so set it
    # before each thing you draw in a different color. It starts as opaque
    # white. LÖVE stores each component as a single-precision float,
    # clamped to 0 through 1, and so does Lota.
    #
    # Raises ArgumentError for any count of components but 3 or 4,
    # TypeError for one that is not a number, and ThreadError off the main
    # thread.
    #
    # === Examples
    #
    #   Lota::Graphics.color = 1, 0, 0       # opaque red
    #   Lota::Graphics.color = 0, 0, 1, 0.5  # half-transparent blue
    #   Lota::Graphics.color = [1, 1, 1]     # an Array works too
    def self.color=(color)
      components = Array(color)
      unless components.size == 3 || components.size == 4
        raise ArgumentError, "wrong number of arguments (given #{components.size}, expected 3 or 4)"
      end

      Native::Graphics.set_color(components.fetch(0), components.fetch(1), components.fetch(2),
        components.fetch(3, 1.0))
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
      Native::Graphics.set_line_style(style.to_s)
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
    #
    # Positions and sizes are in the current coordinate system, which
    # starts as the window's or the canvas's pixels, with (0, 0) at the
    # top left. LÖVE reads each as a single-precision float, and so does
    # Lota. LÖVE also rounds the corners with radii and a count of
    # segments; Lota binds that form later.
    #
    # Raises ArgumentError for an unknown +mode+, TypeError for a position
    # or size that is not a number, and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.rectangle(:fill, 100, 100, 50, 30)
    #   Lota::Graphics.rectangle(:line, 500, 500, 70, 20)
    def self.rectangle(mode, x, y, width, height)
      Native::Graphics.rectangle(mode.to_s, x, y, width, height)
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
      Native::Graphics.circle(mode.to_s, x, y, radius, segments)
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

      Native::Graphics.set_font(font.native)
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
      Font.from_native(Native::Graphics.font)
    end

    # Draws text in the current font and color, matching
    # love.graphics.print (src/modules/graphics/wrap_Graphics.cpp,
    # w_print).
    #
    # [text] String, or an Array of colored text: Strings, each drawn in
    #   the color given by the Array of red, green, blue, and optionally
    #   alpha before it, as love.graphics.print's table of colored text.
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
    # float, and so does Lota. LÖVE also draws in a Font given before the
    # position, and places text with a Transform; Lota binds those forms
    # later.
    #
    # Raises TypeError for text or a number of the wrong type, and
    # ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.print("Score: 100", 10, 10)
    #   Lota::Graphics.print([[1, 0, 0], "red ", [0, 0, 1], "blue"], 10, 30)
    def self.print(text, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil, kx = nil, ky = nil)
      Native::Graphics.print(colored_text(text), placement(x || 0, y || 0, r, sx, sy, ox, oy, kx, ky))
    end

    # Draws text in the current font and color, wrapped and aligned within
    # a width, matching love.graphics.printf
    # (src/modules/graphics/wrap_Graphics.cpp, w_printf).
    #
    # [text] String, or an Array of colored text, as for print.
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
    # the limit. LÖVE also draws in a Font given before the position, and
    # places text with a Transform; Lota binds those forms later.
    #
    # Raises ArgumentError for an unknown alignment, TypeError for text or
    # a number of the wrong type, and ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.printf("Congratulations!\nYou have finished the game!", 300, 250, 200, :center)
    def self.printf(text, x, y, limit, align = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil, kx = nil,
      ky = nil
    )
      Native::Graphics.printf(colored_text(text), placement(x, y, r, sx, sy, ox, oy, kx, ky), limit, align&.to_s)
    end

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # luax_checkcoloredstring (src/modules/font/wrap_Font.cpp:33-76): text
    # as parts, each a String and the color it is drawn in, white until a
    # color comes before it, with alpha 1 when left out.
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
      Native::Graphics.set_default_filter(min.to_s, mag&.to_s, anisotropy)
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
  end
end
