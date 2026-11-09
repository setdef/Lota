# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# What love.graphics does with a Buffer's bytes beyond what Lövetest's tests
# check (no test of Lövetest calls these): readbackBuffer,
# readbackBufferAsync, copyBuffer, copyBufferToTexture, copyTextureToBuffer,
# drawFromShader, drawFromShaderIndirect (wrap_Graphics.cpp:2367-2409,
# 3340-3406, and 3813-3896), and SpriteBatch:attachAttribute
# (wrap_SpriteBatch.cpp:210-230). Each answers with the messages of
# Graphics.cpp.
class BufferCopyTest < Minitest::Test
  include NativeHelper

  POSITION = { name: "VertexPosition", format: :floatvec2, location: 0 }.freeze

  def setup
    EngineHelper.open_window
    Lota::Graphics.color = 1, 1, 1, 1
  end

  def buffer_of(*rows)
    Lota::Graphics::Buffer.new([POSITION], rows, vertex: true)
  end

  # A buffer of four pixels of +color+, as a texture buffer, which needs no
  # binding location.
  def pixels_of(color)
    skip "texel buffers are not supported" unless Lota::Graphics.supported.texelbuffer

    Lota::Graphics::Buffer.new(:unorm8vec4, [color] * 4, texel: true)
  end

  # The 32-bit floats a Data holds.
  def floats(data)
    count = data.size / 4
    Lota::Data.unpack("<#{'f' * count}", data).first(count)
  end

  def drawn_on(canvas)
    Lota::Graphics.push(:all)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    yield
    Lota::Graphics.pop
    Lota::Graphics.readback_texture(canvas)
  end

  def test_readback_buffer_reads_a_buffer_or_a_range_of_it
    buffer = buffer_of([1, 2], [3, 4])
    bytes = Lota::Graphics.readback_buffer(buffer)

    assert_instance_of Lota::Data::ByteData, bytes
    assert_equal [1.0, 2.0, 3.0, 4.0], floats(bytes)
    assert_equal [3.0, 4.0], floats(Lota::Graphics.readback_buffer(buffer, 8))
    assert_equal [2.0, 3.0], floats(Lota::Graphics.readback_buffer(buffer, 4, 8))
  end

  def test_readback_buffer_reads_into_a_byte_data_it_is_given
    buffer = buffer_of([1, 2], [3, 4])
    dest = Lota::Data::ByteData.new(16)
    result = Lota::Graphics.readback_buffer(buffer, 0, 8, dest, 8)

    assert_same dest, result
    assert_equal [1.0, 2.0], floats(dest).last(2)
  end

  def test_readback_buffer_reports_a_range_or_a_destination_that_does_not_fit
    buffer = buffer_of([1, 2], [3, 4])

    assert_equal "Invalid offset or size for the given Buffer.",
      assert_raises(RuntimeError) { Lota::Graphics.readback_buffer(buffer, 8, 16) }.message
    assert_equal "Invalid destination offset or size for the given ByteData.",
      assert_raises(RuntimeError) { Lota::Graphics.readback_buffer(buffer, 0, 8, Lota::Data::ByteData.new(4)) }.message
    assert_raises(TypeError) { Lota::Graphics.readback_buffer(:buffer) }
    assert_raises(TypeError) { Lota::Graphics.readback_buffer(buffer, 0, 8, :bytes) }
  end

  def test_readback_buffer_async_has_the_bytes_once_it_is_complete
    buffer = buffer_of([1, 2], [3, 4])
    readback = Lota::Graphics.readback_buffer_async(buffer)
    readback.wait

    assert_instance_of Lota::Graphics::GraphicsReadback, readback
    assert_predicate readback, :complete?
    assert_equal [1.0, 2.0, 3.0, 4.0], floats(readback.buffer_data)
    assert_equal "Invalid offset or size for the given Buffer.",
      assert_raises(RuntimeError) { Lota::Graphics.readback_buffer_async(buffer, 16, 8) }.message
    assert_raises(TypeError) { Lota::Graphics.readback_buffer_async(:buffer) }
  end

  def test_copy_buffer_copies_a_range_to_another_buffer
    source = buffer_of([1, 2], [3, 4])
    dest = buffer_of([0, 0], [0, 0])
    Lota::Graphics.copy_buffer(source, dest, 0, 8, 8)

    assert_equal [0.0, 0.0, 1.0, 2.0], floats(Lota::Graphics.readback_buffer(dest))

    Lota::Graphics.copy_buffer(source, dest)

    assert_equal [1.0, 2.0, 3.0, 4.0], floats(Lota::Graphics.readback_buffer(dest))
  end

  def test_copy_buffer_reports_what_it_cannot_copy
    source = buffer_of([1, 2], [3, 4])
    dest = buffer_of([0, 0], [0, 0])

    assert_equal "copyBuffer offsets cannot be negative.",
      assert_raises(RuntimeError) { Lota::Graphics.copy_buffer(source, dest, -4) }.message
    assert_equal "copyBuffer size must be greater than 0.",
      assert_raises(RuntimeError) { Lota::Graphics.copy_buffer(source, dest, 0, 0, 0) }.message
    assert_equal "Buffer copy source offset, destination offset, and size parameters must be multiples of 4 bytes.",
      assert_raises(RuntimeError) { Lota::Graphics.copy_buffer(source, dest, 1, 0, 4) }.message
    assert_equal "Copying a portion of a buffer to the same buffer requires non-overlapping source and " \
      "destination offsets.",
      assert_raises(RuntimeError) { Lota::Graphics.copy_buffer(source, source, 0, 4, 8) }.message
    assert_raises(TypeError) { Lota::Graphics.copy_buffer(:source, dest) }
    assert_raises(TypeError) { Lota::Graphics.copy_buffer(source, :dest) }
  end

  def test_copy_buffer_to_texture_fills_a_texture_from_bytes
    pixels = pixels_of([1, 0, 0, 1])
    canvas = Lota::Graphics::Canvas.new(2, 2)
    Lota::Graphics.copy_buffer_to_texture(pixels, canvas)

    assert_equal [1.0, 0.0, 0.0, 1.0], Lota::Graphics.readback_texture(canvas).pixel(1, 1)
  end

  def test_copy_buffer_to_texture_reports_what_it_cannot_copy
    pixels = pixels_of([1, 0, 0, 1])
    canvas = Lota::Graphics::Canvas.new(2, 2)

    assert_equal "copyBufferToTexture source offset cannot be negative.",
      assert_raises(RuntimeError) { Lota::Graphics.copy_buffer_to_texture(pixels, canvas, -4) }.message
    assert_equal "Invalid texture mipmap index 2.",
      assert_raises(RuntimeError) { Lota::Graphics.copy_buffer_to_texture(pixels, canvas, 0, 0, nil, 2) }.message
    assert_raises(TypeError) { Lota::Graphics.copy_buffer_to_texture(:pixels, canvas) }
    assert_raises(TypeError) { Lota::Graphics.copy_buffer_to_texture(pixels, :canvas) }
  end

  def test_copy_texture_to_buffer_fills_a_buffer_from_a_texture
    skip "copying a texture to a buffer is not supported" unless Lota::Graphics.supported.copytexturetobuffer

    canvas = Lota::Graphics::Canvas.new(2, 2)
    Lota::Graphics.push(:all)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 1, 0, 1)
    Lota::Graphics.pop
    pixels = pixels_of([0, 0, 0, 0])
    Lota::Graphics.copy_texture_to_buffer(canvas, pixels)

    assert_equal [0x00, 0xFF, 0x00, 0xFF] * 4, Lota::Graphics.readback_buffer(pixels).string.bytes
  end

  def test_copy_texture_to_buffer_reports_what_it_cannot_copy
    canvas = Lota::Graphics::Canvas.new(2, 2)
    pixels = pixels_of([0, 0, 0, 0])

    assert_equal "copyTextureToBuffer dest offset cannot be negative.",
      assert_raises(RuntimeError) { Lota::Graphics.copy_texture_to_buffer(canvas, pixels, nil, nil, nil, nil, nil, nil, -4) }.message
    assert_raises(TypeError) { Lota::Graphics.copy_texture_to_buffer(:canvas, pixels) }
    assert_raises(TypeError) { Lota::Graphics.copy_texture_to_buffer(canvas, :pixels) }
  end

  FULLSCREEN = <<~GLSL
    #ifdef VERTEX
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
      vec2 corners[3] = vec2[3](vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
      return vec4(corners[love_VertexID], 0.0, 1.0);
    }
    #endif

    #ifdef PIXEL
    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
      return vec4(1.0, 0.0, 0.0, 1.0);
    }
    #endif
  GLSL

  def drawn_from_shader
    skip "shaders need GLSL 3" unless Lota::Graphics.supported.glsl3

    canvas = Lota::Graphics::Canvas.new(4, 4)
    pixels = drawn_on(canvas) do
      Lota::Graphics.shader = Lota::Graphics::Shader.new(FULLSCREEN)
      yield
    end
    pixels.pixel(2, 2)
  end

  def test_draw_from_shader_draws_the_vertices_a_shader_makes
    assert_equal [1.0, 0.0, 0.0, 1.0], drawn_from_shader { Lota::Graphics.draw_from_shader(:triangles, 3) }
    assert_equal [1.0, 0.0, 0.0, 1.0], drawn_from_shader { Lota::Graphics.draw_from_shader("triangles", 3, 2) }
  end

  def test_draw_from_shader_draws_the_indices_of_a_buffer
    indices = Lota::Graphics::Buffer.new(:uint16, [0, 1, 2], index: true)

    assert_equal [1.0, 0.0, 0.0, 1.0], drawn_from_shader { Lota::Graphics.draw_from_shader(indices, 3, 1, 1) }
  end

  def test_draw_from_shader_reports_what_it_cannot_draw
    indices = Lota::Graphics::Buffer.new(:uint16, [0, 1, 2], index: true)

    assert_equal "drawFromShader can only be used with a custom shader.",
      assert_raises(RuntimeError) { Lota::Graphics.draw_from_shader(:triangles, 3) }.message
    assert_equal "drawFromShader can only be used with a custom shader.",
      assert_raises(RuntimeError) { Lota::Graphics.draw_from_shader(indices, 3) }.message
    assert_match(/Invalid primitive type 'blobs'/, assert_raises(ArgumentError) do
      Lota::Graphics.draw_from_shader(:blobs, 3)
    end.message)
    assert_raises(TypeError) { Lota::Graphics.draw_from_shader(:triangles, 3, 1, :texture) }
    assert_raises(TypeError) { Lota::Graphics.draw_from_shader(indices, 3, 1, 1, :texture) }
  end

  def test_draw_from_shader_indirect_draws_what_a_buffer_says
    skip "indirect draws are not supported" unless Lota::Graphics.supported.indirectdraw

    arguments = Lota::Graphics::Buffer.new(:uint32, [3, 1, 0, 0], indirectarguments: true)

    assert_equal [1.0, 0.0, 0.0, 1.0], drawn_from_shader { Lota::Graphics.draw_from_shader_indirect(:triangles, arguments) }
  end

  def test_draw_from_shader_indirect_reports_what_it_cannot_draw
    arguments = Lota::Graphics::Buffer.new(:uint32, [3, 1, 0, 0], indirectarguments: true)
    indices = Lota::Graphics::Buffer.new(:uint16, [0, 1, 2], index: true)

    assert_equal "drawFromShaderIndirect can only be used with a custom shader.",
      assert_raises(RuntimeError) { Lota::Graphics.draw_from_shader_indirect(:triangles, arguments) }.message
    assert_raises(TypeError) { Lota::Graphics.draw_from_shader_indirect(:triangles, :arguments) }
    assert_raises(TypeError) { Lota::Graphics.draw_from_shader_indirect(indices, arguments, 1, :texture) }
  end

  def sprite_batch
    batch = Lota::Graphics::SpriteBatch.new(Lota::Graphics::Canvas.new(4, 4), 4)
    batch.add(0, 0)
    batch
  end

  TINT = { name: "Tint", format: :floatvec4, location: 3 }.freeze

  def test_a_sprite_batch_takes_an_attribute_from_a_buffer_or_a_mesh
    tints = Lota::Graphics::Buffer.new([TINT], [[1, 0, 0, 1]] * 4, vertex: true)
    mesh = Lota::Graphics::Mesh.new([TINT], 4, :fan)

    assert_nil sprite_batch.attach_attribute("Tint", tints)
    assert_nil sprite_batch.attach_attribute("Tint", mesh)
  end

  def test_a_sprite_batch_reports_an_attribute_it_cannot_take
    batch = sprite_batch
    plain = Lota::Graphics::Buffer.new(:uint16, [0, 1, 2, 3], index: true)
    few = Lota::Graphics::Buffer.new([TINT], [[1, 0, 0, 1]] * 3, vertex: true)
    tints = Lota::Graphics::Buffer.new([TINT], [[1, 0, 0, 1]] * 4, vertex: true)
    buffered = Lota::Graphics::Mesh.new([{ buffer: tints, location: 3, name: "Tint" }], :fan)

    assert_equal "GraphicsBuffer must be created with vertex buffer support to be used as a SpriteBatch vertex attribute.",
      assert_raises(RuntimeError) { batch.attach_attribute("Tint", plain) }.message
    assert_equal "Buffer has too few vertices to be attached to this SpriteBatch (at least 4 vertices are required)",
      assert_raises(RuntimeError) { batch.attach_attribute("Tint", few) }.message
    assert_equal "The specified Buffer does not have a vertex attribute named 'Nope'",
      assert_raises(RuntimeError) { batch.attach_attribute("Nope", tints) }.message
    assert_equal "Mesh does not have its own vertex buffer.",
      assert_raises(RuntimeError) { batch.attach_attribute("Tint", buffered) }.message
    assert_raises(TypeError) { batch.attach_attribute("Tint", :buffer) }
    assert_raises(TypeError) { batch.attach_attribute(:Tint, tints) }
  end
end
