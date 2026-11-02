# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/variant"

# Lota::Variant: the tokens a value crosses between Ruby and the engine
# in, as luax_checkvariant reads a Lua value and luax_pushvariant makes
# one again (vendor/love/src/common/runtime.cpp:722-861). That the engine
# carries them is test/native/event_poll_test.rb's to prove.
class VariantTest < Minitest::Test
  def test_a_table_is_its_pairs_in_order_after_its_count
    assert_equal [:table, 2, 1.0, "a", 2.0, :table, 1, "k", true], Lota::Variant.tokens(["a", { k: true }])
    assert_equal [nil], Lota::Variant.tokens(nil)
    assert_equal [0.5], Lota::Variant.tokens(1/2r)
  end

  # A pair of unknown type makes its table so (runtime.cpp:784-808), and
  # each table it is in.
  def test_a_table_with_a_function_in_it_is_one_unknown_token
    assert_equal [:unknown], Lota::Variant.tokens([1, [2, [-> {}]]])
    assert_equal [:unknown], Lota::Variant.tokens({ 1.method(:+) => 1 })
  end

  def test_what_tokens_write_read_gives_back_as_the_queue_does
    assert_equal [1.0, { "k" => [true, nil] }, []], read([1, { k: [true, nil] }, {}])
    assert_equal({ 1.0 => "a", 3.0 => "c" }, read({ 1 => "a", 3 => "c" }))
    assert_equal %w[a b], read({ 2 => "b", 1 => "a" })
  end

  # luax_pushvariant sets each pair in turn, so of two keys that become one
  # the later wins (runtime.cpp:837-853), and the table they make may be
  # a sequence.
  def test_keys_that_become_one_keep_the_later_value
    assert_equal ["b"], read({ 1 => "a", 1.0 => "b" })
    assert_equal({ "k" => 2.0 }, read({ "k" => 1, :k => 2 }))
  end

  def test_tokens_that_are_not_one_value_are_refused
    [[], [:table], [:table, 1, 1.0], [1.0, 2.0], [:unknown], [:table, "1"], [:table, -1, nil]].each do |tokens|
      assert_raises(ArgumentError, tokens.inspect) { Lota::Variant.read(tokens) }
    end
  end

  def test_only_the_values_a_table_can_hold_are_values
    assert Lota::Variant.value?(1/2r)
    refute Lota::Variant.value?(Complex(1, 2))
    refute Lota::Variant.value?(Object.new)
    assert_raises(TypeError) { Lota::Variant.tokens([Complex(1, 2)]) }
  end

  private def read(value) = Lota::Variant.read(Lota::Variant.tokens(value))
end
