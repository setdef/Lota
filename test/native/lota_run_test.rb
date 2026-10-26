# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require "rbconfig"
require "tmpdir"

# lota run, end to end: each test runs the lota executable on a game
# folder in a Ruby of its own, which opens a real window, as a player's
# would. Under rake test:native that Ruby loads the sanitized extension,
# as this one did, and inherits the sanitizers (strip_env=0,
# tasks/sanitized_build.rb).
class LotaRunTest < Minitest::Test
  include NativeHelper

  GAMES = File.join(ROOT, "test/games")

  # Runs <tt>lota run</tt> with +arguments+ and returns its output and
  # Process::Status. -w makes any warning part of the output.
  def lota_run(*)
    native = File.dirname(File.dirname(loaded("lota/native")))
    load_path = [native, File.join(ROOT, "lib")].uniq.join(File::PATH_SEPARATOR)
    capture2e({}, RbConfig.ruby, "-w", "-I#{load_path}", File.join(ROOT, "exe/lota"), "run", *)
  end

  def game(name)
    File.join(GAMES, name)
  end

  # conf.rb sizes and titles the window; main.rb reads them back in load,
  # then each callback prints its name. The first draw asks to quit, the
  # quit callback refuses once, and the second request ends the game with
  # the status given on the command line.
  def test_callbacks_run_in_loves_order_and_the_game_exits_with_its_status
    output, status = lota_run(game("order"), "7")

    assert_equal <<~OUTPUT, output
      conf 800x600
      main
      load ["7"] ["#{game('order')}", "7"]
      window 320x200 Order
      update Float
      draw
      quit 1
      update Float
      draw
      quit 2
    OUTPUT
    assert_equal 7, status.exitstatus
  end

  def test_a_game_that_quits_without_a_status_exits_cleanly
    output, status = lota_run(game("order"))

    assert_predicate status, :success?, output
    assert_includes output, %(load [] ["#{game('order')}"])
    assert output.end_with?("quit 2\n"), output
  end

  def test_a_game_runs_from_the_current_directory
    reader, writer = IO.pipe
    native = File.dirname(File.dirname(loaded("lota/native")))
    pid = Dir.chdir(game("order")) do
      LotaNativeTest.spawn([
        RbConfig.ruby,
        "-w",
        "-I#{native}#{File::PATH_SEPARATOR}#{File.join(ROOT, 'lib')}",
        File.join(ROOT, "exe/lota"),
        "run",
], writer.fileno, ENV.map { |name, value| "#{name}=#{value}" })
    end
    writer.close
    output = reader.read
    status = Process.wait2(pid).last

    assert_predicate status, :success?, output
    assert_includes output, "load [] []"
    assert_includes output, "window 320x200 Order"
  ensure
    reader&.close
  end

  # A game can replace Lota.run, and Lota drains its release queue after
  # every frame of it.
  def test_a_game_replaces_the_loop_and_lota_drains_the_release_queue_each_frame
    output, status = lota_run(game("custom_run"))

    assert_equal "run\nframe 1\nqueued some\nframe 2\nqueued none\nframe 3\n", output
    assert_equal 5, status.exitstatus
  end

  # The walking skeleton's acceptance test, through the loop: Lövetest's
  # love.graphics, love.keyboard, love.mouse, and love.math tests, run from
  # the update callback of a game whose conf.rb translates Lövetest's
  # conf.lua. On a GitHub Actions runner, Lövetest's arc test compares none
  # of its three 32 by 32 images, and asserts once instead
  # (test/lovetest/tests/graphics.rb, test_arc).
  def test_lovetest_passes_when_run_by_lota_run
    output, status = lota_run(File.join(ROOT, "test/lovetest/game"))
    assertions = (ENV["GITHUB_ACTIONS"] == "true") ? 7968 - (3 * 32 * 32) + 1 : 7968

    assert_predicate status, :success?, output
    assert_match(/^love\.conf$/, output)
    assert_match(/^19 runs, #{assertions} assertions, 0 failures, 0 errors, 0 skips$/, output)
  end

  def test_an_error_in_a_callback_ends_the_program_with_a_backtrace
    in_game("main.rb" => "def Lota.update(dt) = raise('broken update')\n") do |directory|
      output, status = lota_run(directory)

      refute_predicate status, :success?
      assert_includes output, "main.rb:1:in 'Lota.update': broken update (RuntimeError)"
    end
  end

  # LÖVE raises conf.lua's error only once the modules are open; the window
  # opens after it (boot.lua:394-396), so the error ends the program.
  def test_an_error_in_conf_ends_the_program_with_a_backtrace
    in_game("conf.rb" => "def Lota.conf(t) = raise('broken conf')\n", "main.rb" => "puts 'main loaded'\n") do |directory|
      output, status = lota_run(directory)

      refute_predicate status, :success?
      assert_includes output, "conf.rb:1:in 'Lota.conf': broken conf (RuntimeError)"
      refute_includes output, "main loaded"
    end
  end

  def test_a_folder_without_main_or_conf_has_no_code_to_run
    in_game({}) do |directory|
      output, status = lota_run(directory)

      refute_predicate status, :success?
      assert_includes output, "No code to run at #{directory} (RuntimeError)\n" \
        "Your game might be packaged incorrectly.\nMake sure main.rb is at the top level of the zip or folder.\n"
    end
  end

  def test_a_game_whose_conf_turns_off_the_window_runs_without_one
    in_game("conf.rb" => "def Lota.conf(t) = (t.window = false)\n",
      "main.rb" => "def Lota.update(dt) = (puts(Lota::Graphics.active?); Lota::Event.quit)\n") do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "false\n", output
    end
  end

  # Numbers LÖVE's C++ holds as integers reach the game as Integers (ADR
  # 001, rule 14): opening the window and changing its mode each resize
  # it, with the graphics module's int width and height
  # (vendor/love/src/modules/event/sdl/Event.cpp:811-835).
  def test_a_resize_reaches_the_game_with_integers
    in_game("main.rb" => <<~RUBY) do |directory|
      $stdout.sync = true
      def Lota.load = Lota::Window.set_mode(400, 300)
      def Lota.resize(width, height) = puts("resize \#{width.inspect} \#{height.inspect}")
      def Lota.update(dt)
        @frames = (@frames || 0) + 1
        Lota::Event.quit if @frames == 30
      end
    RUBY
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_includes output, "resize 400 300\n"
    end
  end

  # Lua passes nil for parameters its caller left out (ADR 003, section
  # 3); update receives one argument and draw none. Lua has no defaults,
  # so draw's is the game's own and stays.
  def test_a_required_parameter_love_does_not_pass_receives_nil
    in_game("main.rb" => <<~RUBY) do |directory|
      def Lota.update(dt, extra) = (@update = [dt.class, extra])
      def Lota.draw(frame = 1)
        puts [*@update, frame].inspect
        Lota::Event.quit
      end
    RUBY
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[Float, nil, 1]\n", output
    end
  end

  # A module the settings turn off is nil through its accessor, as
  # love.timer is nil in LÖVE, while its constant stays defined (ADR 003,
  # section 6).
  def test_a_module_the_settings_turn_off_is_nil_through_its_accessor
    in_game("conf.rb" => "def Lota.conf(t) = (t.modules.timer = false; t.modules.keyboard = false)\n",
      "main.rb" => <<~RUBY) do |directory|
        def Lota.update(dt)
          p [lota.timer, lota.keyboard, Lota::Timer, lota.event, lota.graphics, dt]
          Lota::Event.quit
        end
      RUBY
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[nil, nil, Lota::Timer, Lota::Event, Lota::Graphics, 0]\n", output
    end
  end

  # LÖVE's require searches the game's folder, from conf.lua as from
  # main.lua, and LÖVE leaves the working directory alone (ADR 003,
  # section 6).
  def test_a_game_requires_files_from_its_folder_and_keeps_the_working_directory
    in_game("conf.rb" => "require 'title'\ndef Lota.conf(t) = (t.window.title = TITLE)\n",
      "title.rb" => "TITLE = 'Required'\n",
      "player.rb" => "module Player\n  def self.name = 'player'\nend\n",
      "main.rb" => <<~RUBY) do |directory|
        require "player"
        def Lota.load
          puts Player.name, Lota::Window.title, Dir.pwd
          Lota::Event.quit
        end
      RUBY
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "player\nRequired\n#{Dir.pwd}\n", output
    end
  end

  # boot.lua opens love.mouse and love.math (boot.lua:347-372), and so
  # does lota run, unless the settings turn them off.
  def test_the_mouse_and_math_modules_are_open_unless_turned_off
    in_game("main.rb" => "def Lota.load = (p [lota.mouse, lota.math]; Lota::Event.quit)\n") do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[Lota::Mouse, Lota::Math]\n", output
    end
    in_game("conf.rb" => "def Lota.conf(t) = (t.modules.mouse = false; t.modules.math = false)\n",
      "main.rb" => "def Lota.load = (p [lota.mouse, lota.math]; Lota::Event.quit)\n") do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[nil, nil]\n", output
    end
  end

  # Writes a game folder of +files+ (name to source) and yields its path.
  private def in_game(files)
    Dir.mktmpdir("lota-run-test") do |directory|
      files.each { |name, source| File.write(File.join(directory, name), source) }
      yield directory
    end
  end
end
