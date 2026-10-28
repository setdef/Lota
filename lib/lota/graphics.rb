# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "graphics/texture"
require_relative "graphics/canvas"
require_relative "graphics/font"
require_relative "graphics/image"
require_relative "graphics/quad"
require_relative "graphics/sprite_batch"

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
      Lota::Image::ImageData.from_native(Native::Graphics.readback_texture(texture.native))
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
    # what the block returns (ADR 001, rule 11).
    #
    # [stack] +:transform+ (the default, also when +nil+) saves the
    #   transformation alone, and +:all+ the color, font, canvas, and the
    #   rest of the state too.
    #
    # LÖVE also applies a Transform given after the stack type; Lota binds
    # that form with Transform. Raises ArgumentError for an unknown stack
    # type, RuntimeError (<tt>"Maximum stack depth reached (more pushes
    # than pops?)"</tt>) past LÖVE's depth of 128, and ThreadError off the
    # main thread.
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
    def self.push(stack = nil)
      Native::Graphics.push(stack && EnumName.of(stack))
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
    # The current color tints what is drawn, so white draws it as it is.
    # LÖVE reads each number as a single-precision float, and so does
    # Lota. LÖVE also places a drawable with a Transform, and draws meshes,
    # text, and its other drawables; Lota binds those forms later.
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
    def self.draw(drawable, quad = nil, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil, kx = nil, ky = nil)
      placement = placement_after(quad, x, y, r, sx, sy, ox, oy, kx, ky)
      if quad.is_a?(Quad)
        raise TypeError, "wrong argument type #{drawable.class} (expected Lota::Graphics::Texture)" unless drawable.is_a?(Texture)

        return Native::Graphics.draw_quad(drawable.native, quad.native, placement)
      end

      case drawable
      when Texture then Native::Graphics.draw(drawable.native, placement)
      when SpriteBatch then Native::Graphics.draw_sprite_batch(drawable.native, placement)
      else
        raise TypeError,
          "wrong argument type #{drawable.class} (expected Lota::Graphics::Texture or Lota::Graphics::SpriteBatch)"
      end
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
    # current font stays as it was. LÖVE also places text with a
    # Transform; Lota binds that form later.
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
    def self.print(text, font = nil, x = nil, y = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil, kx = nil,
      ky = nil
    )
      unless font.is_a?(Font)
        raise ArgumentError, "wrong number of arguments (given 10 numbers, expected 0..9)" unless ky.nil?

        return Native::Graphics.print(colored_text(text), nil,
          placement(number(font || 0), number(x || 0), y, r, sx, sy, ox, oy, kx))
      end

      Native::Graphics.print(colored_text(text), font.native, placement(x || 0, y || 0, r, sx, sy, ox, oy, kx, ky))
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
    # the limit. LÖVE also places text with a Transform; Lota binds that
    # form later.
    #
    # Raises ArgumentError for an unknown alignment or a twelfth argument
    # after the text, TypeError for text or a number of the wrong type,
    # and ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.printf("Congratulations!\nYou have finished the game!", 300, 250, 200, :center)
    #   Lota::Graphics.printf("Victory!", big_font, 8, 8, 240, :center)
    def self.printf(text, font, x, y, limit = nil, align = nil, r = nil, sx = nil, sy = nil, ox = nil, oy = nil,
      kx = nil, ky = nil
    )
      arguments = [x, y, limit, align, r, sx, sy, ox, oy, kx, ky]
      unless font.is_a?(Font)
        raise ArgumentError, "wrong number of arguments (given 12 after the text, expected 3..11)" unless ky.nil?

        arguments = [font, *arguments.first(10)]
        font = nil
      end
      x, y, limit, align, r, sx, sy, ox, oy, kx, ky = arguments
      Native::Graphics.printf(colored_text(text), font&.native,
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

    # The placement the numbers after a Quad give, or, when +quad+ is not
    # a Quad, the numbers from +quad+ on, as w_draw and
    # w_SpriteBatch_add_or_set read them (wrap_Graphics.cpp:3245-3263 and
    # wrap_SpriteBatch.cpp:36-44). A +nil+ in place of the quad, with a
    # number after it, is a missing quad, which LÖVE reports as a type
    # error; without a quad there are nine numbers, not ten. The position
    # is 0 when +nil+ or left out. :nodoc:
    def self.placement_after(quad, x, y, r, sx, sy, ox, oy, kx, ky)
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

    # The canvas drawing goes to, or +nil+ while it goes to the window,
    # matching love.graphics.getCanvas
    # (src/modules/graphics/wrap_Graphics.cpp, w_getCanvas).
    #
    # It is the Lota::Graphics::Texture that Lota::Graphics.canvas= set.
    # LÖVE also returns several canvases, or a table describing them, for
    # the forms of setCanvas that set those; Lota binds them later.
    #
    # Raises ThreadError off the main thread.
    #
    # === Example
    #
    #   Lota::Graphics.canvas = shadow_map
    #   Lota::Graphics.canvas # => #<Lota::Graphics::Texture ...>
    def self.canvas
      native = Native::Graphics.canvas
      native && Texture.from_native(native)
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

    # Draws points in the current color and point size, matching
    # love.graphics.points (src/modules/graphics/wrap_Graphics.cpp,
    # w_points).
    #
    # [points] The x and y of each point in turn, as numbers or as one
    #   Array of them.
    #
    # LÖVE reads each coordinate as a single-precision float, and so does
    # Lota. LÖVE also takes a table of points with a color each; Lota
    # binds that form later.
    #
    # Raises RuntimeError with LÖVE's message for an odd count of
    # coordinates, TypeError for a coordinate that is not a number, and
    # ThreadError off the main thread.
    #
    # === Examples
    #
    #   Lota::Graphics.points(10, 10, 20, 20)
    #   Lota::Graphics.points([1, 1, 7, 7, 14, 1])
    def self.points(*points)
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

    # +value+, a number LÖVE reads with luaL_checkinteger, or TypeError.
    private_class_method def self.integer(value)
      return value if value.is_a?(Integer)

      raise TypeError, "wrong argument type #{value.class} (expected Integer)"
    end
  end
end
