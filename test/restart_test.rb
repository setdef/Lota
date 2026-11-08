# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/restart"

# The value a restart carries across exec, in an environment variable no
# one trusts: it holds nil, booleans, numbers, strings, and tables of
# them, and anything else is dropped. That a restart starts the game again is
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

  # A table crosses as the event queue gives one back: keys 1 to n make an
  # Array, and any others a Hash, with numbers as Floats and Symbols as
  # Strings, keys and values alike.
  def test_tables_cross_as_the_queue_gives_them_back
    assert_equal [1.0, "two", [true, nil], []], roundtrip([1, :two, [true, nil], {}])
    assert_equal({ "name" => "Ada", 0.0 => false, true => { "deep" => [2.5] }, nil => "nil key" },
      roundtrip({ :name => "Ada", 0 => false, true => { deep: [2.5] }, nil => "nil key" }))
    assert_equal %w[a b], roundtrip({ 2 => "b", 1 => "a" })
    assert_equal({ 1.0 => "a", 3.0 => "c" }, roundtrip({ 1 => "a", 3 => "c" }))
  end

  def test_a_string_in_a_table_keeps_its_bytes_and_is_utf8
    key, value = roundtrip({ "café" => "\xff\x00".b }).first

    assert_equal "café", key
    assert_equal Encoding::UTF_8, key.encoding
    assert_equal [0xff, 0x00], value.bytes
    assert_equal Encoding::UTF_8, value.encoding
  end

  def test_tables_nest_as_deep_as_the_limit
    deepest = Lota::Restart::MAXIMUM_DEPTH.times.reduce(1) { |inner, _| [inner] }

    assert_equal deepest, roundtrip(deepest)
    error = assert_raises(TypeError) { Lota::Restart.encode([deepest]) }
    assert_includes error.message, Lota::Restart::MAXIMUM_DEPTH.to_s
  end

  def test_what_the_queue_cannot_carry_is_refused
    [Object.new, -> {}, 1..2, Complex(1, 2), [Object.new], { a: -> {} }, { Object.new => 1 }].each do |value|
      error = assert_raises(TypeError) { Lota::Restart.encode(value) }
      assert_match(/Object|Proc|Range|Complex/, error.message)
    end
  end

  def test_a_table_that_holds_itself_is_refused_and_a_shared_one_crosses
    cycle = [1]
    cycle << { again: cycle }
    error = assert_raises(TypeError) { Lota::Restart.encode(cycle) }

    assert_equal "Cycle detected in table", error.message

    shared = [1]

    assert_equal [[1.0], [1.0]], roundtrip([shared, shared])
  end

  # Environment variables are limited in size on every system, the largest
  # to a megabyte (macOS's ARG_MAX), so nothing longer can cross.
  def test_a_value_too_long_for_the_environment_is_refused
    error = assert_raises(TypeError) { Lota::Restart.encode("x" * Lota::Restart::MAXIMUM_LENGTH) }

    assert_includes error.message, "too long"
    assert_raises(ArgumentError) { Lota::Restart.decode("string:#{'78' * Lota::Restart::MAXIMUM_LENGTH}") }
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
      "table:",
      "table:(",
      "table:()x",
      "table:())",
      "table:(nil:)",
      "table:(nil:,)",
      "table:(nil:,nil:;)",
      "table:(nil:,nil:",
      "table:(nil:,nil:,nil:)",
      "table:(;)",
      "table:(string:abc,nil:)",
      "table:(nil: ,nil:)",
      "table:[nil:,nil:]",
      "array:()",
      "table:(eval:1,nil:)",
      "#{'table:(nil:,' * (Lota::Restart::MAXIMUM_DEPTH + 1)}nil:#{')' * (Lota::Restart::MAXIMUM_DEPTH + 1)}",
      "table:(nil:,\xff)",
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

  LOTA = File.expand_path("../exe/lota", __dir__)

  # A copy of Lota::Restart that remembers +arguments+, with +fused+, as
  # it would in a process whose $0 is +program+, and has registered no
  # exit proc in this one.
  def remembered(program, arguments, fused: false)
    copy = Lota::Restart.dup
    copy.instance_variable_set(:@installed, true)
    before = $PROGRAM_NAME
    begin
      $PROGRAM_NAME = program
      copy.remember(arguments, fused:)
    ensure
      $PROGRAM_NAME = before
    end
    copy
  end

  # bundle exec loads the program in its own process, where Process.argv0
  # is bundle (Bundler::CLI::Exec, kernel_load) and $0 the program, so
  # lota run remembers $0.
  def test_lota_run_remembers_the_program_ruby_runs_not_the_one_the_process_began_with
    command = remembered(LOTA, ["run", "games/pong"]).instance_variable_get(:@command)

    assert_equal RbConfig.ruby, command.first
    assert_equal [LOTA, "run", "games/pong"], command.last(3)
  end

  # A fused game starts again as LÖVE's does, by running its program again
  # with its arguments (src/love.cpp, main): the app's own launcher, as
  # Fledge builds it. Only when the program is Ruby's own, as when someone
  # runs the entry script with ruby, does it start Ruby with the script.
  def test_a_fused_game_starts_its_program_again_with_its_arguments
    copy = remembered(LOTA, ["--level", "2"], fused: true)
    launcher = "/Applications/Sample Game.app/Contents/MacOS/Sample Game"
    command = copy.instance_variable_get(:@command)

    assert_equal [launcher, "--level", "2"], copy.fused_command(launcher)
    assert_equal ["C:/Games/Sample Game/Sample Game.exe", "--level", "2"],
      copy.fused_command("C:/Games/Sample Game/Sample Game.exe")
    assert_equal [RbConfig.ruby, LOTA, "--level", "2"], command.values_at(0, -3, -2, -1)
    assert_equal command, copy.fused_command(RbConfig.ruby)
    assert_equal command, copy.fused_command(""), "nothing to name the program by leaves Ruby's command"
  end

  def test_a_program_ruby_cannot_start_again_is_not_remembered
    refute_predicate remembered("-e", []), :restartable?
  end

  def test_asking_to_restart_with_what_cannot_cross_raises_before_the_game_ends
    assert_raises(TypeError) { Lota::Restart.request([Object.new]) }
  end
end
