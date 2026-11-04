# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Graphics::Buffer and Lota::Graphics::Mesh beyond what Lövetest's
# tests for them check (test/lovetest/tests/graphics.rb): how each data
# format stores and defaults a number (wrap_Buffer.cpp:32-212), the forms
# and errors of Buffer:setArrayData and Mesh:setVertices
# (wrap_Buffer.cpp:214-343 and wrap_Mesh.cpp:40-123), the three forms of
# newMesh (wrap_Graphics.cpp:1983-2320), and the deprecations
# luax_validatebuffervertexbindings marks. A buffer has no reader, so what a
# buffer stores is read back through a mesh that has the same format.
class BufferTest < Minitest::Test
  include NativeHelper

  POSITION = { name: "VertexPosition", format: :floatvec2, location: 0 }.freeze

  def setup
    EngineHelper.open_window
    Lota::Graphics.color = 1, 1, 1, 1
  end

  # A mesh of one attribute of +format+ whose first vertex is +row+.
  def mesh_of(format, row, mode = :points)
    Lota::Graphics::Mesh.new([{ format:, location: 0, name: "Attribute" }], [row], mode)
  end

  def test_a_unorm_component_is_clamped_and_scaled_and_defaults_to_one
    mesh = mesh_of(:unorm8vec4, [0.5, -1, 2])

    # 0.5 * 255 and 255 are cut to a whole number, as (uint8) casts a double.
    assert_equal [127 / 255.0, 0.0, 1.0, 1.0], mesh.vertex(1)
  end

  def test_a_snorm_component_is_clamped_to_minus_one_and_one
    mesh = mesh_of(:snorm16vec2, [-3, 0.5])

    assert_in_delta(-1.0, mesh.vertex(1)[0], 1e-9)
    assert_in_delta 0.5, mesh.vertex(1)[1], 1e-4
  end

  def test_a_plain_component_defaults_to_zero_and_alpha_to_one
    assert_equal [0.0, 0.0, 0.0, 1.0], mesh_of(:floatvec4, []).vertex(1)
    assert_equal [7, 0, 0, 1], mesh_of(:int32vec4, [7]).vertex(1)
    assert_equal [1, 2], mesh_of(:uint16vec2, [1, 2]).vertex(1)
  end

  def test_a_matrix_component_is_required
    skip "shader storage buffers are not supported" unless Lota::Graphics.supported.glsl4

    error = assert_raises(TypeError) do
      Lota::Graphics::Buffer.new(:floatmat2x2, [[1, 2, 3]], shaderstorage: true)
    end

    assert_match(/expected Float/, error.message)
  end

  def test_a_component_that_is_not_a_number_is_a_type_error
    assert_raises(TypeError) { mesh_of(:floatvec2, [1, "x"]) }
  end

  def test_set_array_data_copies_a_range_of_elements_to_a_range_of_the_buffer
    buffer = Lota::Graphics::Buffer.new([POSITION], [[1, 2], [3, 4], [5, 6]], vertex: true)
    buffer.set_array_data([[9, 9], [8, 8]], 1, 2)

    assert_equal 3, buffer.element_count
    assert_equal 8, buffer.element_stride
    assert_equal 24, buffer.size
  end

  def test_set_array_data_reports_the_ranges_it_cannot_copy
    buffer = Lota::Graphics::Buffer.new([POSITION], 2, vertex: true)

    assert_equal "Source start index must be at least 1.",
      assert_raises(RuntimeError) { buffer.set_array_data([[1, 2]], 0) }.message
    assert_equal "Element count must be greater than 0.",
      assert_raises(RuntimeError) { buffer.set_array_data([[1, 2]], 1, 1, 0) }.message
    assert_equal "Invalid buffer start index (must be between 1 and 2)",
      assert_raises(RuntimeError) { buffer.set_array_data([[1, 2]], 1, 3) }.message
    assert_equal "Invalid data start index (must be between 1 and 1)",
      assert_raises(RuntimeError) { buffer.set_array_data([[1, 2]], 2) }.message
    assert_equal "Too many array elements (expected at most 1, got 2)",
      assert_raises(RuntimeError) { buffer.set_array_data([[1, 2], [3, 4]], 1, 2) }.message
  end

  def test_a_flat_array_must_be_a_multiple_of_the_components_of_an_element
    buffer = Lota::Graphics::Buffer.new([POSITION], 2, vertex: true)
    error = assert_raises(RuntimeError) { buffer.set_array_data([1, 2, 3]) }

    assert_equal "Array length in flat array variant of Lota::Graphics::GraphicsBuffer#set_array_data must be a multiple of " \
      "the total number of components (2)", error.message
  end

  def test_set_array_data_takes_the_bytes_of_a_data
    buffer = Lota::Graphics::Buffer.new([POSITION], 2, vertex: true)
    bytes = Lota::Filesystem::FileData.new([1.0, 2.0].pack("f2"), "bytes")
    buffer.set_array_data(bytes)

    assert_equal 2, buffer.element_count
  end

  def test_a_buffer_takes_the_content_of_its_format_from_a_data
    bytes = Lota::Filesystem::FileData.new([1.0, 2.0, 3.0, 4.0].pack("f4"), "bytes")
    buffer = Lota::Graphics::Buffer.new([POSITION], bytes, vertex: true)

    assert_equal 2, buffer.element_count
  end

  def test_the_number_of_elements_must_be_positive
    error = assert_raises(ArgumentError) { Lota::Graphics::Buffer.new(:uint16, 0, index: true) }

    assert_equal "number of elements must be greater than 0", error.message
  end

  def test_the_format_of_a_vertex_buffer_needs_a_location
    error = assert_raises(ArgumentError) do
      Lota::Graphics::Buffer.new([{ name: "a", format: :float }], 1, vertex: true)
    end

    assert_equal "'location' field expected in array element #1 of format table", error.message
  end

  def test_a_format_needs_a_format_that_exists
    error = assert_raises(ArgumentError) { Lota::Graphics::Buffer.new([{ name: "a" }], 1, index: true) }

    assert_equal "'format' field expected in array element #1 of format table", error.message
    assert_match(/Invalid data format 'nope'/, assert_raises(ArgumentError) do
      Lota::Graphics::Buffer.new(:nope, 1, index: true)
    end.message)
  end

  def test_a_usage_that_does_not_exist_is_an_argument_error
    assert_match(/Invalid usage hint 'rarely'/, assert_raises(ArgumentError) do
      Lota::Graphics::Buffer.new(:uint16, 1, index: true, usage: :rarely)
    end.message)
    assert_match(/Invalid buffer type 'nope'/, assert_raises(ArgumentError) do
      Lota::Graphics::Buffer.new(:uint16, 1, index: true).buffer_type?(:nope)
    end.message)
  end

  def test_the_format_of_a_buffer_is_records_that_answer_brackets
    format = Lota::Graphics::Buffer.new([POSITION, { name: "a", format: :uint16, location: 1, arraylength: 0 }], 1,
      vertex: true).format

    assert_equal %w[VertexPosition a], format.map(&:name)
    assert_equal [:floatvec2, :uint16], format.map(&:format)
    assert_equal [0, 8], format.map(&:offset)
    assert_equal 8, format.first[:size]
    assert_equal "VertexPosition", format.first["name"]
    assert_predicate format.first, :frozen?
  end

  def test_a_buffer_is_the_same_object_the_engine_gives_back
    mesh = Lota::Graphics::Mesh.new([[0, 0]], :points)

    assert_same mesh.vertex_buffer, mesh.vertex_buffer
    assert_equal "GraphicsBuffer", mesh.vertex_buffer.object_type
    assert mesh.vertex_buffer.type_of?("Object")
  end

  def test_the_quad_index_buffer_is_an_index_buffer
    assert Lota::Graphics.quad_index_buffer.buffer_type?(:index)
  end

  def test_a_vertex_format_that_names_attributes_and_gives_no_location_is_deprecated
    name = "vertex format 'name' fields in Meshes and Buffers"
    uses = -> { Lota::Deprecation.instance_variable_get(:@deprecated)[name]&.uses.to_i }
    before = uses.call
    Lota::Graphics::Buffer.new([{ name: "VertexPosition", format: :floatvec2, location: -1 }], 1, vertex: true)
    Lota::Graphics::Buffer.new([POSITION], 1, vertex: true)

    assert_equal before + 1, uses.call
    notice = Lota::Deprecation.notice(Lota::Deprecation.instance_variable_get(:@deprecated).fetch(name))

    assert_includes notice, "Using deprecated #{name} (replaced by 'location' field containing a binding location " \
      "number value.)"
  end

  def test_a_mesh_set_a_vertex_at_a_time_stores_what_it_gets
    mesh = Lota::Graphics::Mesh.new(3, :triangles)
    mesh.vertex = 2, 5, 6, 0.25, 0.75, 1, 0, 0, 1
    mesh.vertex = 3, [7, 8]

    assert_equal [5.0, 6.0, 0.25, 0.75, 1.0, 0.0, 0.0, 1.0], mesh.vertex(2)
    assert_equal [7.0, 8.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0], mesh.vertex(3).then { |row| row[0, 4] + [0.0, 0.0, 0.0, 1.0] }
  end

  def test_a_standard_mesh_vertex_needs_a_position_and_defaults_the_rest
    mesh = Lota::Graphics::Mesh.new([[3, 4]], :fan)

    assert_equal [3.0, 4.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0], mesh.vertex(1)
    assert_raises(TypeError) { Lota::Graphics::Mesh.new([[3]], :fan) }
    assert_raises(TypeError) { Lota::Graphics::Mesh.new([3], :fan) }
  end

  def test_a_mesh_of_a_count_of_vertices_starts_at_zero
    mesh = Lota::Graphics::Mesh.new(5, :strip, :static)

    assert_equal 5, mesh.vertex_count
    assert_equal [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], mesh.vertex(5)
  end

  def test_a_mesh_takes_its_vertices_from_a_data
    bytes = Lota::Filesystem::FileData.new([1.0, 2.0, 3.0, 4.0].pack("f4"), "bytes")
    mesh = Lota::Graphics::Mesh.new([{ format: :floatvec2, location: 0 }], bytes, :points)

    assert_equal 2, mesh.vertex_count
    assert_equal [3.0, 4.0], mesh.vertex(2)
    mesh.set_vertices(Lota::Filesystem::FileData.new([9.0, 8.0].pack("f2"), "bytes"), 2, 1)

    assert_equal [9.0, 8.0], mesh.vertex(2)
  end

  def test_the_vertices_a_mesh_is_given_must_fit
    mesh = Lota::Graphics::Mesh.new(2, :fan)

    assert_equal "Vertex count must be greater than 0.",
      assert_raises(RuntimeError) { mesh.set_vertices([[1, 1]], 1, 0) }.message
    assert_equal "Invalid vertex start index (must be between 1 and 2)",
      assert_raises(RuntimeError) { mesh.set_vertices([[1, 1]], 3) }.message
    assert_equal "Too many vertices (expected at most 2, got 3)",
      assert_raises(RuntimeError) { mesh.set_vertices([[1, 1], [2, 2], [3, 3]]) }.message
  end

  def test_a_vertex_outside_the_mesh_is_an_error
    mesh = Lota::Graphics::Mesh.new(2, :fan)

    assert_raises(RuntimeError) { mesh.vertex(3) }
    assert_raises(RuntimeError) { mesh.vertex = 0, 1, 1 }
    assert_equal "Invalid vertex attribute index: 4",
      assert_raises(RuntimeError) { mesh.vertex_attribute(1, 4) }.message
  end

  def test_the_vertex_map_is_a_list_of_indices_or_a_data_of_indices
    mesh = Lota::Graphics::Mesh.new(4, :triangles)
    mesh.set_vertex_map(1, 2, 3, 4)

    assert_equal [1, 2, 3, 4], mesh.vertex_map
    mesh.set_vertex_map(Lota::Filesystem::FileData.new([2, 1, 0].pack("S3"), "indices"), :uint16, 3)

    assert_equal [3, 2, 1], mesh.vertex_map
    mesh.set_vertex_map

    assert_nil mesh.vertex_map
    assert_match(/Invalid index data type 'int8'/, assert_raises(ArgumentError) do
      mesh.set_vertex_map(Lota::Filesystem::FileData.new("ab", "indices"), :int8)
    end.message)
    assert_equal "Invalid index count: 9",
      assert_raises(RuntimeError) { mesh.set_vertex_map(Lota::Filesystem::FileData.new("ab", "indices"), :uint16, 9) }.message
  end

  def test_an_index_buffer_replaces_the_vertex_map
    mesh = Lota::Graphics::Mesh.new(4, :triangles)
    indices = Lota::Graphics::Buffer.new(:uint16, [1, 2, 3], index: true)
    mesh.index_buffer = indices

    assert_same indices, mesh.index_buffer
    mesh.index_buffer = nil

    assert_nil mesh.index_buffer
    assert_raises(TypeError) { mesh.index_buffer = :indices }
  end

  def test_a_mesh_of_buffers_draws_the_attributes_of_its_buffers
    positions = Lota::Graphics::Buffer.new([POSITION], [[0, 0], [8, 0], [8, 8]], vertex: true)
    mesh = Lota::Graphics::Mesh.new([{ buffer: positions, location: 0, name: "VertexPosition" }], :triangles)

    assert_equal 3, mesh.vertex_count
    assert_nil mesh.vertex_buffer
    assert_raises(TypeError) { Lota::Graphics::Mesh.new([{ buffer: positions, location: 0 }, :x], :triangles) }
  end

  def test_attribute_enabled_takes_a_flag_and_an_attribute_by_name_or_location
    mesh = Lota::Graphics::Mesh.new(1, :fan)
    mesh.attribute_enabled = 0, false

    refute mesh.attribute_enabled?("VertexPosition")
    assert_raises(TypeError) { mesh.attribute_enabled = "VertexPosition", 1 }
    assert_raises(TypeError) { mesh.attribute_enabled?(:VertexPosition) }
  end

  def test_attach_attribute_takes_a_buffer_or_a_mesh_that_has_one
    positions = Lota::Graphics::Buffer.new([POSITION], [[0, 0], [8, 0]], vertex: true)
    mesh = Lota::Graphics::Mesh.new(2, :fan)
    custom = { name: "Offset", format: :floatvec2, location: 3 }
    other = Lota::Graphics::Mesh.new([{ name: "VertexPosition", format: :floatvec2, location: 0 }, custom], 2, :fan)
    buffered = Lota::Graphics::Mesh.new([{ buffer: positions, location: 0, name: "VertexPosition" }], :fan)

    mesh.attach_attribute("Offset", other, :perinstance)
    assert mesh.attribute_enabled?("Offset")
    assert_equal "Mesh does not have its own vertex buffer.",
      assert_raises(RuntimeError) { mesh.attach_attribute("Offset", buffered) }.message
    assert_raises(TypeError) { mesh.attach_attribute("Offset", :buffer) }
    assert_match(/Invalid vertex attribute step 'sometimes'/, assert_raises(ArgumentError) do
      mesh.attach_attribute("Offset", other, :sometimes)
    end.message)
  end

  def test_older_vertex_formats_of_arrays_are_read_and_marked_deprecated
    output = Lota::Deprecation.output?
    Lota::Deprecation.output = true
    mesh = nil
    out, = capture_io do
      mesh = Lota::Graphics::Mesh.new([["VertexPosition", "float", 2], ["VertexColor", "byte", 4]], [[1, 2, 1, 0, 0, 1]],
        :points)
    end

    assert_equal [:floatvec2, :unorm8vec4], mesh.vertex_format.map(&:format)
    assert_match(/#{Regexp.escape(__FILE__)}:\d+: Using deprecated vertex format array values in Lota::Graphics::Mesh.new/,
      out)
    assert_match(/Invalid vertex data type 'double'/, assert_raises(ArgumentError) do
      Lota::Graphics::Mesh.new([["a", "double", 1]], 1, :points)
    end.message)
    assert_equal "Invalid component count (3) for vertex data type unorm16",
      assert_raises(RuntimeError) { Lota::Graphics::Mesh.new([["a", "unorm16", 3]], 1, :points) }.message
  ensure
    capture_io { Lota::Deprecation.output = output }
  end

  # A Mesh's constructor allocates its vertex data with new[], and LÖVE's
  # destructor frees it with delete (Mesh.cpp:53 and 140), which Lota's
  # Mesh patch makes delete[] (ext/lota/engine/mesh.patch). Without it,
  # AddressSanitizer on Linux ends rake test:native here, as the C++
  # reference this test holds is released, with an alloc-dealloc-mismatch.
  def test_a_mesh_frees_its_vertex_data_when_its_last_reference_goes
    on_a_finished_fiber do
      LotaNativeTest.observe_mesh(Lota::Graphics::Mesh.new([[0, 0], [1, 0], [1, 1]], :triangles).native)
    end
    collect_garbage

    assert_equal [1], LotaNativeTest.observed_reference_counts
    LotaNativeTest.forget_observed
    assert_empty LotaNativeTest.observed_reference_counts
  ensure
    LotaNativeTest.forget_observed
  end

  def test_a_mesh_draws_where_it_is_placed
    mesh = Lota::Graphics::Mesh.new([
      [0, 0, 0, 0, 1, 0, 0, 1],
      [4, 0, 0, 0, 1, 0, 0, 1],
      [4, 4, 0, 0, 1, 0, 0, 1],
      [0, 4, 0, 0, 1, 0, 0, 1],
], :fan)
    canvas = Lota::Graphics::Canvas.new(8, 8)
    Lota::Graphics.push(:all)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.draw(mesh, 2, 2)
    Lota::Graphics.draw(mesh, Lota::Math::Transform.new(4, 4))
    Lota::Graphics.pop
    data = Lota::Graphics.readback_texture(canvas)

    assert_equal [1.0, 0.0, 0.0, 1.0], data.pixel(3, 3)
    assert_equal [0.0, 0.0, 0.0, 1.0], data.pixel(0, 0)
    assert_equal [1.0, 0.0, 0.0, 1.0], data.pixel(7, 7)
  end

  def test_instanced_drawing_draws_a_mesh_a_number_of_times
    mesh = Lota::Graphics::Mesh.new([[0, 0], [2, 0], [2, 2], [0, 2]], :fan)
    canvas = Lota::Graphics::Canvas.new(4, 4)
    Lota::Graphics.push(:all)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.draw_instanced(mesh, 3, 1, 1)
    Lota::Graphics.draw_instanced(mesh, 2, Lota::Math::Transform.new(0, 0))
    Lota::Graphics.pop

    assert_equal [1.0, 1.0, 1.0, 1.0], Lota::Graphics.readback_texture(canvas).pixel(2, 2)
    assert_raises(TypeError) { Lota::Graphics.draw_instanced(:mesh, 1) }
  end

  def test_a_texture_of_a_mesh_can_be_taken_away
    image = Lota::Graphics::Image.new("resources/love.png")
    mesh = Lota::Graphics::Mesh.new(1, :fan)
    mesh.texture = image
    mesh.texture = nil

    assert_nil mesh.texture
    assert_raises(TypeError) { mesh.texture = :image }
  end

  def test_a_flat_array_that_is_not_whole_is_refused_by_name_of_the_ruby_constructor
    error = assert_raises(RuntimeError) { Lota::Graphics::Buffer.new([POSITION], [1, 2, 3], vertex: true) }

    assert_equal "Array length in flat array variant of Lota::Graphics::Buffer.new must be a multiple of the total " \
      "number of components (2)", error.message
  end

  def test_buffer_is_a_module_that_matches_every_graphics_buffer
    buffer = Lota::Graphics::Buffer.new(:uint16, 2, index: true)

    assert_instance_of Lota::Graphics::GraphicsBuffer, buffer
    assert_equal "GraphicsBuffer", buffer.object_type
    assert_operator Lota::Graphics::Buffer, :===, buffer
    assert_operator Lota::Graphics::Buffer, :===, Lota::Graphics::GraphicsBuffer.new(:uint16, 2, index: true)
    refute_operator Lota::Graphics::Buffer, :===, :buffer
  end

  def test_a_mesh_has_no_attached_attributes_as_loves_function_returns_an_empty_table
    other = Lota::Graphics::Mesh.new([POSITION, { name: "Offset", format: :floatvec2, location: 3 }], 2, :fan)
    mesh = Lota::Graphics::Mesh.new(2, :fan)
    mesh.attach_attribute("Offset", other)

    assert_empty mesh.attached_attributes
  end

  def test_a_custom_mesh_format_cannot_be_empty
    assert_equal "table of tables expected", assert_raises(ArgumentError) { Lota::Graphics::Mesh.new([], 1, :fan) }.message
    assert_equal "table or number expected", assert_raises(ArgumentError) { Lota::Graphics::Mesh.new(:x, :fan) }.message
  end

  def test_a_location_that_is_not_a_number_is_a_type_error
    assert_raises(TypeError) { Lota::Graphics::Buffer.new([{ format: :uint16, location: "a" }], 1, index: true) }
  end

  def test_the_quad_index_buffer_is_a_graphics_buffer_once_a_window_is_open
    assert_instance_of Lota::Graphics::GraphicsBuffer, Lota::Graphics.quad_index_buffer
  end

  def test_indirect_drawing_reads_its_arguments_from_a_buffer
    skip "indirect draws are not supported" unless Lota::Graphics.supported.indirectdraw

    mesh = Lota::Graphics::Mesh.new([[0, 0], [2, 0], [2, 2]], :triangles)
    arguments = Lota::Graphics::Buffer.new(:uint32, [3, 1, 0, 0], indirectarguments: true)
    canvas = Lota::Graphics::Canvas.new(4, 4)
    Lota::Graphics.push(:all)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.draw_indirect(mesh, arguments, 1)
    Lota::Graphics.draw_indirect(mesh, arguments, 1, Lota::Math::Transform.new(1, 1))
    Lota::Graphics.pop

    assert_raises(TypeError) { Lota::Graphics.draw_indirect(mesh, :arguments, 1) }
  end

  def test_a_shader_with_no_compute_stage_cannot_be_dispatched
    shader = Lota::Graphics::Shader.new("vec4 effect(vec4 c, Image t, vec2 tc, vec2 pc) { return c; }\n")

    assert_equal "Only compute shaders can have threads dispatched.",
      assert_raises(RuntimeError) { Lota::Graphics.dispatch_threadgroups(shader, 1) }.message
    refute_operator Lota::Graphics::ComputeShader, :===, shader
    refute_operator Lota::Graphics::ComputeShader, :===, :shader
    assert_raises(TypeError) { Lota::Graphics.dispatch_threadgroups(:shader, 1) }
    assert_raises(TypeError) { Lota::Graphics.dispatch_indirect(shader, :arguments) }
  end

  def test_a_compute_shader_is_dispatched_and_a_buffer_is_sent_to_it
    skip "compute shaders and shader storage buffers need GLSL 4" unless Lota::Graphics.supported.glsl4

    shader = Lota::Graphics::ComputeShader.new(<<~GLSL, debugname: "fill")
      layout(std430) buffer Values { float values[]; };
      layout(local_size_x = 1) in;
      void computemain() { values[gl_GlobalInvocationID.x] = 1.0; }
    GLSL
    values = Lota::Graphics::Buffer.new([{ name: "values", format: :float, arraylength: 0 }], 4, shaderstorage: true)
    shader.__send__(:send, "Values", values)
    Lota::Graphics.dispatch_threadgroups(shader, 4)

    assert_instance_of Lota::Graphics::Shader, shader
    assert_operator Lota::Graphics::ComputeShader, :===, shader
    assert_equal [:float], shader.buffer_format("Values").map(&:format)
    assert_equal ["values"], shader.buffer_format("Values").map(&:name)
    assert_equal "Buffer 'Nothing' does not exist in the Shader.",
      assert_raises(RuntimeError) { shader.buffer_format("Nothing") }.message
    assert_raises(TypeError) { shader.__send__(:send, "Values", :values) }
  end

  def test_a_compute_shader_is_dispatched_for_the_groups_a_buffer_says
    skip "indirect dispatches are not supported" unless Lota::Graphics.supported.indirectdraw && Lota::Graphics.supported.glsl4

    shader = Lota::Graphics::ComputeShader.new(<<~GLSL)
      layout(std430) buffer Values { float values[]; };
      layout(local_size_x = 1) in;
      void computemain() { values[gl_GlobalInvocationID.x] = 1.0; }
    GLSL
    values = Lota::Graphics::Buffer.new([{ name: "values", format: :float, arraylength: 0 }], 4, shaderstorage: true)
    groups = Lota::Graphics::Buffer.new(:uint32, [2, 1, 1], indirectarguments: true)
    shader.__send__(:send, "Values", values)
    Lota::Graphics.dispatch_indirect(shader, groups)
    Lota::Graphics.dispatch_indirect(shader, groups, 1)
  end
end
