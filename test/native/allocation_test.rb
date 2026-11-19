# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "objspace"
require_relative "native_helper"
require_relative "../engine_helper"

# The calls a game makes every frame allocate no Ruby object of their own
# to pass an enum's name: a Symbol's name is a frozen String Ruby keeps
# (Symbol#name), where Symbol#to_s makes a new one each call. These are
# the calls the fixture games draw with (doc/contributors/design/engine.md).
class AllocationTest < Minitest::Test
  def setup
    EngineHelper.open_window
    @line_style = Lota::Graphics.line_style
  end

  # The tests that share this process draw with the line style Lövetest's
  # love.load set.
  def teardown
    Lota::Graphics.line_style = @line_style
  end

  # Objects allocated by +calls+ calls of the block, counted by count after
  # one count of a single call. The first time Ruby runs a call site it
  # allocates the site's inline cache (an internal object GC.stat counts),
  # once; the warm-up runs every call site the measurement runs, the
  # block's and count's own, so that only what the calls allocate is
  # counted, while an allocation in each call still counts +calls+ times.
  def allocations(calls = 100, &)
    count(1, &)
    count(calls, &)
  end

  def count(calls)
    GC.disable
    before = GC.stat(:total_allocated_objects)
    calls.times { yield }
    GC.stat(:total_allocated_objects) - before
  ensure
    GC.enable
  end

  def test_drawing_a_shape_allocates_nothing
    assert_equal 0, allocations { Lota::Graphics.rectangle(:fill, 1, 2, 3, 4) }
    assert_equal 0, allocations { Lota::Graphics.circle(:line, 1, 2, 3) }
    assert_equal 0, allocations { Lota::Graphics.ellipse(:fill, 1, 2, 3, 4) }
  end

  # arc's angles join an Array, as it reads them from LÖVE's position-
  # dependent arguments (Lota::Graphics.arc), and nothing else allocates.
  def test_drawing_an_arc_allocates_only_its_arguments
    assert_equal 100, allocations(100) { Lota::Graphics.arc(:fill, :pie, 1, 2, 3, 0, 1) }
  end

  def test_setting_the_line_style_allocates_nothing
    assert_equal 0, allocations { Lota::Graphics.line_style = :smooth }
  end

  # The keys join an Array, as Lota::Keyboard.down? passes them as one.
  def test_asking_whether_keys_are_down_allocates_only_their_list
    assert_equal 200, allocations(100) { Lota::Keyboard.down?(:a, :b) }
  end

  # Setting a color allocates only the Array its four values arrive in.
  def test_setting_a_color_allocates_only_its_values
    batch = Lota::Graphics::SpriteBatch.new(Lota::Graphics::Canvas.new(8, 4))

    assert_equal 100, allocations(100) { Lota::Graphics.color = 0.25, 0.5, 0.75, 1.0 }
    assert_equal 100, allocations(100) { Lota::Graphics.background_color = 0.25, 0.5, 0.75, 1.0 }
    assert_equal 100, allocations(100) { batch.color = 0.25, 0.5, 0.75, 1.0 }
  ensure
    Lota::Graphics.color = 1, 1, 1, 1
    Lota::Graphics.background_color = 0, 0, 0, 1
  end

  # A String works where a Symbol does, as LÖVE's names were strings.
  def test_a_string_name_still_works
    Lota::Graphics.rectangle("fill", 1, 2, 3, 4)
    Lota::Graphics.line_style = "rough"

    assert_equal :rough, Lota::Graphics.line_style
  end

  # A getter's Array of four holds its values in its own slot, with no
  # buffer from malloc, which Ruby 4.1 counts toward a major collection
  # (oldmalloc). Lota's loop reads the background color every frame, and
  # games read the color and the scissor (tasks/bindings/port.rb).
  def test_a_getters_array_of_four_needs_no_buffer_of_its_own
    Lota::Graphics.scissor = 1, 2, 3, 4

    [Lota::Graphics.color, Lota::Graphics.background_color, Lota::Graphics.scissor].each do |values|
      assert_equal 4, values.size
      assert_includes ObjectSpace.dump(values), %("embedded":true), values.inspect
    end
  ensure
    Lota::Graphics.scissor = nil
  end

  # Fails unless each of +arrays+, by name, holds its values in its own
  # slot, naming every one that has a buffer of its own.
  def assert_embedded(arrays)
    buffered = arrays.reject { |_name, values| ObjectSpace.dump(values).include?(%("embedded":true)) }

    assert_empty buffered.keys, "a buffer of its own holds the values of each of #{buffered.keys.join(', ')}"
  end

  # The hand-written bindings that return four or more values of a fixed
  # count make their Array with room for them all, as the generated ones
  # do (ext/lota/native/ruby.hpp, ruby::array_with_room).
  def test_a_hand_written_records_array_needs_no_buffer_of_its_own
    canvas = Lota::Graphics::Canvas.new(4, 4)
    Lota::Graphics.canvas = canvas
    _tables, targets, = Lota::Native::Graphics.canvas
    Lota::Graphics.canvas = nil
    particles = Lota::Graphics::ParticleSystem.new(canvas)
    particles.colors = [[1, 0, 0, 1], [0, 1, 0, 0.5]]
    buffer = Lota::Graphics::Buffer.new([{ name: "VertexPosition", format: :floatvec2, location: 0 }], 2, vertex: true)
    mesh = Lota::Graphics::Mesh.new(3, :fan)

    assert_embedded(
      "Native::Graphics.blend_state" => Lota::Native::Graphics.blend_state,
      "Native::Graphics.canvas's target" => targets.first,
      "ParticleSystem#colors" => particles.colors.first,
      "Buffer#format" => buffer.__send__(:native).format.first,
      "Mesh#vertex_format" => mesh.__send__(:native).vertex_format.first,
      "Mesh#vertex" => mesh.vertex(1),
      "Mesh#vertex_attribute" => mesh.vertex_attribute(1, 3),
      "ImageData#pixel" => Lota::Image::ImageData.new(2, 2).pixel(1, 1),
      "Transform#matrix" => Lota::Math::Transform.new.matrix,
      "Native::Audio.orientation" => Lota::Native::Audio.orientation,
    )
  end

  def test_a_ray_casts_hit_needs_no_buffer_of_its_own
    world = Lota::Physics::World.new(0, 0)
    Lota::Physics::RectangleShape.new(Lota::Physics::Body.new(world, 10, 0, :static), 4, 4)
    native = world.__send__(:native)

    assert_embedded(
      "World#ray_cast_any" => native.ray_cast_any(0, 0, 20, 0, nil),
      "World#ray_cast_closest" => native.ray_cast_closest(0, 0, 20, 0, nil),
    )
  ensure
    world&.destroy
  end

  def test_a_files_information_needs_no_buffer_of_its_own
    previous = Lota::Filesystem.identity
    Lota::Filesystem.identity = "lota-allocation-test"
    Lota::Filesystem.write("info.txt", "hi")

    assert_embedded("Native::Filesystem.info" => Lota::Native::Filesystem.info("info.txt", nil))
  ensure
    Lota::Filesystem.remove("info.txt")
    Lota::Filesystem.identity = previous
  end
end
