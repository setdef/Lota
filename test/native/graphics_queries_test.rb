# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# What Lövetest's tests of the renderer's queries do not reach: the types
# of their fields (ADR 001, rule 14), and the checks w_getTextureFormats
# makes of its settings (wrap_Graphics.cpp:3022-3064), which become
# keywords (rule 10).
class GraphicsQueriesTest < Minitest::Test
  include NativeHelper

  Graphics = Lota::Graphics

  def setup
    EngineHelper.open_window
  end

  # w_getStats pushes the counts as integers, and its memory as numbers
  # of an int64 the C++ holds; w_getSystemLimits pushes doubles.
  def test_counts_are_integers_and_limits_floats_as_the_engine_holds_them
    stats = Graphics.stats

    stats.to_h.each_value { |count| assert_kind_of Integer, count }
    Graphics.system_limits.to_h.each_value { |limit| assert_kind_of Float, limit }
    assert_operator Graphics.system_limits.texturesize, :>=, 1.0
  end

  def test_the_queries_are_frozen_records
    records = [Graphics.stats, Graphics.supported, Graphics.system_limits, Graphics.texture_types]
    records << Graphics.texture_formats(canvas: false)
    records.each do |record|
      assert_predicate record, :frozen?
      assert_kind_of Lota::Record, record
    end
  end

  def test_every_texture_type_is_true_or_false
    types = Graphics.texture_types

    assert_equal %i[2d volume array cube], types.members
    assert(types["2d"], "every renderer has 2D textures")
  end

  # luax_checkboolflag: canvas must be given, as true or false.
  def test_canvas_is_required_and_must_be_true_or_false
    assert_raises(ArgumentError) { Graphics.texture_formats }
    assert_raises(TypeError) { Graphics.texture_formats(canvas: 1) }
    assert_raises(TypeError) { Graphics.texture_formats(canvas: nil) }
  end

  # readable, when given, must be true or false (luax_checkboolean);
  # nil leaves LÖVE's default, true but for depth and stencil formats.
  def test_readable_must_be_true_or_false_when_given
    assert_raises(TypeError) { Graphics.texture_formats(canvas: true, readable: "yes") }
    assert_equal Graphics.texture_formats(canvas: true), Graphics.texture_formats(canvas: true, readable: nil)
  end

  # luax_boolflag: computewrite and shaderatomics take any value's
  # truthiness, as Lua's flags do.
  def test_the_other_flags_take_any_truthiness
    assert_equal Graphics.texture_formats(canvas: false, computewrite: true),
      Graphics.texture_formats(canvas: false, computewrite: 1)
    assert_equal Graphics.texture_formats(canvas: false),
      Graphics.texture_formats(canvas: false, shaderatomics: nil)
  end

  def test_a_canvas_format_is_one_the_renderer_can_draw_into
    assert Graphics.texture_formats(canvas: true).rgba8
    assert Graphics.texture_formats(canvas: false).rgba8
  end
end
