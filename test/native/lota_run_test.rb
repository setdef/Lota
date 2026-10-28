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

  # Quits a game's error screen once it is up (quit_on_error.rb).
  QUIT_ON_ERROR = File.expand_path("quit_on_error.rb", __dir__)

  # Presses Return on each dialog the game shows (press_return_on_dialogs.rb).
  PRESS_RETURN = File.expand_path("press_return_on_dialogs.rb", __dir__)

  # Gives the window focus for Lövetest's setGrabbed test (focus_for_grab.rb).
  FOCUS_FOR_GRAB = File.expand_path("focus_for_grab.rb", __dir__)

  # boot.lua's warning for a game made for a version the engine is not
  # compatible with (boot.lua:381-384), for t.version +version+.
  def self.version_warning(version)
    "This game indicates it was made for version '#{version}' of LOVE.\n" \
      "It may not be compatible with the running version (#{Lota::Native::VERSION}).\n"
  end

  # Runs <tt>lota run</tt> with +arguments+ and returns its output and
  # Process::Status. -w makes any warning part of the output. +preload+
  # names a file Ruby loads first, as ruby -r does, which may require
  # lota_native_test, last on the load path. +environment+ changes the
  # run's environment from this process's.
  def lota_run(*, preload: nil, environment: {})
    native = File.dirname(File.dirname(loaded("lota/native")))
    native_test = File.dirname(loaded("lota_native_test"))
    load_path = [native, File.join(ROOT, "lib"), native_test].uniq.join(File::PATH_SEPARATOR)
    capture2e(environment, RbConfig.ruby, "-w", "-I#{load_path}", *(preload && "-r#{preload}"), File.join(ROOT, "exe/lota"),
      "run", *)
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
  # love.graphics (its Quad and SpriteBatch tests among them),
  # love.audio, love.sound, love.keyboard, love.mouse, love.math, love.event, love.system,
  # love.window, love.filesystem, and love.physics tests, run from
  # the update callback of a game whose conf.rb translates Lövetest's
  # conf.lua. On a GitHub Actions runner, Lövetest's arc test compares none
  # of its three 32 by 32 images, and asserts once instead
  # (test/lovetest/tests/graphics.rb, test_arc).
  def test_lovetest_passes_when_run_by_lota_run
    output, status = lota_run(File.join(ROOT, "test/lovetest/game"), preload: FOCUS_FOR_GRAB)
    assertions = (ENV["GITHUB_ACTIONS"] == "true") ? 30263 - (3 * 32 * 32) + 1 : 30263

    assert_predicate status, :success?, output
    assert_match(/^love\.conf$/, output)
    assert_match(/^99 runs, #{assertions} assertions, 0 failures, 0 errors, 0 skips$/, output)
  end

  # An error in a callback shows LÖVE's error screen, after printing the
  # error and its backtrace (callbacks.lua:221-224), and the screen ends
  # the program with 1 when the player quits (lines 319-321).
  def test_an_error_in_a_callback_shows_the_error_screen_and_prints_a_backtrace
    in_game("main.rb" => "def Lota.update(dt) = raise('broken update')\n") do |directory|
      output, status = lota_run(directory, preload: QUIT_ON_ERROR)

      assert_equal 1, status.exitstatus, output
      assert_includes output, "Error: #{directory}/main.rb:1:in 'Lota.update': broken update (RuntimeError)\n" \
        "stack traceback:\n\t#{directory}/main.rb:1:in 'Lota.update'\n"
      assert output.end_with?("error screen shown\n"), output
    end
  end

  # LÖVE raises conf.lua's error only once the modules are open (boot.lua:
  # 394-396), and its error screen opens the window the game did not get
  # to (callbacks.lua:230-239).
  def test_an_error_in_conf_shows_the_error_screen
    in_game("conf.rb" => "def Lota.conf(t) = raise('broken conf')\n", "main.rb" => "puts 'main loaded'\n") do |directory|
      output, status = lota_run(directory, preload: QUIT_ON_ERROR)

      assert_equal 1, status.exitstatus, output
      assert_includes output, "conf.rb:1:in 'Lota.conf': broken conf (RuntimeError)"
      assert_includes output, "error screen shown"
      refute_includes output, "main loaded"
    end
  end

  def test_a_folder_without_main_or_conf_has_no_code_to_run
    in_game({}) do |directory|
      output, status = lota_run(directory, preload: QUIT_ON_ERROR)

      assert_equal 1, status.exitstatus, output
      assert_includes output, "No code to run at #{directory} (RuntimeError)\n" \
        "Your game might be packaged incorrectly.\nMake sure main.rb is at the top level of the zip or folder.\n"
    end
  end

  # A game's Lota.errorhandler replaces Lota's, as love.errorhandler does
  # (boot.lua:476): it receives what the game raised, and the frame it
  # returns runs until it returns the exit status (boot.lua:515-516).
  def test_a_games_error_handler_replaces_loves_and_its_frame_gives_the_status
    in_game("main.rb" => <<~RUBY) do |directory|
      def Lota.update(dt) = raise(ArgumentError, "broken")
      def Lota.errorhandler(error)
        puts "handled \#{error.class} \#{error.message}"
        frames = 0
        -> { (frames += 1) == 3 ? 7 : nil }
      end
    RUBY
      output, status = lota_run(directory)

      assert_equal 7, status.exitstatus, output
      assert_equal "handled ArgumentError broken\n", output
    end
  end

  # A handler that returns no frame ends the program with 1 (boot.lua:520).
  def test_an_error_handler_that_returns_no_frame_ends_the_program_with_1
    in_game("main.rb" => "def Lota.load = raise('broken')\ndef Lota.errorhandler(error) = nil\n") do |directory|
      output, status = lota_run(directory)

      assert_equal 1, status.exitstatus, output
      assert_empty output
    end
  end

  # An error in the error handler is printed by error_printer instead, and
  # the program ends with 1 (boot.lua:475-481 and 520).
  def test_an_error_in_the_error_handler_is_printed_and_ends_the_program
    in_game("main.rb" => "def Lota.load = raise('broken')\ndef Lota.errorhandler(error) = raise('worse')\n") do |directory|
      output, status = lota_run(directory)

      assert_equal 1, status.exitstatus, output
      assert_match(%r{\AError: #{Regexp.escape(directory)}/main.rb:2:in 'Lota.errorhandler': worse \(RuntimeError\)\n},
        output)
      refute_includes output, "broken"
    end
  end

  # LÖVE 12 keeps love.errhand only as another name for its own handler,
  # and calls love.errorhandler while there is one (boot.lua:476 and
  # callbacks.lua:351-352), so a game's errhand alone changes nothing.
  def test_a_games_errhand_alone_does_not_replace_the_error_handler
    in_game("main.rb" => "def Lota.load = raise('broken')\ndef Lota.errhand(error) = puts('errhand')\n") do |directory|
      output, status = lota_run(directory, preload: QUIT_ON_ERROR)

      assert_equal 1, status.exitstatus, output
      assert_includes output, "error screen shown"
      refute_includes output, "errhand\n"
    end
  end

  # A game that removes Lota.errorhandler gets its errhand, as boot.lua
  # falls back to love.errhand (line 476).
  def test_without_an_error_handler_a_games_errhand_handles_errors
    in_game("main.rb" => <<~RUBY) do |directory|
      Lota.singleton_class.undef_method(:errorhandler)
      def Lota.load = raise("broken")
      def Lota.errhand(error) = (puts("errhand \#{error.message}"); -> { 5 })
    RUBY
      output, status = lota_run(directory)

      assert_equal 5, status.exitstatus, output
      assert_equal "errhand broken\n", output
    end
  end

  # Without the window module the handler only prints (callbacks.lua:
  # 226-228), and the program ends with 1.
  def test_without_the_window_module_an_error_is_printed_and_ends_the_program
    in_game("conf.rb" => "def Lota.conf(t) = (t.modules.window = false)\n",
      "main.rb" => "def Lota.load = raise('broken')\n") do |directory|
      output, status = lota_run(directory, preload: QUIT_ON_ERROR)

      assert_equal 1, status.exitstatus, output
      assert_includes output, "main.rb:1:in 'Lota.load': broken (RuntimeError)"
      assert_includes output, "error screen not shown"
    end
  end

  # boot.lua opens love.system before conf.lua runs, whatever the settings
  # say (boot.lua:48-49), and love.font with the other modules unless the
  # settings turn it off (lines 347-372).
  def test_the_system_module_is_always_open_and_the_font_module_unless_turned_off
    in_game("conf.rb" => "def Lota.conf(t) = (p lota.system; t.modules.system = false; t.modules.font = false)\n",
      "main.rb" => "def Lota.load = (p [lota.font, lota.system]; Lota::Event.quit)\n") do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "Lota::System\n[nil, Lota::System]\n", output
    end
    in_game("main.rb" => "def Lota.load = (p [lota.font, lota.system]; Lota::Event.quit)\n") do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[Lota::Font, Lota::System]\n", output
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
    in_game("conf.rb" => "def Lota.conf(t) = (t.modules.timer = false; t.modules.keyboard = false; " \
              "t.modules.data = false)\n", "main.rb" => <<~RUBY) do |directory|
                def Lota.update(dt)
                  p [lota.timer, lota.keyboard, lota.data, Lota::Timer, lota.event, lota.graphics, dt]
                  Lota::Event.quit
                end
              RUBY
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[nil, nil, nil, Lota::Timer, Lota::Event, Lota::Graphics, 0]\n", output
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

  # boot.lua makes the game's folder the source LÖVE's filesystem reads
  # (boot.lua:123), so a file the game names is found in its folder,
  # wherever lota run was started, and the mouse and math modules are open,
  # as boot.lua opens love.mouse and love.math (boot.lua:347-372).
  def test_a_game_reads_the_files_it_names_from_its_folder
    logo = File.binread(File.join(ROOT, "vendor/love/testing/resources/love.png"))
    in_game("logo.png" => logo, "main.rb" => <<~RUBY) do |directory|
      def Lota.load
        image = Lota::Image::ImageData.new("logo.png")
        p [image.width, image.height, lota.mouse, lota.math]
        Lota::Event.quit
      end
    RUBY
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[64, 64, Lota::Mouse, Lota::Math]\n", output
      refute_equal File.realpath(directory), File.realpath(Dir.pwd)
    end
  end

  # boot.lua checks t.version once the modules are open (boot.lua:378-393):
  # a version love.isVersionCompatible refuses is printed, and, with the
  # window module open, shown in a dialog before the window opens, which
  # waits until the player presses Return.
  def test_a_game_made_for_another_version_shows_loves_warning_in_a_dialog
    in_game("conf.rb" => "def Lota.conf(t) = (t.version = '11.3')\n",
      "main.rb" => "def Lota.load = (p Lota::Window.open?; Lota::Event.quit)\n") do |directory|
      output, status = lota_run(directory, preload: PRESS_RETURN)

      assert_predicate status, :success?, output
      assert_equal "#{self.class.version_warning('11.3')}true\ndialogs 1\n", output
    end
  end

  # love.isVersionCompatible appends ".0" to a version with fewer than two
  # dots, once, and compares it with each version the engine is compatible
  # with, written the same way (love.cpp:309-352), so "12.0" and "12.0.0"
  # pass and "12" does not. boot.lua first turns t.version into a string
  # with Lua's tostring, which writes nil as "nil" and 12.0 as "12". Without
  # the window module the warning is only printed, and no dialog shows.
  def test_the_version_is_compared_as_love_compares_it
    { "'12.0'" => nil, "'12.0.0'" => nil, "'12'" => "12", "12.0" => "12", "nil" => "nil" }.each do |version, warned|
      in_game("conf.rb" => "def Lota.conf(t) = (t.version = #{version}; t.modules.window = false)\n",
        "main.rb" => "def Lota.load = Lota::Event.quit\n") do |directory|
        output, status = lota_run(directory, preload: PRESS_RETURN)

        assert_predicate status, :success?, output
        assert_equal "#{warned && self.class.version_warning(warned)}dialogs 0\n", output, version
      end
    end
  end

  # Where a game's saves go: the system's application data folder under
  # the tests' home of their own (test/test_helper.rb), then Lota's folder
  # unless the game is fused, then its identity (ADR 003, section 8;
  # physfs/Filesystem.cpp:608-616).
  def self.save_directory(identity, fused: false)
    support = File.join(File.realpath(ENV.fetch("CFFIXED_USER_HOME")), "Library/Application Support")
    File.join(*[support, ("Lota" unless fused), identity].compact)
  end

  # boot.lua names the save directory after the game's folder, without
  # leading dots or its last extension and with its other dots made
  # underscores (boot.lua:136-150), and then after t.identity, once
  # conf.lua has run (line 442).
  def test_a_game_saves_under_its_folders_name_or_its_identity
    in_game("main.rb" => "def Lota.load = (p [Lota::Filesystem.identity, Lota::Filesystem.save_directory, " \
              "Lota::Filesystem.fused?]; Lota::Event.quit)\n") do |directory|
      game = File.join(directory, ".my.game.v2")
      Dir.mkdir(game)
      File.write(File.join(game, "main.rb"), File.read(File.join(directory, "main.rb")))
      output, status = lota_run(game)

      assert_predicate status, :success?, output
      assert_equal "#{['my_game', self.class.save_directory('my_game'), false].inspect}\n", output

      File.write(File.join(game, "conf.rb"), "def Lota.conf(t) = (t.identity = 'kleleatoms')\n")
      output, status = lota_run(game)

      assert_predicate status, :success?, output
      assert_equal "#{['kleleatoms', self.class.save_directory('kleleatoms'), false].inspect}\n", output
    end
  end

  # A game shipped fused into an application of its own saves where LÖVE's
  # fused game saves, without Lota's folder (ADR 003, section 8), which is
  # how ADR 002's launcher is to start one.
  def test_a_fused_game_saves_where_loves_fused_game_saves
    in_game("conf.rb" => "def Lota.conf(t) = (t.identity = 'kleleatoms')\n",
      "main.rb" => "def Lota.load = (p [Lota::Filesystem.save_directory, Lota::Filesystem.fused?]; " \
        "Lota::Event.quit)\n") do |directory|
      native = File.dirname(File.dirname(loaded("lota/native")))
      output, status = capture2e({}, RbConfig.ruby, "-w", "-I#{native}#{File::PATH_SEPARATOR}#{File.join(ROOT, 'lib')}",
        "-rlota", "-e", "exit Lota::Boot.new(ARGV.first, fused: true).call", directory)

      assert_predicate status, :success?, output
      assert_equal "#{[self.class.save_directory('kleleatoms', fused: true), true].inspect}\n", output
    end
  end

  # boot.lua requires love.sound and love.audio unless the settings turn
  # them off (boot.lua:347-372), and love.audio opens LÖVE's null audio
  # module when OpenAL cannot open a device (wrap_Audio.cpp:678-708); the
  # tests' OpenAL Soft plays into a wave file (test/alsoft.conf).
  def test_the_sound_and_audio_modules_are_open_unless_turned_off
    in_game("main.rb" => "def Lota.load = (p [lota.sound, lota.audio]; Lota::Event.quit)\n") do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[Lota::Sound, Lota::Audio]\n", output
    end
    in_game("conf.rb" => "def Lota.conf(t) = (t.modules.sound = false; t.modules.audio = false)\n",
      "main.rb" => "def Lota.load = (p [lota.sound, lota.audio]; Lota::Event.quit)\n") do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[nil, nil]\n", output
    end
  end

  # LÖVE closes its modules when it closes its Lua state at exit
  # (love.cpp:291), and so the audio device, and Lota closes the audio
  # module at exit too. OpenAL Soft's wave writer, which the tests play
  # into (test/alsoft.conf), writes the file's size into its header when
  # the device closes, and leaves it unwritten when it never does.
  def test_the_audio_device_closes_at_exit
    Dir.mktmpdir("lota-run-test-home") do |home|
      in_game("main.rb" => "def Lota.load = Lota::Event.quit\n") do |directory|
        output, status = lota_run(directory, environment: { "CFFIXED_USER_HOME" => home })

        assert_predicate status, :success?, output
        wave = File.binread(File.join(home, "alsoft.wav"))
        assert_equal "RIFF", wave[0, 4]
        assert_equal wave.bytesize - 8, wave[4, 4].unpack1("V")
      end
    end
  end

  # A static Source decodes its file when it is made, and a streaming one
  # as it plays; either plays from a file in the game's folder.
  def test_a_game_plays_sounds_from_its_folder
    click = File.binread(File.join(ROOT, "vendor/love/testing/resources/click.ogg"))
    in_game("click.ogg" => click, "main.rb" => <<~RUBY) do |directory|
      def Lota.load
        sources = %i[static stream].map { |type| Lota::Audio::Source.new("click.ogg", type) }
        p sources.map { |source| [source.channel_count, Lota::Audio.play(source), source.playing?] }
        Lota::Audio.stop
        p [sources.map(&:playing?), Lota::Audio.active_source_count]
        Lota::Event.quit
      end
    RUBY
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[[2, true, true], [2, true, true]]\n[[false, false], 0]\n", output
    end
  end

  # Writes a game folder of +files+ (name to source) and yields its path.
  private def in_game(files)
    Dir.mktmpdir("lota-run-test") do |directory|
      files.each { |name, source| File.binwrite(File.join(directory, name), source) }
      yield directory
    end
  end
end
