# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/restart"

# The value a restart carries across exec, in an environment variable no
# one trusts: it holds nil, booleans, numbers and strings, and anything
# else is dropped. That a restart starts the game again is
# test/native/restart_run_test.rb's to prove, in processes of their own.
class RestartTest < Minitest::Test
  def roundtrip(value)
    Lota::Restart.decode(Lota::Restart.encode(value))
  end

  def test_nil_booleans_numbers_and_strings_cross_as_they_are
    assert_nil roundtrip(nil)
    assert_same true, roundtrip(true)
    assert_same false, roundtrip(false)
    assert_equal 2.5, roundtrip(2.5)
    assert_equal "café\nline: \"quoted\"", roundtrip("café\nline: \"quoted\"")
    assert_equal "", roundtrip("")
  end

  def test_every_float_crosses_with_its_bits
    assert_predicate roundtrip(Float::NAN), :nan?
    assert_equal Float::INFINITY, roundtrip(Float::INFINITY)
    assert_equal(-Float::INFINITY, roundtrip(-Float::INFINITY))
    assert_equal 0.1, roundtrip(0.1)
    assert_equal "-0.0", roundtrip(-0.0).to_s
    assert_equal 1.0e-310, roundtrip(1.0e-310)
  end

  def test_an_integer_crosses_as_a_float_and_a_symbol_as_a_string
    assert_equal 7.0, roundtrip(7)
    assert_instance_of Float, roundtrip(7)
    assert_equal "name", roundtrip(:name)
  end

  def test_a_string_that_is_not_utf8_keeps_its_bytes
    bytes = roundtrip("\xff\x00".b)

    assert_equal [0xff, 0x00], bytes.bytes
  end

  def test_what_the_queue_cannot_carry_is_refused
    [[1], {}, Object.new, -> {}, 1..2, Complex(1, 2)].each do |value|
      error = assert_raises(TypeError) { Lota::Restart.encode(value) }
      assert_includes error.message, value.class.to_s
    end
  end

  def test_nothing_but_what_encode_writes_is_read
    [
      "",
      "nil",
      "nil:x",
      "boolean:1",
      "boolean:true ",
      "number:",
      "number:zz00000000000000",
      "number:0000000000000000\n",
      "number:00000000000000000",
      "string:abc",
      "string:6869\nnil:",
      "string:6869:",
      "symbol:6869",
      "eval:1+1",
      "[\"nil\"]",
      "nil:\nnil:",
      " nil:",
      "NIL:",
      "number:0x00000000000000",
].each do |text|
      assert_raises(ArgumentError, text.inspect) { Lota::Restart.decode(text) }
    end
  end

  def test_what_the_game_set_is_read_once_and_removed
    environment = { Lota::Restart::VARIABLE => Lota::Restart.encode("hi"), "OTHER" => "kept" }
    restart = Lota::Restart.dup
    restart.instance_variable_set(:@taken, false)

    restart.take(environment)

    assert_equal "hi", restart.value
    assert_equal({ "OTHER" => "kept" }, environment)

    environment[Lota::Restart::VARIABLE] = Lota::Restart.encode("again")
    restart.take(environment)

    assert_equal "hi", restart.value, "only the first read counts"
  end

  def test_a_variable_that_is_not_a_restart_value_is_removed_and_ignored
    environment = { Lota::Restart::VARIABLE => "eval:system('echo pwned')" }
    restart = Lota::Restart.dup
    restart.instance_variable_set(:@taken, false)

    restart.take(environment)

    assert_nil restart.value
    assert_empty environment
  end

  def test_asking_to_restart_with_what_cannot_cross_raises_before_the_game_ends
    assert_raises(TypeError) { Lota::Restart.request([1]) }
  end
end
