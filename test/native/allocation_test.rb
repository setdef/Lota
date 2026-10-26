# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The calls a game makes every frame allocate no Ruby object of their own
# to pass an enum's name: a Symbol's name is a frozen String Ruby keeps
# (Symbol#name), where Symbol#to_s makes a new one each call. These are
# the calls the fixture games draw with (ADR 001, section 8).
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

  # A String works where a Symbol does, as LÖVE's names were strings.
  def test_a_string_name_still_works
    Lota::Graphics.rectangle("fill", 1, 2, 3, 4)
    Lota::Graphics.line_style = "rough"

    assert_equal :rough, Lota::Graphics.line_style
  end
end
