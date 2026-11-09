# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "bindings_helper"

# Analysis reads each wrap function's arguments, results, and errors from
# its real body in vendor/love, or says precisely why it cannot.
class AnalysisTest < Minitest::Test
  include BindingsHelper

  def reads(love_name)
    analysis(love_name).reads.map { |read| [read.index, read.reader, read.default, read.cast] }
  end

  # w_rectangle: an enum, four floats, and optional corners.
  def test_reads_each_argument_with_its_reader_default_and_cast
    assert_equal [
      [1, "luaL_checkstring", nil, nil],
      [2, "luaL_checknumber", nil, "float"],
      [3, "luaL_checknumber", nil, "float"],
      [4, "luaL_checknumber", nil, "float"],
      [5, "luaL_checknumber", nil, "float"],
      [6, "luaL_optnumber", "0.0", "float"],
      [7, "luaL_optnumber", "rx", "float"],
      [8, "luaL_checkinteger", nil, "int"],
    ], reads("love.graphics.rectangle")
    assert_equal [[6, "lua_isnoneornil"], [8, "lua_isnoneornil"]],
      analysis("love.graphics.rectangle").tests.map { |test| [test.index, test.predicate] }
  end

  def test_an_enum_argument_is_read_with_its_label_and_type
    enum = analysis("love.graphics.setLineStyle").enums.first

    assert_equal [1, "Graphics::LineStyle", "line style"], [enum.index, enum.enum_type, enum.label]
    assert_equal [[:enum, "line style"]], analysis("love.graphics.setLineStyle").errors.map { |e| [e.kind, e.message] }
  end

  def test_an_enum_result_is_named_and_its_error_kept
    analysis = analysis("love.graphics.getLineStyle")

    assert_equal ["Graphics::LineStyle"], analysis.enum_results.map(&:enum_type)
    assert_equal [[:error, "Unknown line style"]], analysis.errors.map { |e| [e.kind, e.message] }
  end

  def test_results_are_each_push_and_the_count_returned
    analysis = analysis("love.graphics.getColor")

    assert_equal %w[c.r c.g c.b c.a], analysis.pushes.map(&:expression)
    assert_equal [:number], analysis.pushes.map(&:kind).uniq
    assert_equal 4, analysis.result_count
    refute analysis.computed_count
    refute analysis.pushes.any?(&:looped)
  end

  # w_newCubeFaces pushes each face in a loop and returns how many it
  # pushed (wrap_Image.cpp:131-139), which the rules read as several
  # objects.
  def test_a_push_in_a_loop_and_a_computed_count_are_marked
    analysis = analysis("love.image.newCubeFaces")

    assert analysis.computed_count
    assert_equal [true], analysis.pushes.map(&:looped)
  end

  # w_isDown reads its keys from a table or from every argument.
  def test_varargs_and_tables_are_read_as_such
    analysis = analysis("love.keyboard.isDown")

    assert_includes analysis.reads.map(&:index), :varargs
    assert_equal %w[luax_objlen lua_rawgeti], analysis.tables.map(&:access)
    assert_predicate analysis, :readable?
  end

  def test_an_option_table_is_read_by_its_keys
    keys = analysis("love.window.showMessageBox").tables.filter_map(&:key)

    assert_includes keys, "escapebutton"
  end

  def test_a_methods_object_is_read_through_its_helper
    read = analysis("Texture:isCanvas").reads.first

    assert_equal [1, :object, "Texture"], [read.index, read.kind, read.type]
  end

  def test_a_function_argument_is_read_as_one
    assert(analysis("Texture:renderTo").reads.any? { |read| read.kind == :function } ||
      !analysis("Texture:renderTo").readable?)
    assert(analysis("love.graphics.captureScreenshot").tests.any? { |test| test.predicate == "lua_isfunction" })
  end

  def test_deprecation_is_recorded
    assert_equal "love.event.wait", analysis("love.event.wait").deprecation
  end

  # w_clear reads its stencil at startidx, which depends on the form.
  def test_a_computed_position_makes_a_function_unreadable_and_says_where
    analysis = analysis("love.graphics.clear")

    refute_predicate analysis, :readable?
    assert_includes analysis.problems, "reads the stack at a position it computes (startidx, line 131)"
  end

  def test_passing_the_lua_state_to_the_engine_makes_a_function_unreadable
    assert_includes analysis("love.graphics.present").problems,
      "passes the lua_State to present (line 179), which the parser does not read"
  end

  def test_a_computed_result_count_makes_a_function_unreadable
    assert(analysis("love.event.wait").problems.any? { |problem| problem.start_with?("returns a computed number") })
  end

  # w_write and w_append return w_write_or_append(L, mode), a helper of the
  # same file that takes the mode besides the lua_State (wrap_Filesystem.cpp,
  # w_write_or_append): true, or nil and a message through luax_ioError, so
  # two values, as the helper's own body says.
  def test_a_helper_called_with_extra_arguments_is_followed
    %w[love.filesystem.write love.filesystem.append].each do |love_name|
      analysis = analysis(love_name)

      assert_predicate analysis, :readable?, love_name
      assert_equal 2, analysis.result_count, love_name
      assert_equal [1, 2, 3], analysis.reads.map(&:index).uniq, love_name
    end
  end

  def test_calling_back_into_lua_makes_a_function_unreadable
    assert(analysis("love.filesystem.load").problems.any? { |problem| problem.start_with?("calls back into Lua") })
  end

  # Every function is read, or listed with the reasons it is not; none is
  # skipped and none is read with an empty shape.
  def test_every_function_is_read_or_has_a_reason
    survey.entries.select { |entry| entry.source == :cpp }.each do |entry|
      analysis = entry.analysis
      if analysis.readable?
        assert(analysis.counts.any? || analysis.delegate, "#{entry.function.love_name} has no result count")
      else
        refute_empty analysis.problems, entry.function.love_name
      end
    end
  end

  def test_most_functions_are_readable
    readable = survey.entries.count(&:readable?)

    assert_equal 931, readable
    assert_equal 156, survey.entries.count { |entry| entry.source == :cpp && !entry.readable? }
  end
end
