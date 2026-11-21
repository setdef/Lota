# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/arg"

# How the lota program reads its arguments, as arg.lua's
# love.arg.parseOptions and parseGameArguments read LÖVE's
# (vendor/love/src/modules/love/arg.lua).
class ArgTest < Minitest::Test
  def parse(*arguments, game_set: false)
    Lota::Arg.parse(arguments, game_set:)
  end

  def test_the_first_argument_that_is_no_option_is_the_game_and_the_rest_are_the_games
    line = parse("games/pong", "level2", "--hard")

    assert_equal "games/pong", line.game
    assert_equal %w[level2 --hard], line.game_arguments
  end

  def test_with_no_arguments_there_is_no_game
    line = parse

    assert_nil line.game
    assert_empty line.game_arguments
  end

  # parseOptions looks for options in every argument, after the game's
  # path too, and each is taken out of the game's arguments.
  def test_options_are_found_anywhere_and_left_out_of_the_games_arguments
    line = parse("--fused", "games/pong", "level2", "--renderers", "opengl,vulkan", "--console")

    assert_equal "games/pong", line.game
    assert_equal %w[level2], line.game_arguments
    assert line.set?("fused")
    assert line.set?("console")
    assert_equal "opengl,vulkan", line.value("renderers")
    refute line.set?("excluderenderers")
    assert_nil line.value("excluderenderers")
  end

  def test_game_names_the_game_wherever_it_is
    line = parse("level2", "--game", "games/pong")

    assert_equal "games/pong", line.game
    assert_equal %w[level2], line.game_arguments
  end

  # An option is read once: given again, it is an argument like any other.
  def test_an_option_given_twice_is_an_argument_the_second_time
    line = parse("games/pong", "--fused", "--fused", "--excluderenderers", "vulkan", "--excluderenderers", "metal")

    assert_equal "vulkan", line.value("excluderenderers")
    assert_equal %w[--fused --excluderenderers metal], line.game_arguments
  end

  # An argument that only looks like an option, one parseOptions does not
  # know, is the game when it comes first, as LÖVE takes it.
  def test_an_unknown_option_is_an_argument
    line = parse("--level", "games/pong")

    assert_equal "--level", line.game
    assert_equal %w[games/pong], line.game_arguments
  end

  # "--" ends the options: the argument after it is the game, unless one
  # came before, and everything after it is the game's.
  def test_two_dashes_end_the_options
    line = parse("--", "--fused", "--console")

    assert_equal "--fused", line.game
    assert_equal %w[--console], line.game_arguments
    refute line.set?("fused")

    line = parse("games/pong", "--", "--fused")

    assert_equal "games/pong", line.game
    assert_equal %w[--fused], line.game_arguments
  end

  # A fused game, whose program carries it, takes no game from its
  # arguments, and --game is then an argument like any other (boot.lua:
  # 74-81).
  def test_with_the_game_set_no_argument_is_the_game
    line = parse("level2", "--game", "other", "--fused", game_set: true)

    assert_nil line.game
    assert_equal %w[level2 --game other], line.game_arguments
    assert line.set?("fused")
  end

  # An option whose value is missing, at the end, is set with none.
  def test_an_option_at_the_end_has_no_value
    line = parse("games/pong", "--renderers")

    assert line.set?("renderers")
    assert_nil line.value("renderers")
    assert_empty line.game_arguments
  end

  def test_the_options_are_loves
    assert_equal({ "console" => 0, "fused" => 0, "game" => 1, "renderers" => 1, "excluderenderers" => 1 },
      Lota::Arg::OPTIONS)
  end
end
