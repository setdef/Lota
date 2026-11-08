# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Graphics::ParticleSystem beyond what Lövetest's tests for it check
# (test/lovetest/tests/graphics.rb): the forms of the setters that take a
# range, sizes, colors, and quads, and the errors each raises
# (wrap_ParticleSystem.cpp:41-618), the clone ADR 001 maps to Ruby's, and
# the drawing of a system placed by numbers or a Transform.
class ParticleSystemTest < Minitest::Test
  def setup
    EngineHelper.open_window
    Lota::Graphics.color = 1, 1, 1, 1
    @image = Lota::Graphics::Image.new("resources/pixel.png")
    @particles = Lota::Graphics::ParticleSystem.new(@image, 10)
  end

  def test_a_system_has_the_size_it_was_made_with_or_one_thousand
    assert_equal 10, @particles.buffer_size
    assert_equal 1000, Lota::Graphics::ParticleSystem.new(@image).buffer_size
    assert_equal 1000, Lota::Graphics::ParticleSystem.new(@image, nil).buffer_size
    assert_equal "Invalid ParticleSystem size", assert_raises(RuntimeError) {
      Lota::Graphics::ParticleSystem.new(@image, 0)
    }.message
    assert_raises(TypeError) { Lota::Graphics::ParticleSystem.new(:image) }
  end

  def test_the_buffer_size_must_be_at_least_one
    @particles.buffer_size = 20

    assert_equal 20, @particles.buffer_size
    assert_equal "Invalid buffer size", assert_raises(RuntimeError) { @particles.buffer_size = 0 }.message
  end

  def test_a_range_takes_one_value_for_both_ends_or_two
    @particles.speed = 5
    assert_equal [5.0, 5.0], @particles.speed
    @particles.speed = [1, 2]
    assert_equal [1.0, 2.0], @particles.speed
    @particles.rotation = 0.5
    assert_equal [0.5, 0.5], @particles.rotation
    @particles.linear_acceleration = 1, 2
    assert_equal [1.0, 2.0, 1.0, 2.0], @particles.linear_acceleration
    assert_equal "wrong number of arguments (given 3, expected 1..2)",
      assert_raises(ArgumentError) { @particles.speed = 1, 2, 3 }.message
    assert_equal "wrong number of arguments (given 1, expected 2..4)",
      assert_raises(ArgumentError) { @particles.linear_acceleration = 1 }.message
    assert_equal "wrong number of arguments (given 1, expected 2)",
      assert_raises(ArgumentError) { @particles.position = 1 }.message
  end

  def test_a_lifetime_cannot_be_negative
    assert_equal "Invalid particle lifetime (must be >= 0)",
      assert_raises(RuntimeError) { @particles.particle_lifetime = -1 }.message
    @particles.particle_lifetime = 3
    assert_equal [3.0, 3.0], @particles.particle_lifetime
  end

  def test_the_size_and_spin_variations_are_checked
    assert_equal "Size variation has to be between 0 and 1, inclusive.",
      assert_raises(RuntimeError) { @particles.size_variation = 2 }.message
  end

  def test_sizes_take_one_to_eight_numbers
    @particles.sizes = 2
    assert_equal [2.0], @particles.sizes
    @particles.sizes = [1, 2, 3]
    assert_equal [1.0, 2.0, 3.0], @particles.sizes
    assert_equal "At most eight (8) sizes may be used.",
      assert_raises(RuntimeError) { @particles.sizes = (1..9).to_a }.message
    assert_raises(TypeError) { @particles.sizes = [1, "x"] }
  end

  def test_colors_take_rows_or_every_component_one_after_another
    @particles.colors = [[1, 0, 0], [0, 0, 1, 0.5]]
    assert_equal [[1.0, 0.0, 0.0, 1.0], [0.0, 0.0, 1.0, 0.5]], @particles.colors
    @particles.colors = 0, 1, 0, 1
    assert_equal [[0.0, 1.0, 0.0, 1.0]], @particles.colors
    @particles.colors = @particles.colors + [[1, 1, 1, 1]]
    assert_equal 2, @particles.colors.size
  end

  def test_colors_must_be_whole_and_at_most_eight
    assert_equal "Expected red, green, blue, and alpha. Only got 2 of 4 components.",
      assert_raises(RuntimeError) { @particles.colors = 1, 1, 1, 1, 1, 1 }.message
    assert_equal "At most eight (8) colors may be used.",
      assert_raises(RuntimeError) { @particles.colors = [[1, 1, 1, 1]] * 9 }.message
    assert_equal "expected 4 color components", assert_raises(ArgumentError) { @particles.colors = [[1, 1]] }.message
    assert_raises(TypeError) { @particles.colors = [[1, 1, "x", 1]] }
  end

  def test_quads_are_the_quads_given_or_none
    quad = Lota::Graphics::Quad.new(0, 0, 1, 1, @image)
    @particles.quads = quad
    assert_equal 1, @particles.quads.size
    assert_equal [0.0, 0.0, 1.0, 1.0], @particles.quads.first.viewport
    @particles.quads = []
    assert_empty @particles.quads
    assert_raises(TypeError) { @particles.quads = [:quad] }
  end

  def test_an_emission_area_needs_its_extents_unless_it_is_none
    @particles.emission_area = :none
    assert_equal :none, @particles.emission_area.first
    @particles.emission_area = nil
    assert_equal :none, @particles.emission_area.first
    @particles.emission_area = :borderellipse, 8, 4, 0.5, true
    assert_equal [:borderellipse, 8.0, 4.0, 0.5, true], @particles.emission_area
    assert_equal "Invalid area spread parameters (must be >= 0)",
      assert_raises(RuntimeError) { @particles.emission_area = :uniform, -1, 4 }.message
    assert_raises(ArgumentError) { @particles.emission_area = :uniform }
    assert_match(/Invalid particle distribution 'square'/, assert_raises(ArgumentError) {
      @particles.emission_area = :square, 1, 1
    }.message)
    assert_raises(TypeError) { @particles.emission_area = :uniform, "x", 1 }
  end

  def test_a_single_color_component_is_an_incomplete_color
    assert_equal "Expected red, green, blue, and alpha. Only got 1 of 4 components.",
      assert_raises(RuntimeError) { @particles.colors = 1 }.message
  end

  def test_only_true_faces_an_emission_away_from_the_center_and_only_a_flag_sets_relative_rotation
    @particles.emission_area = :uniform, 1, 1, 0, 1

    refute @particles.emission_area.last
    @particles.relative_rotation = true

    assert_predicate @particles, :relative_rotation?
    assert_raises(TypeError) { @particles.relative_rotation = nil }
  end

  def test_the_insert_mode_is_one_of_three
    assert_match(/Invalid insert mode 'middle'/, assert_raises(ArgumentError) { @particles.insert_mode = :middle }.message)
  end

  def test_a_clone_is_a_copy_that_is_kept_apart
    @particles.speed = 3, 4
    copy = @particles.clone

    refute_same @particles, copy
    assert_equal [3.0, 4.0], copy.speed
    copy.speed = 9
    assert_equal [3.0, 4.0], @particles.speed
    assert_equal "ParticleSystem", copy.object_type
    assert_equal @particles.texture.width, copy.dup.texture.width
  end

  def test_the_texture_can_be_replaced_by_a_texture_only
    other = Lota::Graphics::Image.new("resources/love.png")
    @particles.texture = other

    assert_same other, @particles.texture
    assert_raises(TypeError) { @particles.texture = :other }
  end

  def test_a_system_draws_its_particles_where_it_is_placed
    @particles.particle_lifetime = 5
    @particles.emitter_lifetime = 100
    @particles.emission_rate = 10
    @particles.colors = 1, 0, 0, 1
    @particles.sizes = 4
    @particles.start
    @particles.update(1)
    canvas = Lota::Graphics::Canvas.new(16, 16)
    Lota::Graphics.push(:all)
    Lota::Graphics.canvas = canvas
    Lota::Graphics.clear(0, 0, 0, 1)
    Lota::Graphics.draw(@particles, 8, 8)
    Lota::Graphics.draw(@particles, Lota::Math::Transform.new(12, 12))
    Lota::Graphics.pop
    data = Lota::Graphics.readback_texture(canvas)

    assert_equal [1.0, 0.0, 0.0, 1.0], data.pixel(8, 8)
    assert_equal [1.0, 0.0, 0.0, 1.0], data.pixel(12, 12)
    assert_equal [0.0, 0.0, 0.0, 1.0], data.pixel(0, 0)
  end

  def test_a_system_counts_what_it_emits_and_forgets_it_when_reset
    @particles.particle_lifetime = 5
    @particles.emit(4)

    assert_equal 4, @particles.count
    @particles.reset
    assert_equal 0, @particles.count
  end

  def test_a_system_can_be_moved_with_or_without_its_particles
    @particles.position = 1, 2
    @particles.move_to(5, 6)

    assert_equal [5.0, 6.0], @particles.position
  end
end
