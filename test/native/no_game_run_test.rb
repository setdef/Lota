# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require "lota/cli"
require "rbconfig"
require "tmpdir"

# Lota started with no game shows its no-game screen, as LÖVE does
# (boot.lua:156-170), and a game dropped on it starts in its place: the
# screen restarts with the game's path (nogame.lua:3289-3299), which the
# new run puts first, as the game's (boot.lua:51-60). Each test runs
# test/native/no_game_start.rb in a Ruby of its own, which drops
# test/games/restart on the screen; that game logs what it was started
# with and quits. The screen opens a window, which stays in the
# background (test/test_helper.rb); it takes neither the focus nor the
# pointer. An error shows the error screen and quits
# (test/native/quit_on_error.rb), and a run that has not ended after
# TIMEOUT seconds is stopped.
class NoGameRunTest < Minitest::Test
  include NativeHelper

  GAME = File.join(ROOT, "test/games/restart")

  # What starts Lota with no game, and drops GAME on its screen.
  START = File.join(ROOT, "test/native/no_game_start.rb")

  def setup
    super
    @directory = Dir.mktmpdir("lota-no-game-test")
    @log = File.join(@directory, "log")
  end

  def teardown
    FileUtils.remove_entry(@directory)
    super
  end

  # Runs test/native/no_game_start.rb with LOTA_NO_GAME_DROP set to
  # +drop+, and returns its output and Process::Status. The load path
  # travels in RUBYOPT, which the restarted process inherits.
  def start_with_no_game(drop)
    native = File.dirname(File.dirname(loaded("lota/native")))
    load_path = [native, File.join(ROOT, "lib")].uniq.map { |path| "-I#{path}" }.join(" ")
    environment = {
      "RUBYOPT" => load_path,
      "LOTA_RESTART_LOG" => @log,
      "LOTA_RESTART_ARGUMENT" => "never",
      "LOTA_NO_GAME_GAME" => GAME,
      "LOTA_NO_GAME_DROP" => drop,
    }
    variables = ENV.to_h.merge(environment).map { |name, value| "#{name}=#{value}" }
    command = [RbConfig.ruby, "-w", "-r#{File.join(ROOT, 'test/native/quit_on_error.rb')}", START]
    reader, writer = IO.pipe
    begin
      pid = NativeHelper.spawn(command, writer, variables)
    ensure
      writer.close
    end
    [read_with_timeout(reader, pid, TIMEOUT), Process.wait2(pid).last]
  ensure
    reader&.close
  end

  # How long a run may take: a screen the drop did not restart would show
  # until it was closed.
  TIMEOUT = 60

  # The one line the game logged as it loaded: [pid, arguments, restart].
  def logged_load(output)
    lines = File.exist?(@log) ? File.readlines(@log, chomp: true).grep(/\Aload /) : []

    assert_equal 1, lines.size, output
    lines.first.match(/pid=(\d+) arguments=(.*) restart=(.*) variable=/).captures
  end

  def test_a_folder_dropped_on_the_screen_starts_as_the_game
    output, status = start_with_no_game("directory")

    assert_predicate status, :success?, output
    assert output.start_with?(Lota::CLI.usage), output
    _, arguments, restart = logged_load(output)

    assert_equal "[]", arguments
    assert_equal({ "_noGameRestartInfo" => { "gamepath" => GAME } }.inspect, restart)
  end

  def test_a_file_dropped_on_the_screen_starts_as_the_game
    output, status = start_with_no_game("file")

    assert_predicate status, :success?, output
    _, arguments, restart = logged_load(output)

    assert_equal "[]", arguments
    assert_equal({ "_noGameRestartInfo" => { "gamepath" => GAME } }.inspect, restart)
  end
end
