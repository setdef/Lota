# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# LÖVE 12 has no Canvas class: love.graphics.newCanvas returns a Texture
# (vendor/love/changes.txt, "Changed the Texture class and implementation
# to no longer have separate Canvas and Image subclasses";
# vendor/love/src/modules/graphics/wrap_Graphics.cpp, w_newCanvas). By ADR
# 001's rule 2, Lota::Graphics::Canvas is a module whose new returns a
# Lota::Graphics::Texture and whose === asks the texture whether it is a
# canvas (Texture:isCanvas, wrap_Texture.cpp:282-287).
#
# Lota binds no factory yet that makes a texture that is not a canvas
# (love.graphics.newTexture or newImage), so these tests cannot show a
# real non-canvas Texture failing to match; they show that everything that
# is not a Texture fails to match, and that Canvas.=== asks canvas? rather
# than the class.
class CanvasTest < Minitest::Test
  include NativeHelper

  Canvas = Lota::Graphics::Canvas
  Texture = Lota::Graphics::Texture

  def setup
    EngineHelper.open_window
  end

  def test_canvas_is_a_module_not_a_class
    assert_instance_of Module, Canvas
  end

  def test_new_returns_a_texture
    assert_instance_of Texture, Canvas.new(4, 4)
  end

  def test_the_texture_wraps_the_engines_texture
    assert_instance_of Lota::Native::Texture, Canvas.new(4, 4).native
  end

  def test_the_texture_says_it_is_a_canvas
    assert_predicate Canvas.new(4, 4), :canvas?
  end

  def test_canvas_matches_a_texture_it_made
    assert_operator Canvas, :===, Canvas.new(4, 4)
  end

  def test_canvas_matches_in_a_case
    kind = case Canvas.new(4, 4)
    when Canvas then :canvas
    else :other
    end

    assert_equal :canvas, kind
  end

  def test_new_with_no_size_makes_a_canvas
    assert_operator Canvas, :===, Canvas.new
  end

  def test_canvas_matches_nothing_that_is_not_a_texture
    not_textures = [nil, :canvas, Object.new, Texture, Canvas, Canvas.new(4, 4).native]
    not_textures << Lota::Graphics.readback_texture(Canvas.new(4, 4))

    not_textures.each { |object| refute_operator Canvas, :===, object, object.inspect }
  end

  # A Texture whose canvas? is false stands in for the non-canvas textures
  # Lota cannot make yet: Canvas.=== goes by canvas?, not by class.
  def test_canvas_does_not_match_a_texture_that_says_it_is_not_a_canvas
    texture = Canvas.new(4, 4)
    texture.define_singleton_method(:canvas?) { false }

    refute_operator Canvas, :===, texture
  end

  def test_new_does_not_extend_what_it_returns
    texture = Canvas.new(4, 4)

    assert_empty texture.singleton_class.ancestors - Texture.ancestors - [texture.singleton_class]
  end

  # LÖVE makes textures only through factories, so Lota offers no
  # Texture.new.
  def test_texture_has_no_public_new
    assert_raises(NoMethodError) { Texture.new }
  end

  def test_a_canvas_is_a_drawing_target
    texture = Canvas.new(2, 2)
    Lota::Graphics.canvas = texture
    Lota::Graphics.clear(0, 0, 1)
    Lota::Graphics.canvas = nil

    assert_equal [0.0, 0.0, 1.0, 1.0], Lota::Graphics.readback_texture(texture).pixel(0, 0)
  end
end
