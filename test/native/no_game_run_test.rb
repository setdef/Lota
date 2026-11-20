# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../zip_writer"
require "lota/cli"
require "rbconfig"
require "tmpdir"

# Lota started with no game shows its no-game screen, as LÖVE does
# (boot.lua:156-170), and a game dropped on it starts in its place: the
# screen restarts with the game's path (nogame.lua:3289-3299), which the
# new run puts first, as the game's (boot.lua:51-60). Each test runs
# test/native/no_game_start.rb in a Ruby of its own, which drops a game
# on the screen: test/games/restart, which logs what it was started with
# and quits, as a folder or as a .lota. The screen opens a window, which
# stays in the background (test/test_helper.rb); it takes neither the
# focus nor the pointer. An error shows the error screen and quits
# (test/native/quit_on_error.rb, which the start loads), and a run that
# has not ended after TIMEOUT seconds is stopped.
class NoGameRunTest < Minitest::Test
  include NativeHelper

  GAME = File.join(ROOT, "test/games/restart")

  # What starts Lota with no game, and drops a game on its screen.
  START = File.join(ROOT, "test/native/no_game_start.rb")

  # How long a run may take: a screen the drop did not restart would show
  # until it was closed.
  TIMEOUT = 60

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
  # +drop+ and LOTA_NO_GAME_GAME to +game+, and returns its output and
  # Process::Status. The load path travels in RUBYOPT, which the
  # restarted process inherits.
  def start_with_no_game(drop, game = GAME, environment = {})
    native = File.dirname(File.dirname(loaded("lota/native")))
    load_path = [native, File.join(ROOT, "lib")].uniq.map { |path| "-I#{path}" }.join(" ")
    environment = {
      "RUBYOPT" => load_path,
      "LOTA_RESTART_LOG" => @log,
      "LOTA_RESTART_ARGUMENT" => "never",
      "LOTA_NO_GAME_GAME" => game,
      "LOTA_NO_GAME_DROP" => drop,
    }.merge(environment)
    variables = ENV.to_h.merge(environment).map { |name, value| "#{name}=#{value}" }
    command = [RbConfig.ruby, "-w", START]
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

  # The lines the game logged as it loaded, each as [pid, arguments,
  # restart].
  def logged_loads
    lines = File.exist?(@log) ? File.readlines(@log, chomp: true).grep(/\Aload /) : []
    lines.map { |line| line.match(/pid=(\d+) arguments=(.*) restart=(.*) variable=/).captures }
  end

  # How many processes ran test/native/no_game_start.rb.
  def starts
    File.exist?(@log) ? File.readlines(@log).grep(/\Astart /).size : 0
  end

  def test_a_folder_dropped_on_the_screen_starts_as_the_game
    output, status = start_with_no_game("directory")

    assert_predicate status, :success?, output
    assert output.start_with?(Lota::CLI.usage), output
    assert_equal 2, starts, "the screen restarts by exec, as Lota restarts by default"
    loads = logged_loads

    assert_equal 1, loads.size, output
    _, arguments, restart = loads.first

    assert_equal "[]", arguments
    assert_equal({ "_noGameRestartInfo" => { "gamepath" => GAME } }.inspect, restart)
  end

  # A game in one file, the .lota LÖVE's .love is to it, dropped as a
  # file, starts from what Lota::Archive unpacks.
  def test_a_lota_dropped_on_the_screen_starts_as_the_game
    archive = File.join(@directory, "restart.lota")
    ZipWriter.write(archive, %w[main.rb conf.rb].to_h { |name| [name, File.binread(File.join(GAME, name))] })
    output, status = start_with_no_game("file", archive, cache_home)

    assert_predicate status, :success?, output
    loads = logged_loads

    assert_equal 1, loads.size, output
    _, arguments, restart = loads.first

    assert_equal "[]", arguments
    assert_equal({ "_noGameRestartInfo" => { "gamepath" => archive } }.inspect, restart)
  end

  # Under LOTA_IN_PROCESS_RESTART the dropped game starts in the same
  # process, as LÖVE's starts in its own (src/love.cpp, main).
  def test_a_dropped_game_starts_in_the_same_process_when_restarts_stay_in_it
    output, status = start_with_no_game("directory", GAME, "LOTA_IN_PROCESS_RESTART" => "always")

    assert_predicate status, :success?, output
    assert_equal 1, starts, output
    loads = logged_loads

    assert_equal 1, loads.size, output
    _, arguments, restart = loads.first

    assert_equal "[]", arguments
    assert_equal({ "_noGameRestartInfo" => { "gamepath" => GAME } }.inspect, restart)
  end

  # A dropped file that is no game is reported as LÖVE reports a path it
  # cannot load: the run it restarts into shows the error screen
  # (boot.lua:123-127 and 453-455).
  def test_a_dropped_file_that_is_no_game_shows_the_error_screen
    notes = File.join(@directory, "notes.txt")
    File.write(notes, "not a zip\n")
    output, status = start_with_no_game("file", notes)

    assert_equal 1, status.exitstatus, output
    assert_includes output, "Cannot load game at path '#{notes}'."
    assert output.end_with?("error screen shown\n"), output
    assert_empty logged_loads, output
  end

  def test_escape_quits_the_screen
    output, status = start_with_no_game("escape")

    assert_equal 0, status.exitstatus, output
    assert_empty logged_loads, output
  end

  # Where the archive unpacks: a cache folder in the test's own folder.
  private def cache_home
    home = File.join(@directory, "home")
    Dir.mkdir(home)
    variable = if TestHome::LINUX then "XDG_CACHE_HOME"
    elsif TestHome::WINDOWS then "LOCALAPPDATA"
    else "CFFIXED_USER_HOME"
    end
    { variable => home }
  end
end
