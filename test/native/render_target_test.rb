# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/lovetest_helper"

# The forms of love.graphics.setCanvas (wrap_Graphics.cpp:274-378),
# readbackTexture (lines 2411-2449), draw with a Transform, drawLayer
# (lines 3281-3313), and Texture:replacePixels (wrap_Texture.cpp:375-428),
# beyond what Lövetest's tests for them check
# (test/lovetest/tests/graphics.rb).
class RenderTargetTest < Minitest::Test
  Graphics = Lota::Graphics
  RED = [1.0, 0.0, 0.0, 1.0].freeze
  GREEN = [0.0, 1.0, 0.0, 1.0].freeze
  CLEAR = [0.0, 0.0, 0.0, 0.0].freeze

  def setup
    EngineHelper.open_window
    Graphics.color = 1, 1, 1, 1
  end

  def teardown
    Graphics.set_canvas
    Graphics.stencil_state = nil
  end

  def pixel(texture, *readback)
    Graphics.readback_texture(texture, *readback).pixel(0, 0)
  end

  def test_clear_fills_every_canvas_set_together
    first = Graphics::Canvas.new(2, 2)
    second = Graphics::Canvas.new(2, 2)
    Graphics.set_canvas(first, second)
    Graphics.clear(1, 0, 0, 1)
    Graphics.set_canvas([first, second], depth: true)
    Graphics.clear(0, 1, 0, 1)
    Graphics.set_canvas

    assert_equal [GREEN, GREEN], [pixel(first), pixel(second)]
  end

  def test_canvas_writes_several_canvases_as_set_canvas
    first = Graphics::Canvas.new(2, 2)
    second = Graphics::Canvas.new(2, 2)
    Graphics.canvas = first, second
    Graphics.clear(1, 0, 0, 1)
    Graphics.canvas = nil

    assert_equal [RED, RED], [pixel(first), pixel(second)]
    assert_empty Graphics.canvas
  end

  def test_a_number_after_a_canvas_is_its_mipmap
    canvas = Graphics::Canvas.new(4, 4, mipmaps: :manual)
    Graphics.set_canvas(canvas, 2)
    Graphics.clear(1, 0, 0, 1)
    Graphics.set_canvas

    assert_equal [CLEAR, RED], [pixel(canvas), pixel(canvas, nil, 2)]
  end

  def test_a_layered_canvas_takes_its_layer
    canvas = Graphics::Canvas.new(2, 2, 3)
    Graphics.set_canvas(canvas, 2)
    Graphics.clear(1, 0, 0, 1)
    Graphics.set_canvas

    assert_equal [CLEAR, RED], [pixel(canvas, 1), pixel(canvas, 2)]
  end

  def test_a_layered_canvas_needs_the_table_of_tables_with_options
    canvas = Graphics::Canvas.new(2, 2, 3)
    error = assert_raises(RuntimeError) { Graphics.set_canvas(canvas, stencil: true) }

    assert_equal "Non-2D textures must use the table-of-tables variant of setCanvas.", error.message
  end

  def test_only_the_first_of_several_targets_may_be_layered
    flat = Graphics::Canvas.new(2, 2)
    error = assert_raises(RuntimeError) { Graphics.set_canvas(flat, Graphics::Canvas.new(2, 2, 2)) }

    assert_equal "This variant of setCanvas only supports 2D texture types.", error.message
  end

  # setCanvas's table of tables: each target an Array of its texture and
  # a Hash of its layer, face, and mipmap (ADR 001, rule 10).
  def test_targets_with_their_layer_and_mipmap
    layers = Graphics::Canvas.new(2, 2, 3)
    flat = Graphics::Canvas.new(4, 4, mipmaps: :manual)
    Graphics.set_canvas([[layers, layer: 3], [flat, mipmap: 2]])
    Graphics.clear(1, 0, 0, 1)
    Graphics.set_canvas

    assert_equal [CLEAR, RED], [pixel(layers, 1), pixel(layers, 3)]
    assert_equal [CLEAR, RED], [pixel(flat), pixel(flat, nil, 2)]
  end

  def test_a_layered_target_needs_its_layer
    layers = Graphics::Canvas.new(2, 2, 3)
    error = assert_raises(ArgumentError) { Graphics.set_canvas([[layers, mipmap: 1]]) }

    assert_equal "expected integer field 'layer' in table", error.message
  end

  def test_a_depth_stencil_target_takes_its_options_too
    canvas = Graphics::Canvas.new(4, 4)
    stencil = Graphics::Canvas.new(4, 4, format: :stencil8)
    Graphics.set_canvas([[canvas]], depthstencil: [stencil, mipmap: 1])

    assert_equal [[[canvas, { mipmap: 1 }], { depthstencil: [stencil, { mipmap: 1 }] }]], Graphics.canvas
  end

  # getCanvas returns each 2D canvas at its first mipmap as a value of its
  # own, and every other set of targets as one table, so Lota returns an
  # Array of them either way (ADR 001, rule 4).
  def test_canvas_returns_what_love_returns_as_an_array
    first = Graphics::Canvas.new(2, 2)
    second = Graphics::Canvas.new(2, 2)
    layers = Graphics::Canvas.new(2, 2, 3)

    Graphics.set_canvas(first, second)
    assert_equal [first, second], Graphics.canvas
    Graphics.set_canvas(layers, 2)
    assert_equal [[[layers, { layer: 2, mipmap: 1 }]]], Graphics.canvas
    Graphics.set_canvas
    assert_equal [], Graphics.canvas
  end

  def test_a_target_that_is_not_a_texture_raises
    error = assert_raises(TypeError) { Graphics.set_canvas(:screen) }

    assert_equal "wrong argument type Symbol (expected Lota::Graphics::Texture)", error.message
  end

  def test_a_stencil_into_a_canvas_needs_a_stencil_buffer
    canvas = Graphics::Canvas.new(4, 4)
    Graphics.set_canvas(canvas)
    error = assert_raises(RuntimeError) { Graphics.stencil_state = :replace, :always, 1 }

    assert_match(/\ADrawing to the stencil buffer with a Canvas active requires/, error.message)
  end

  def test_a_stencil_buffer_masks_drawing
    [{ stencil: true }, { depthstencil: true }, { depthstencil: Graphics::Canvas.new(4, 4, format: :stencil8) }]
      .each do |options|
      canvas = Graphics::Canvas.new(4, 4)
      Graphics.set_canvas(canvas, **options)
      Graphics.clear(0, 0, 0, 1)
      Graphics.stencil_state = :replace, :always, 1
      Graphics.rectangle(:fill, 0, 0, 2, 4)
      Graphics.stencil_state = :keep, :greater, 0
      Graphics.color = 1, 0, 0, 1
      Graphics.rectangle(:fill, 0, 0, 4, 4)
      Graphics.color = 1, 1, 1, 1
      Graphics.stencil_state = nil
      Graphics.set_canvas
      pixels = Graphics.readback_texture(canvas)

      assert_equal [RED, [0.0, 0.0, 0.0, 1.0]], [pixels.pixel(0, 0), pixels.pixel(3, 0)], options.inspect
    end
  end

  def test_readback_reads_a_rectangle
    canvas = Graphics::Canvas.new(4, 4)
    canvas.render_to do
      Graphics.clear(0, 1, 0, 1)
      Graphics.color = 1, 0, 0, 1
      Graphics.rectangle(:fill, 2, 2, 2, 2)
    end
    part = Graphics.readback_texture(canvas, nil, nil, 2, 2, 2, 1)

    assert_equal [[2, 1], RED], [part.dimensions, part.pixel(0, 0)]
  end

  def test_readback_reads_into_an_image_data_given
    canvas = Graphics::Canvas.new(2, 2)
    canvas.render_to { Graphics.clear(1, 0, 0, 1) }
    dest = Lota::Image::ImageData.new(4, 4)

    assert_same dest, Graphics.readback_texture(canvas, nil, nil, 0, 0, 2, 2, dest, 2, 2)
    assert_equal [CLEAR, RED], [dest.pixel(0, 0), dest.pixel(3, 3)]
  end

  def test_readback_of_a_2d_texture_takes_no_slice_but_a_number
    error = assert_raises(TypeError) { Graphics.readback_texture(Graphics::Canvas.new(2, 2), :first) }

    assert_equal "wrong argument type Symbol for slice (expected Integer or nil)", error.message
  end

  def test_replace_pixels_at_a_position
    canvas = Graphics::Canvas.new(4, 4)
    red = Lota::Image::ImageData.new(2, 2)
    red.map_pixel { [1, 0, 0, 1] }
    canvas.replace_pixels(red, nil, nil, 2, 2)
    pixels = Graphics.readback_texture(canvas)

    assert_equal [CLEAR, RED], [pixels.pixel(0, 0), pixels.pixel(3, 3)]
    assert_raises(TypeError) { canvas.replace_pixels(:red) }
  end

  def test_draw_places_by_a_transform
    source = Graphics::Canvas.new(2, 2)
    source.render_to { Graphics.clear(1, 0, 0, 1) }
    transform = Lota::Math::Transform.new.translate(2, 2)
    target = Graphics::Canvas.new(4, 4)
    target.render_to { Graphics.draw(source, transform) }
    quad_target = Graphics::Canvas.new(4, 4)
    quad_target.render_to { Graphics.draw(source, Graphics::Quad.new(0, 0, 1, 1, source), transform) }

    assert_equal [CLEAR, RED], [Graphics.readback_texture(target).pixel(1, 1), Graphics.readback_texture(target).pixel(3, 3)]
    assert_equal [CLEAR, RED], [Graphics.readback_texture(quad_target).pixel(3, 3), Graphics.readback_texture(quad_target).pixel(2, 2)]
  end

  def test_draw_layer_draws_the_layer_it_names
    array = Graphics::Canvas.new(2, 2, 2)
    Graphics.set_canvas(array, 2)
    Graphics.clear(1, 0, 0, 1)
    Graphics.set_canvas
    target = Graphics::Canvas.new(4, 4)
    target.render_to do
      Graphics.draw_layer(array, 1, 0, 0)
      Graphics.draw_layer(array, 2, Lota::Math::Transform.new.translate(2, 2))
      Graphics.draw_layer(array, 2, Graphics::Quad.new(0, 0, 1, 1, array), 0, 2)
    end
    pixels = Graphics.readback_texture(target)

    assert_equal [CLEAR, RED, RED, CLEAR], [pixels.pixel(0, 0), pixels.pixel(3, 3), pixels.pixel(0, 2), pixels.pixel(1, 3)]
  end

  def test_draw_layer_raises_for_a_missing_quad_or_layer
    array = Graphics::Canvas.new(2, 2, 2)

    assert_raises(TypeError) { Graphics.draw_layer(array, 1, nil, 0) }
    assert_raises(TypeError) { Graphics.draw_layer(array, :first) }
  end

  def test_filters_and_wraps_raise_for_unknown_modes
    canvas = Graphics::Canvas.new(2, 2)

    assert_raises(ArgumentError) { canvas.filter = :blurry }
    assert_raises(ArgumentError) { canvas.wrap = :around }
    assert_raises(ArgumentError) { canvas.mipmap_filter = :sometimes }
    assert_raises(ArgumentError) { canvas.depth_sample_mode = :maybe }
  end

  # LÖVE names the filter of a texture that does not use its mipmaps
  # "none", though its comment says it returns nil (wrap_Texture.cpp:
  # 213-226).
  def test_mipmap_filter_nil_stops_using_mipmaps
    canvas = Graphics::Canvas.new(4, 4, mipmaps: :auto)
    canvas.mipmap_filter = nil

    assert_equal [:none, 0.0], canvas.mipmap_filter
  end
end
