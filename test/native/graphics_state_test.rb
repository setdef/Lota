# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# LÖVE 12's drawing state and readback that Lövetest has no test for
# (vendor/love/testing/tests/graphics.lua): setStencilMode and
# getStencilMode (wrap_Graphics.cpp:613-644), setBlendState and
# getBlendState (lines 2701-2749), setDefaultMipmapFilter and
# getDefaultMipmapFilter (lines 2784-2814), isLowPowerPreferred (lines
# 201-205), discard (lines 152-175), clear's forms that choose whether to
# clear the stencil and depth (lines 69-150), readbackTextureAsync (lines
# 2451-2489) and GraphicsReadback (wrap_GraphicsReadback.cpp), and
# Texture:getViewFormats (wrap_Texture.cpp:303-319); and the functions LÖVE
# 12 keeps for older games and marks deprecated: getCanvasFormats and
# getImageFormats (wrap_Graphics.cpp:3088-3144), setNewFont (lines
# 2563-2571), and stencil, setStencilTest, and getStencilTest
# (wrap_Graphics.lua:55-96).
class GraphicsStateTest < Minitest::Test
  Graphics = Lota::Graphics
  RED = [1.0, 0.0, 0.0, 1.0].freeze
  BLACK = [0.0, 0.0, 0.0, 1.0].freeze

  def setup
    EngineHelper.open_window
    Graphics.color = 1, 1, 1, 1
    @mipmap_filter = Graphics.default_mipmap_filter
  end

  def teardown
    Graphics.set_canvas
    Graphics.stencil_state = nil
    Graphics.color_mask = nil
    Graphics.blend_mode = :alpha
    Graphics.default_mipmap_filter = @mipmap_filter
    Graphics.color = 1, 1, 1, 1
  end

  # How many times +name+ has been marked deprecated.
  def uses(name)
    Lota::Deprecation.instance_variable_get(:@deprecated)[name]&.uses.to_i
  end

  # Asserts that +block+ marks +name+ deprecated once, with the notice
  # LÖVE gives, ending in +change+, such as "replaced by" a name, and
  # returns what +block+ returns.
  def assert_deprecated(name, change = nil, api: :function)
    before = uses(name)
    result = yield
    info = Lota::Deprecation.instance_variable_get(:@deprecated).fetch(name)
    notice = "Using deprecated #{api} #{name}#{change && " (#{change})"}"

    assert_equal [before + 1, notice], [uses(name), Lota::Deprecation.notice(info).delete_prefix(info.where)]
    result
  end

  # A 4 by 4 canvas with a stencil buffer, cleared to opaque black, on
  # which +block+ draws; its pixels.
  def drawn_with_stencil(&)
    canvas = Graphics::Canvas.new(4, 4)
    Graphics.set_canvas(canvas, stencil: true)
    Graphics.clear(0, 0, 0, 1)
    yield
    Graphics.color = 1, 1, 1, 1
    Graphics.stencil_state = nil
    Graphics.color_mask = nil
    Graphics.set_canvas
    Graphics.readback_texture(canvas)
  end

  # Graphics::setStencilMode (Graphics.cpp:1536-1549) draws into the
  # stencil with the color masked off, tests it with the color on, and
  # with no mode turns the stencil off; the value is 1 unless given.
  def test_a_stencil_mode_sets_the_stencil_and_the_color_mask
    assert_equal [:off, 0], Graphics.stencil_mode

    Graphics.set_canvas(Graphics::Canvas.new(4, 4), stencil: true)
    Graphics.stencil_mode = :draw

    assert_equal [[:draw, 1], [false, false, false, false], %i[replace always]],
      [Graphics.stencil_mode, Graphics.color_mask, Graphics.stencil_state.first(2)]

    Graphics.stencil_mode = :test, 2

    assert_equal [[:test, 2], [true, true, true, true], [:keep, :equal, 2]],
      [Graphics.stencil_mode, Graphics.color_mask, Graphics.stencil_state.first(3)]

    Graphics.stencil_mode = nil

    assert_equal [:off, 0], Graphics.stencil_mode
  end

  def test_drawing_in_the_stencil_mode_draw_masks_what_the_mode_test_draws
    pixels = drawn_with_stencil do
      Graphics.stencil_mode = :draw
      Graphics.rectangle(:fill, 0, 0, 2, 4)
      Graphics.stencil_mode = :test
      Graphics.color = 1, 0, 0, 1
      Graphics.rectangle(:fill, 0, 0, 4, 4)
    end

    assert_equal [RED, BLACK], [pixels.pixel(0, 0), pixels.pixel(3, 0)]
  end

  # A state no mode names is "custom" (renderstate.cpp:136-145).
  def test_a_stencil_state_no_mode_names_is_custom
    Graphics.set_canvas(Graphics::Canvas.new(4, 4), stencil: true)
    Graphics.stencil_state = :increment, :always, 3

    assert_equal [:custom, 3], Graphics.stencil_mode
  end

  # w_setStencilMode reads a mode when it is given anything at all.
  def test_a_stencil_mode_raises_for_an_unknown_mode_or_a_value_without_one
    error = assert_raises(ArgumentError) { Graphics.stencil_mode = :sideways }

    assert_match(/\AInvalid stencil mode 'sideways'/, error.message)
    assert_raises(ArgumentError) { Graphics.stencil_mode = nil, 1 }
  end

  # w_setBlendState gives the color and alpha one operation and two
  # factors in its short form, and each its own in its long one; nil
  # turns blending off, which getBlendMode calls "none".
  def test_a_blend_state_round_trips_and_names_the_blend_mode_it_makes
    Graphics.blend_mode = :alpha

    assert_equal %i[add add srcalpha one oneminussrcalpha oneminussrcalpha], Graphics.blend_state

    Graphics.blend_state = :add, :one, :zero

    assert_equal [%i[add add one one zero zero], %i[replace premultiplied]],
      [Graphics.blend_state, Graphics.blend_mode]

    Graphics.blend_state = :max, :add, :one, :zero, :one, :one

    assert_equal [%i[max add one zero one one], %i[custom premultiplied]],
      [Graphics.blend_state, Graphics.blend_mode]

    Graphics.blend_state = nil

    assert_equal [[nil] * 6, %i[none premultiplied]], [Graphics.blend_state, Graphics.blend_mode]
  end

  def test_drawing_with_a_blend_state_blends_by_it
    canvas = Graphics::Canvas.new(2, 2)
    Graphics.set_canvas(canvas)
    Graphics.clear(1, 0, 0, 1)
    Graphics.blend_state = :add, :one, :zero
    Graphics.color = 0, 0, 1, 0
    Graphics.rectangle(:fill, 0, 0, 2, 2)
    Graphics.set_canvas

    assert_equal [0.0, 0.0, 1.0, 0.0], Graphics.readback_texture(canvas).pixel(0, 0)
  end

  def test_a_blend_state_raises_for_an_unknown_name_or_count
    error = assert_raises(ArgumentError) { Graphics.blend_state = :add, :one, :sometimes }

    assert_match(/\AInvalid blend factor 'sometimes'/, error.message)
    error = assert_raises(ArgumentError) { Graphics.blend_state = :plus, :one, :zero }

    assert_match(/\AInvalid blend operation 'plus'/, error.message)
    assert_raises(ArgumentError) { Graphics.blend_state = :add, :one, :zero, :one }
  end

  # The default mipmap filter starts as "linear" (Graphics.cpp:214); a
  # texture made with mipmaps afterward takes it, and its sharpness, which
  # LÖVE negates into the bias it stores, and nil is "none".
  def test_a_default_mipmap_filter_is_what_textures_made_afterward_take
    assert_equal [:linear, 0.0], Graphics.default_mipmap_filter

    Graphics.default_mipmap_filter = :nearest, 0.5

    assert_equal [:nearest, 0.5], Graphics.default_mipmap_filter
    assert_equal [:nearest, 0.5], Graphics::Canvas.new(4, 4, mipmaps: :manual).mipmap_filter

    Graphics.default_mipmap_filter = :linear

    assert_equal [:linear, 0.0], Graphics.default_mipmap_filter

    Graphics.default_mipmap_filter = nil

    assert_equal [:none, 0.0], Graphics.default_mipmap_filter
    error = assert_raises(ArgumentError) { Graphics.default_mipmap_filter = :blurry }

    assert_match(/\AInvalid filter mode 'blurry'/, error.message)
  end

  # isLowPowerPreferred answers what boot sets from
  # t.graphics.lowpower, before or after the module opens.
  def test_low_power_preferred_answers_what_was_set
    before = Graphics.low_power_preferred?
    [true, false].each do |preferred|
      Lota::Native::Graphics.set_low_power_preferred(preferred)

      assert_equal preferred, Graphics.low_power_preferred?
    end
  ensure
    Lota::Native::Graphics.set_low_power_preferred(before)
  end

  # w_discard reads a table of booleans for several canvases, or one for
  # all of them, and takes anything but false as true, as
  # luax_optboolean does. What the driver then does is its own: LÖVE's
  # docs say some desktops do nothing, and Lövetest skips its test.
  def test_discard_takes_every_form_love_reads
    Graphics.set_canvas(Graphics::Canvas.new(2, 2), Graphics::Canvas.new(2, 2), stencil: true)

    assert_nil Graphics.discard
    assert_nil Graphics.discard(false)
    assert_nil Graphics.discard([true, false], false)
    assert_nil Graphics.discard(0, nil)
  end

  # w_clear's color can be false, to clear only the stencil and depth, or
  # true, for transparent black; after the color, the stencil and depth
  # are each cleared to a number, or not when false.
  def test_clear_can_leave_the_color_and_clear_the_stencil_alone
    pixels = drawn_with_stencil do
      Graphics.stencil_state = :replace, :always, 1
      Graphics.rectangle(:fill, 0, 0, 2, 4)
      Graphics.clear(1, 0, 0, 1, false, false)
      Graphics.stencil_state = :keep, :equal, 1
      Graphics.color = 0, 0, 1, 1
      Graphics.rectangle(:fill, 0, 0, 4, 4)
    end

    assert_equal [[0.0, 0.0, 1.0, 1.0], RED], [pixels.pixel(0, 0), pixels.pixel(3, 0)]

    pixels = drawn_with_stencil do
      Graphics.clear(1, 0, 0, 1)
      Graphics.clear(false, 2, false)
      Graphics.stencil_state = :keep, :equal, 2
      Graphics.color = 0, 0, 1, 1
      Graphics.rectangle(:fill, 0, 0, 4, 4)
    end

    assert_equal [0.0, 0.0, 1.0, 1.0], pixels.pixel(3, 3)
    pixels = drawn_with_stencil { Graphics.clear(true) }

    assert_equal [0.0, 0.0, 0.0, 0.0], pixels.pixel(0, 0)
  end

  def test_clear_raises_for_a_count_of_components_love_does_not_read
    assert_raises(ArgumentError) { Graphics.clear(1, 0) }
    assert_raises(ArgumentError) { Graphics.clear(1, 0, 0, 1, true, true, true) }
    assert_raises(ArgumentError) { Graphics.clear(false, true, true, true) }
  end

  # An asynchronous readback is complete once waited for, and then has
  # the pixels; it reads a rectangle into an ImageData given, as
  # readbackTexture does.
  def test_an_asynchronous_readback_has_the_pixels_once_complete
    canvas = Graphics::Canvas.new(4, 4)
    canvas.render_to { Graphics.clear(1, 0, 0, 1) }
    readback = Graphics.readback_texture_async(canvas)
    readback.wait

    assert_equal ["GraphicsReadback", true, false, nil], [
      readback.type,
      readback.complete?,
      readback.error?,
      readback.buffer_data,
]
    assert_equal [4, RED], [readback.image_data.width, readback.image_data.pixel(3, 3)]

    dest = Lota::Image::ImageData.new(4, 4)
    into = Graphics.readback_texture_async(canvas, nil, nil, 0, 0, 2, 2, dest, 2, 2)
    into.update
    into.wait

    assert_equal [[0.0, 0.0, 0.0, 0.0], RED], [dest.pixel(1, 1), dest.pixel(3, 3)]
    assert_equal dest, into.image_data
  end

  def test_an_asynchronous_readback_raises_as_readback_texture_does
    error = assert_raises(TypeError) { Graphics.readback_texture_async(Graphics::Canvas.new(2, 2), "1") }

    assert_equal "wrong argument type String for slice (expected Integer or nil)", error.message
    assert_raises(RuntimeError) { Graphics.readback_texture_async(Graphics::Canvas.new(2, 2), nil, 2) }
  end

  # A texture's view formats are the ones its viewformats setting
  # names, in order, and none without it.
  def test_a_texture_lists_the_view_formats_it_was_made_with
    assert_empty Graphics::Canvas.new(2, 2).view_formats
    assert_equal %i[srgba8 rgba8], Graphics::Canvas.new(2, 2, format: :rgba8, viewformats: %i[srgba8 rgba8]).view_formats
  end

  # getCanvasFormats asks for formats a canvas can have, sampled unless
  # its first argument says otherwise, leaving out compressed formats;
  # getImageFormats for formats a texture can be sampled in, leaving out
  # depth and stencil formats. LÖVE marks both deprecated, replaced by
  # getTextureFormats.
  def test_canvas_and_image_formats_answer_as_texture_formats_and_are_deprecated
    canvas = assert_deprecated("Lota::Graphics.canvas_formats", "replaced by Lota::Graphics.texture_formats") do
      Graphics.canvas_formats
    end

    assert_predicate canvas, :frozen?
    assert_equal Graphics.texture_formats(canvas: true).rgba8, canvas.rgba8
    assert_equal Graphics.texture_formats(canvas: true, readable: false).stencil8, Graphics.canvas_formats(false).stencil8
    assert_equal Graphics.texture_formats(canvas: true, readable: true).depth16, Graphics.canvas_formats(true).depth16
    assert_nil canvas["DXT1"]

    image = assert_deprecated("Lota::Graphics.image_formats", "replaced by Lota::Graphics.texture_formats") do
      Graphics.image_formats
    end
    sampled = Graphics.texture_formats(canvas: false)

    assert_equal [sampled.rgba16f, sampled["DXT1"]], [image.rgba16f, image["DXT1"]]
    assert_nil image[:depth16]
  end

  # setNewFont makes a font as newFont does, sets it, and returns it.
  def test_set_new_font_sets_and_returns_a_new_font_and_is_deprecated
    before = Graphics.font
    font = assert_deprecated("Lota::Graphics.set_new_font") { Graphics.set_new_font(17) }

    assert_kind_of Graphics::Font, font
    assert_equal [font, Graphics::Font.new(17).height], [Graphics.font, font.height]
  ensure
    Graphics.font = before if before
  end

  # love.graphics.stencil clears the stencil unless told to keep it,
  # draws what the block draws into it with the color masked off, and
  # puts the stencil state and color mask back after, also when the block
  # raises.
  def test_stencil_draws_the_block_into_the_stencil_and_puts_the_state_back
    pixels = drawn_with_stencil do
      Graphics.color_mask = true, true, false, true
      Graphics.stencil_state = :keep, :always, 0
      Graphics.stencil { Graphics.rectangle(:fill, 0, 0, 2, 4) }

      assert_equal [[true, true, false, true], [:keep, :always, 0]],
        [Graphics.color_mask, Graphics.stencil_state.first(3)]
      Graphics.color_mask = nil
      Graphics.stencil_state = :keep, :equal, 1
      Graphics.color = 1, 0, 0, 1
      Graphics.rectangle(:fill, 0, 0, 4, 4)
    end

    assert_equal [RED, BLACK], [pixels.pixel(0, 0), pixels.pixel(3, 0)]
  end

  def test_stencil_keeps_values_with_its_action_and_value_when_told
    pixels = drawn_with_stencil do
      Graphics.stencil(:replace, 2) { Graphics.rectangle(:fill, 0, 0, 2, 4) }
      Graphics.stencil(:increment, nil, true) { Graphics.rectangle(:fill, 0, 0, 4, 2) }
      Graphics.stencil_state = :keep, :equal, 3
      Graphics.color = 1, 0, 0, 1
      Graphics.rectangle(:fill, 0, 0, 4, 4)
    end

    assert_equal [RED, BLACK, BLACK], [pixels.pixel(0, 0), pixels.pixel(3, 0), pixels.pixel(0, 3)]
  end

  def test_stencil_puts_the_state_back_when_the_block_raises_and_is_deprecated
    Graphics.set_canvas(Graphics::Canvas.new(4, 4), stencil: true)
    error = assert_deprecated("Lota::Graphics.stencil", "replaced by Lota::Graphics.stencil_mode= or stencil_state=") do
      assert_raises(RuntimeError) { Graphics.stencil { raise "drawn" } }
    end

    assert_equal ["drawn", [true, true, true, true], %i[keep always]],
      [error.message, Graphics.color_mask, Graphics.stencil_state.first(2)]
  end

  # setStencilTest tests the stencil with the action "keep", and with no
  # mode turns it off; getStencilTest answers the compare mode and value.
  def test_the_stencil_test_sets_and_reads_the_stencil_state_and_is_deprecated
    Graphics.set_canvas(Graphics::Canvas.new(4, 4), stencil: true)
    assert_deprecated("Lota::Graphics.stencil_test=", "replaced by Lota::Graphics.stencil_mode= or stencil_state=") do
      Graphics.stencil_test = :greater, 1
    end

    assert_equal [:keep, :greater, 1], Graphics.stencil_state.first(3)
    assert_equal [:greater, 1], assert_deprecated("Lota::Graphics.stencil_test",
      "replaced by Lota::Graphics.stencil_mode or stencil_state") { Graphics.stencil_test }

    Graphics.stencil_test = :less

    assert_equal [:less, 0], Graphics.stencil_test

    Graphics.stencil_test = nil

    assert_equal [:always, 0], Graphics.stencil_test
  end

  # newCubeTexture, newArrayTexture, and newVolumeTexture
  # (wrap_Graphics.cpp:977-1255) make a Texture of their type, which ===
  # asks of the texture (ADR 001, rule 26); LÖVE 11's names, newCubeImage
  # and its kin, call them (lines 1257-1273).
  def test_texture_factories_make_and_match_textures_of_their_type
    cube = Graphics::CubeTexture.new(2)
    array = Graphics::ArrayTexture.new(2, 2, 3)
    volume = Graphics::VolumeTexture.new(2, 2, 2)

    assert_equal %i[cube array volume], [cube.texture_type, array.texture_type, volume.texture_type]
    assert_equal [true, false, false], [cube, array, volume].map { |texture| Graphics::CubeTexture === texture }
    assert_equal [false, true, false], [cube, array, volume].map { |texture| Graphics::ArrayTexture === texture }
    assert_equal [false, false, true], [cube, array, volume].map { |texture| Graphics::VolumeTexture === texture }
    assert_equal [true, true, true], [
      Graphics::CubeImage === cube,
      Graphics::ArrayImage === array,
      Graphics::VolumeImage === volume,
]
    assert_equal :array, Graphics::ArrayImage.new(2, 2, 2).texture_type
    refute_operator Graphics::CubeTexture, :===, :cube
  end

  # A view shares its texture's pixels (Texture.cpp:340-445): here one
  # layer of an array texture, drawn as a 2D texture. LÖVE cannot tell a
  # view from any other Texture, so TextureView === is true of every one.
  # Views need GLSL 4 (Texture.cpp:402-403).
  def test_a_texture_view_sees_one_layer_of_an_array_texture
    skip("Texture views need GLSL 4, which this renderer lacks") unless Graphics.supported.glsl4
    layers = Graphics::Canvas.new(2, 2, 2)
    layers.render_to(2) { Graphics.clear(1, 0, 0, 1) }
    view = Graphics::TextureView.new(layers, type: :"2d", layerstart: 2, layers: 1, debugname: "second")
    canvas = Graphics::Canvas.new(2, 2)
    canvas.render_to do
      Graphics.clear(0, 0, 0, 1)
      Graphics.draw(view)
    end

    assert_equal [:"2d", "second", RED], [
      view.texture_type,
      view.debug_name,
      Graphics.readback_texture(canvas).pixel(0, 0),
]
    assert_equal [true, true, false], [view, layers, 1].map { |object| Graphics::TextureView === object }
    error = assert_raises(ArgumentError) { Graphics::TextureView.new(layers, type: :flat) }

    assert_match(/\AInvalid texture type 'flat'/, error.message)
    assert_raises(TypeError) { Graphics::TextureView.new(:layers) }
  end

  # Texture:newImageData reads as readbackTexture does, and LÖVE marks it
  # renamed to readbackTexture (wrap_Texture.cpp:426-457).
  def test_a_textures_new_image_data_reads_it_back_and_is_deprecated
    canvas = Graphics::Canvas.new(4, 4)
    canvas.render_to { Graphics.clear(1, 0, 0, 1) }
    data = assert_deprecated("Lota::Graphics::Texture#new_image_data",
      "renamed to Lota::Graphics.readback_texture", api: :method) { canvas.new_image_data(nil, nil, 1, 1, 2, 2) }

    assert_equal [2, RED], [data.width, data.pixel(1, 1)]
  end
end
