# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Lota::Deprecation, ported from LÖVE's src/common/deprecation.cpp and
# luax_markdeprecated (src/common/runtime.cpp:1074-1091): the first use of
# each deprecated name prints a notice, while output is on, and turning
# output on prints the notices of names used once while it was off. Each
# test marks names of its own, as the record lasts as long as the
# process, as LÖVE's does.
class DeprecationTest < Minitest::Test
  Deprecation = Lota::Deprecation

  def setup
    @output = Deprecation.output?
    Deprecation.output = true
  end

  def teardown
    capture_io { Deprecation.output = @output }
  end

  def test_the_first_use_prints_where_and_what_replaced_it
    out, = capture_io do
      Deprecation.mark("test.first", :field, :replaced, "test.second", where: "main.rb:3: ")
    end

    assert_equal "Lota - Warning: main.rb:3: Using deprecated field test.first (replaced by test.second)\n", out
  end

  def test_later_uses_print_nothing
    capture_io { Deprecation.mark("test.again", :function, where: "main.rb:1: ") }
    out, = capture_io { Deprecation.mark("test.again", :function, where: "main.rb:2: ") }

    assert_empty out
  end

  # getDeprecationNotice (deprecation.cpp:99-131): each API type's word,
  # and renamed as well as replaced.
  def test_a_notice_names_the_kind_of_api_and_how_it_changed
    notices = {
      ["test.function", :function, :noreplacement, nil] => "Using deprecated function test.function",
      ["test.variant", :functionvariant, :noreplacement, nil] => "Using deprecated function variant in test.variant",
      ["test.method", :method, :renamed, "test.renamed"] => "Using deprecated method test.method (renamed to test.renamed)",
      ["test.method_variant", :methodvariant, :noreplacement, nil] => "Using deprecated method variant in test.method_variant",
      ["test.callback", :callback, :noreplacement, nil] => "Using deprecated callback test.callback",
      ["test.constant", :constant, :noreplacement, nil] => "Using deprecated constant test.constant",
      ["test.custom", :custom, :replaced, "test.other"] => "Using deprecated test.custom (replaced by test.other)",
    }

    notices.each do |(name, api, type, replacement), notice|
      out, = capture_io { Deprecation.mark(name, api, type, replacement) }

      assert_equal "Lota - Warning: #{notice}\n", out
    end
  end

  # setDeprecationOutputEnabled (deprecation.cpp:75-92): while output is
  # off nothing prints, and turning it on prints each name used once, so
  # far, whenever it was used, as LÖVE does.
  def test_turning_output_on_prints_what_was_used_once_while_it_was_off
    Deprecation.output = false
    out, = capture_io do
      Deprecation.mark("test.quiet", :field, where: "a.rb:1: ")
      Deprecation.mark("test.twice", :field, where: "a.rb:2: ")
      Deprecation.mark("test.twice", :field, where: "a.rb:3: ")
    end
    assert_empty out
    refute_predicate Deprecation, :output?

    out, = capture_io { Deprecation.output = true }
    assert_includes out, "Lota - Warning: a.rb:1: Using deprecated field test.quiet\n"
    refute_includes out, "test.twice"
    assert_predicate Deprecation, :output?
  end

  def test_an_unknown_api_or_deprecation_type_is_refused
    assert_raises(ArgumentError) { Deprecation.mark("test.bad", :table) }
    assert_raises(ArgumentError) { Deprecation.mark("test.bad", :field, :removed) }
  end
end
