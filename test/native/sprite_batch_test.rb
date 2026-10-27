# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Graphics::SpriteBatch, Lota::Graphics::Quad, and drawing through
# them, beyond what Lövetest's tests for them check
# (test/lovetest/tests/graphics.rb): the forms w_newQuad chooses between
# (wrap_Graphics.cpp:1335-1380), the defaults and errors of
# w_newSpriteBatch (lines 1438-1460) and of SpriteBatch's methods
# (wrap_SpriteBatch.cpp and SpriteBatch.cpp), and how w_draw tells a quad
# from a missing one (wrap_Graphics.cpp:3245-3263).
class SpriteBatchTest < Minitest::Test
  def setup
    EngineHelper.open_window
    Lota::Graphics.color = 1, 1, 1, 1
  end

  def texture
    @texture ||= Lota::Graphics::Canvas.new(8, 4)
  end

  def test_a_quad_takes_its_textures_size_or_numbers_and_a_layer_counted_from_1
    assert_equal [8.0, 4.0], Lota::Graphics::Quad.new(0, 0, 1, 1, texture).texture_dimensions
    assert_equal [16.0, 32.0], Lota::Graphics::Quad.new(0, 0, 1, 1, 16, 32).texture_dimensions
    assert_equal 1, Lota::Graphics::Quad.new(0, 0, 1, 1, texture).layer
    assert_equal 3, Lota::Graphics::Quad.new(0, 0, 1, 1, 3, texture).layer
    with_layer = Lota::Graphics::Quad.new(1, 2, 3, 4, 2, 16, 32)

    assert_equal [2, [16.0, 32.0], [1.0, 2.0, 3.0, 4.0]], [
      with_layer.layer,
      with_layer.texture_dimensions,
      with_layer.viewport,
]
  end

  # w_Quad_setViewport keeps the texture's size unless given one.
  def test_a_quads_viewport_moves_within_the_same_texture_unless_given_another
    quad = Lota::Graphics::Quad.new(0, 0, 1, 1, texture)
    quad.viewport = 2, 1, 4, 2

    assert_equal [[2.0, 1.0, 4.0, 2.0], [8.0, 4.0]], [quad.viewport, quad.texture_dimensions]

    quad.viewport = [0, 0, 1, 1, 64, 64]

    assert_equal [64.0, 64.0], quad.texture_dimensions
    assert_raises(ArgumentError) { quad.viewport = 0, 0, 1, 1, 64 }
    assert_raises(ArgumentError) { Lota::Graphics::Quad.new(0, 0, 1, 1, 64) }
  end

  # A batch holds 1000 sprites unless told otherwise, and doubles when a
  # sprite is added to a full one (SpriteBatch.cpp, add).
  def test_a_batch_grows_when_a_sprite_is_added_to_a_full_one
    assert_equal 1000, Lota::Graphics::SpriteBatch.new(texture).buffer_size
    batch = Lota::Graphics::SpriteBatch.new(texture, 2, :static)
    ids = Array.new(3) { |n| batch.add(n, 0) }

    assert_equal [[1, 2, 3], 3, 4], [ids, batch.count, batch.buffer_size]
  end

  def test_a_batch_raises_loves_errors
    batch = Lota::Graphics::SpriteBatch.new(texture, 10)
    usage = assert_raises(ArgumentError) { Lota::Graphics::SpriteBatch.new(texture, 10, :often) }
    index = assert_raises(RuntimeError) { batch.set(11, 0, 0) }
    range = assert_raises(RuntimeError) { batch.draw_range = 1, 0 }

    assert_match(/\AInvalid usage hint 'often', expected one of: /, usage.message)
    assert_equal "Invalid sprite index: 11", index.message
    assert_equal "Invalid draw range.", range.message
    assert_raises(TypeError) { Lota::Graphics::SpriteBatch.new(:texture) }
    assert_raises(TypeError) { batch.texture = :texture }
  end

  # SpriteBatch:getDrawRange returns nothing until a range is set, and
  # setDrawRange with no arguments, which Lota writes as nil, unsets it.
  def test_a_draw_range_is_nil_until_set_and_after_it_is_unset
    batch = Lota::Graphics::SpriteBatch.new(texture)

    assert_nil batch.draw_range
    batch.draw_range = 3, 4

    assert_equal [3, 4], batch.draw_range
    batch.draw_range = nil

    assert_nil batch.draw_range
  end

  def test_a_batch_color_has_alpha_1_unless_given
    batch = Lota::Graphics::SpriteBatch.new(texture)
    batch.color = 1, 0, 0

    assert_equal [1.0, 0.0, 0.0, 1.0], batch.color
    assert_raises(ArgumentError) { batch.color = 1, 0 }
  end

  # nil where the quad would be is a missing quad when a number follows
  # it, as in LÖVE, and otherwise the drawable's position, 0. A quad draws
  # only a texture, and nine numbers are all a placement has.
  def test_draw_tells_a_quad_from_a_missing_one
    batch = Lota::Graphics::SpriteBatch.new(texture)
    quad = Lota::Graphics::Quad.new(0, 0, 1, 1, texture)
    missing = assert_raises(TypeError) { Lota::Graphics.draw(texture, nil, 5) }
    batch_quad = assert_raises(TypeError) { Lota::Graphics.draw(batch, quad) }

    assert_equal "wrong argument type nil (expected Lota::Graphics::Quad)", missing.message
    assert_equal "wrong argument type Lota::Graphics::SpriteBatch (expected Lota::Graphics::Texture)",
      batch_quad.message
    assert_raises(TypeError) { batch.add(nil, 5) }
    assert_raises(ArgumentError) { Lota::Graphics.draw(texture, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0) }
    assert_nil Lota::Graphics.draw(texture, nil)
  end

  # A texture's width and height, of its first mipmap or the one given,
  # counting from 1 (w__optMipmap, wrap_Texture.cpp:38-51).
  def test_a_texture_measures_a_mipmap_it_has
    assert_equal [8, 4], [texture.width, texture.height]
    assert_equal [8, 4], [texture.width(1), texture.height(1)]
    error = assert_raises(RuntimeError) { texture.width(2) }

    assert_equal "Invalid mipmap index: 2", error.message
  end
end
