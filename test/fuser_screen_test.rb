# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/fuser/screen"
require "rbconfig"

# The fuser's window makes each game dropped on it into an app in a
# process of its own, and shows what came of it. Here a Ruby script stands
# in for the fuser's program given --build, printing what it was given as
# Lota::Fuser.main prints, so each test starts a real process and reads
# what it printed.
class FuserScreenTest < Minitest::Test
  # Prints the archive's path as an app's, and what Fledge would say, and
  # exits with the status FUSER_STATUS names.
  WORKER = <<~RUBY
    warn "fledge build: copying"
    puts ARGV.last.sub(/\\.lota\\z/, "-x86_64-linux.tar.gz")
    exit Integer(ENV.fetch("FUSER_STATUS", "0"))
  RUBY

  def screen
    Lota::Fuser::Screen.new("/unused", command: [RbConfig.ruby, "-e", WORKER])
  end

  # Updates +screen+ until it is no longer making an app.
  def finish(screen)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    while screen.text.include?("Making ")
      flunk "the app was not made within 30 seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      screen.update
      sleep 0.01
    end
  end

  def test_the_screen_asks_for_a_game_in_one_file
    assert_equal Lota::Fuser::Screen::WAITING, screen.text
  end

  def test_a_dropped_game_is_made_into_an_app_whose_paths_it_shows
    screen = self.screen

    screen.drop("games/Sample Game.lota")
    assert_equal "Making Sample Game.lota into an app...", screen.text
    finish(screen)

    assert_equal "Made Sample Game.lota into an app:\nfledge build: copying\n#{File.expand_path('games/Sample Game-x86_64-linux.tar.gz')}",
      screen.text
  end

  def test_a_game_that_could_not_be_made_into_an_app_shows_why
    ENV["FUSER_STATUS"] = "1"
    screen = self.screen
    screen.drop("Sample Game.lota")
    finish(screen)

    assert_match(/\ACould not make Sample Game.lota into an app:\nfledge build: copying\n/, screen.text)
  ensure
    ENV.delete("FUSER_STATUS")
  end

  def test_games_dropped_while_another_is_made_are_made_after_it_in_turn
    screen = self.screen
    screen.drop("First.lota")
    screen.drop("Second.lota")
    screen.drop("Third.lota")

    assert_equal "Making First.lota into an app...\n\n2 more to make after it.", screen.text
    finish(screen)

    made = %w[First Second Third].map do |name|
      "Made #{name}.lota into an app:\nfledge build: copying\n#{File.expand_path("#{name}-x86_64-linux.tar.gz")}"
    end
    assert_equal made.join("\n\n"), screen.text
  end

  def test_a_game_dropped_once_the_window_is_idle_again_starts_afresh
    screen = self.screen
    screen.drop("First.lota")
    finish(screen)
    screen.drop("Second.lota")

    assert_equal "Making Second.lota into an app...", screen.text
    finish(screen)

    assert_match(/\AMade Second.lota/, screen.text)
  end
end
