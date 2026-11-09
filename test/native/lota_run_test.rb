# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../lovetest/unseen_desktop"
require_relative "../lovetest/lovetest_skips"
require_relative "../lovetest/held_foreground"
require "json"
require "rbconfig"
require "tmpdir"
require_relative "../../tasks/package_check"
require_relative "../../tasks/lovetest_image"

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

  # Gives the window focus for Lövetest's setGrabbed and isOccluded tests
  # (focus_for_tests.rb).
  FOCUS_FOR_TESTS = File.expand_path("focus_for_tests.rb", __dir__)

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
    capture2e(environment, RbConfig.ruby, "-w", "-I#{run_load_path}", *(preload && "-r#{preload}"),
      File.join(ROOT, "exe/lota"), "run", *)
  end

  # The load path of a run: the extension this process loaded, Lota's
  # lib, and the test extension, last.
  def run_load_path
    native = File.dirname(File.dirname(loaded("lota/native")))
    native_test = File.dirname(loaded("lota_native_test"))
    [native, File.join(ROOT, "lib"), native_test].uniq.join(File::PATH_SEPARATOR)
  end

  def game(name)
    File.join(GAMES, name)
  end

  # What a run that presses Return on dialogs (PRESS_RETURN) needs loaded
  # first: on Linux, the library that answers them, from the build tree
  # this process loaded the test extension from (NativeHelper.dialogs).
  def answering_dialogs
    dialogs = NativeHelper.dialogs(File.dirname(loaded("lota_native_test")))
    dialogs.empty? ? {} : NativeHelper.preload(*dialogs)
  end

  # conf.rb sizes and titles the window; main.rb reads them back in load,
  # with whether text input is on, which LÖVE leaves off until a game asks
  # (Lota::Keyboard.text_input=), then each callback prints its name. The first draw asks to quit, the
  # quit callback refuses once, and the second request ends the game with
  # the status given on the command line.
  def test_callbacks_run_in_loves_order_and_the_game_exits_with_its_status
    output, status = lota_run(game("order"), "7")
    scale = reported_scale(output)
    units = (320 / scale).round
    units_high = (200 / scale).round

    assert_equal <<~OUTPUT, output
      conf 800x600
      main
      load ["7"] ["#{game('order')}", "7"]
      window #{units}x#{units_high} Order
      pixels 320x200 scale #{scale}
      text input false
      update Float
      draw
      quit 1
      update Float
      draw
      quit 2
    OUTPUT
    assert_equal 7, status.exitstatus
  end

  # The scale the order game reports for its 320x200-pixel window: 1.0 on a
  # display at 100%, and more on a display above it, where LÖVE's
  # usedpiscale makes a unit smaller than a pixel whatever highdpi says.
  def reported_scale(output)
    Float(output[/^pixels 320x200 scale (\S+)$/, 1] || flunk("no pixels line: #{output}"))
  end

  # test/games/fuse, the game the fuse workflow fuses and runs on every
  # platform, restarts once, then draws the screen Lövetest's
  # captureScreenshot test captures and saves a screenshot of it, which
  # must be Lövetest's expected image by Lövetest's rule. The load path
  # travels in RUBYOPT, which the restarted process inherits.
  def test_the_fuse_game_saves_the_screenshot_lovetest_expects
    load_path = run_load_path.split(File::PATH_SEPARATOR).map { |path| "-I#{path}" }.join(" ")
    output, status = capture2e({ "RUBYOPT" => load_path }, RbConfig.ruby, "-w", File.join(ROOT, "exe/lota"), "run",
      game("fuse"))

    assert_equal 3, status.exitstatus, output
    screenshot = output[/^screenshot: (.*)$/, 1]

    refute_nil screenshot, output
    expected = LovetestImage.read(File.join(ROOT, "vendor/love/testing/output/expected", LovetestImage::SCREENSHOT))

    assert_empty LovetestImage.differences(LovetestImage.read(screenshot), expected).first(5), output
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
      NativeHelper.spawn([
        RbConfig.ruby,
        "-w",
        "-I#{native}#{File::PATH_SEPARATOR}#{File.join(ROOT, 'lib')}",
        File.join(ROOT, "exe/lota"),
        "run",
], writer, ENV.map { |name, value| "#{name}=#{value}" })
    end
    writer.close
    output = reader.read
    status = Process.wait2(pid).last

    assert_predicate status, :success?, output
    assert_includes output, "load [] []"
    scale = reported_scale(output)

    assert_includes output, "window #{(320 / scale).round}x#{(200 / scale).round} Order"
    assert_includes output, "pixels 320x200 scale"
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

  # Lövetest, through lota run and the game loop: every test Lota
  # translates from it (test/lovetest/tests), run from the update callback
  # of a game whose conf.rb translates Lövetest's conf.lua, once each and
  # with none failing. The runs it expects are the test methods those
  # files define, so a file the game does not load, or a test it does not
  # run, is noticed, and a test that runs but asserts nothing fails, as
  # in Lövetest (Lovetest::TestMethod#after_teardown). How many assertions
  # the tests make is left to them: many depend on the machine, and
  # getPowerInfo's on its battery at the moment the game asks, which a
  # laptop on a charger it out-draws can change from one second to the
  # next (test/lovetest/tests/system.rb, test_get_power_info).
  #
  # Lövetest skips its discard, requestAttention, showMessageBox, openURL,
  # vibrate, pump, and wait tests everywhere, and so does Lota.
  def test_lovetest_passes_when_run_by_lota_run
    output, status = lota_run(File.join(ROOT, "test/lovetest/game"), preload: FOCUS_FOR_TESTS)
    runs = Dir[File.join(ROOT, "test/lovetest/tests/*.rb")].sum { |file| File.read(file).scan(/^\s*def test_\w+/).size }
    # Lövetest skips its window tests of fullscreen, maximizing, and
    # minimizing on a GitHub runner on Linux, where xvfb has no window
    # manager (test/lovetest/tests/window.rb), beside those it always
    # skips; LovetestSkips counts both from the tests.
    EngineHelper.open_window
    supported = Lota::Graphics.supported
    # Its ShaderStorageBuffer test skips where the renderer lacks GLSL 4.
    # Its isEnabled, getName, and getData sensor tests skip where the
    # machine has neither an accelerometer nor a gyroscope
    # (test/lovetest/tests/sensor.rb).
    sensors = %i[accelerometer gyroscope].count { |sensor_type| Lota::Sensor.sensor?(sensor_type) }
    # It also skips getSource, setSource, and RecordingDevice, whose OpenAL
    # Soft cannot record (Lovetest::PLAYBACK_ONLY), as Lövetest skips them.
    # On a desktop macOS does not draw, the isOccluded test skips
    # (test/lovetest/unseen_desktop.rb), and on a Windows desktop whose
    # foreground is held, the setGrabbed test (test/lovetest/held_foreground.rb).
    skips = HeldForeground.skips(UnseenDesktop.skips(LovetestSkips.expected + (supported.glsl4 ? 0 : 1) +
      (sensors.zero? ? 3 : 0)))

    assert_predicate status, :success?, output
    assert_match(/^love\.conf$/, output)
    assert_match(/^#{runs} runs, \d+ assertions, 0 failures, 0 errors, #{skips} skips$/, output)
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

  # A game's line that says whether the frame it is in runs inside
  # Lota::Event.pump, as a frame the event module's modal draw runs does,
  # and asks for the system's live resize redraw during the next pump
  # (LotaNativeTest.request_modal_draw) on the frame +ask+ names.
  MODAL_FRAME = <<~RUBY
    require "lota_native_test"

    def modal_frame(name, count, ask)
      inside = caller_locations.any? { |location| location.label == "Lota::Event.pump" }
      puts "\#{name} \#{count}\#{' inside pump' if inside}"
      LotaNativeTest.request_modal_draw if count == ask
    end
  RUBY

  # boot.lua hands each new frame of love.run to the event module
  # (boot.lua:507-514, love.event._setDefaultModalDrawCallback), whose
  # modal draw runs it while the system resizes the window
  # (event/sdl/Event.cpp:100-103, event/Event.cpp:108-130): the frame runs
  # again inside the pump of the frame under way, and draws.
  def test_the_frame_draws_while_the_system_resizes_the_window
    in_game("main.rb" => <<~RUBY) do |directory|
      #{MODAL_FRAME}
      def Lota.draw
        @frames = (@frames || 0) + 1
        modal_frame("draw", @frames, 1)
        Lota::Event.quit(3) if @frames == 3
      end
    RUBY
      output, status = lota_run(directory)

      assert_equal "draw 1\ndraw 2 inside pump\ndraw 3\n", output
      assert_equal 3, status.exitstatus, output
    end
  end

  # The frame is called as LÖVE's drawCallback calls it, with no error
  # handler of boot.lua's around it (wrap_Event.cpp:161-193), so what it
  # raises inside the modal draw comes out of the pump that ran it, after
  # the callback's name (event/sdl/Event.cpp:172-182), and reaches the
  # game's error handler from there.
  def test_an_error_the_frame_raises_while_the_window_is_resized_comes_out_of_the_pump
    in_game("main.rb" => <<~RUBY) do |directory|
      #{MODAL_FRAME}
      def Lota.draw
        @frames = (@frames || 0) + 1
        modal_frame("draw", @frames, 1)
        raise "broken" if @frames == 2
      end
      def Lota.errorhandler(error)
        puts "handled \#{error.class} \#{error.message}"
        -> { 4 }
      end
    RUBY
      output, status = lota_run(directory)

      assert_equal "draw 1\ndraw 2 inside pump\nhandled RuntimeError Error in modal draw callback: broken\n", output
      assert_equal 4, status.exitstatus, output
    end
  end

  # Once love.run has returned its frame, boot.lua hands every new frame
  # to the event module, the error handler's too (boot.lua:497-500 and
  # 510-514).
  def test_the_error_handlers_frame_draws_while_the_system_resizes_the_window
    in_game("main.rb" => <<~RUBY) do |directory|
      #{MODAL_FRAME}
      def Lota.update(dt) = raise("broken")
      def Lota.errorhandler(error)
        frames = 0
        lambda do
          Lota::Event.pump
          modal_frame("handler", frames += 1, 1)
          frames == 3 ? 5 : nil
        end
      end
    RUBY
      output, status = lota_run(directory)

      assert_equal "handler 1\nhandler 2 inside pump\nhandler 3\n", output
      assert_equal 5, status.exitstatus, output
    end
  end

  # When love.init or love.run fails, boot.lua hands no frame to the event
  # module, the error handler's neither (boot.lua:471 and 490-500).
  def test_the_error_handlers_frame_is_not_handed_on_when_the_game_failed_to_start
    in_game("main.rb" => <<~RUBY) do |directory|
      #{MODAL_FRAME}
      def Lota.load(*) = raise("broken")
      def Lota.errorhandler(error)
        frames = 0
        lambda do
          Lota::Event.pump
          modal_frame("handler", frames += 1, 1)
          frames == 3 ? 5 : nil
        end
      end
    RUBY
      output, status = lota_run(directory)

      assert_equal "handler 1\nhandler 2\nhandler 3\n", output
      assert_equal 5, status.exitstatus, output
    end
  end

  # LÖVE's event module goes with the Lua state when boot.lua's root
  # function returns (love.cpp, runlove), and the frame it holds with it,
  # so once call has returned no frame of the game is drawn, though Lota's
  # module stays open.
  def test_the_frame_is_not_drawn_once_the_game_has_ended
    in_game("main.rb" => <<~RUBY) do |directory|
      #{MODAL_FRAME}
      def Lota.draw
        @frames = (@frames || 0) + 1
        modal_frame("draw", @frames, 0)
        Lota::Event.quit(3)
      end
    RUBY
      output, status = capture2e({}, RbConfig.ruby, "-w", "-I#{run_load_path}", "-rlota", "-e", <<~RUBY, directory)
        status = Lota::Boot.new(ARGV.first).call
        LotaNativeTest.request_modal_draw
        Lota::Event.pump
        exit status
      RUBY

      assert_equal "draw 1\n", output
      assert_equal 3, status.exitstatus, output
    end
  end

  # An engine error a game meets reaches its error handler with its Lua
  # names translated (doc/contributors/design/translation.md), and so does one
  # the handler itself meets, which error_printer prints: what
  # ImageData:getPixel raises for an ImageData whose pixels it does not convert
  # (ImageData.cpp:549).
  def test_an_engine_error_reaches_the_error_handler_and_the_printer_translated
    srgba8 = "Lota::Image::ImageData#pixel does not currently support the srgba8 pixel format."
    meet = "Lota::Image::ImageData.new(1, 1, :srgba8).pixel(0, 0)"
    in_game("main.rb" => "def Lota.update(dt) = #{meet}\ndef Lota.errorhandler(error) = puts(error.message)\n") do |handled|
      in_game("main.rb" => "def Lota.load = raise('broken')\ndef Lota.errorhandler(error) = #{meet}\n") do |printed|
        handler_output, = lota_run(handled)
        printer_output, = lota_run(printed)

        assert_equal "#{srgba8}\n", handler_output
        assert_includes printer_output, "#{srgba8} (RuntimeError)\n"
        refute_includes printer_output, "ImageData:getPixel"
      end
    end
  end

  # rake package:install and package:deliver run their games with
  # OpenAL Soft's settings in tasks/alsoft.conf (PackageCheck::SILENT) and
  # match all they print. On a Linux whose system bus has no RTKit, as a
  # bare CI runner's has none, OpenAL Soft's mixer would report that it
  # could not ask RTKit for real-time priority ("Could not query RTKit",
  # OpenAL Soft 1.24.3, core/helpers.cpp:423) unless the settings ask for
  # none, so a run prints only what its game prints.
  def test_a_run_with_the_package_checks_audio_settings_prints_only_what_its_game_prints
    in_game("main.rb" => "def Lota.load = puts('loaded')\ndef Lota.draw = Lota::Event.quit(3)\n") do |directory|
      output, status = lota_run(directory, environment: PackageCheck::SILENT)

      assert_equal 3, status.exitstatus, output
      assert_equal "loaded\n", output
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

  # Numbers LÖVE's C++ holds as integers reach the game as Integers (rule 14 of
  # doc/contributors/design/translation.md): opening the window and changing its
  # mode each resize it, with the graphics module's int width and height
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

  # Lua passes nil for parameters its caller left out
  # (doc/contributors/design/game.md); update receives one argument and draw
  # none. Lua has no defaults, so draw's is the game's own and stays.
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
  # love.timer is nil in LÖVE, while its constant stays defined
  # (doc/contributors/design/game.md).
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
  # main.lua, and LÖVE leaves the working directory alone
  # (doc/contributors/design/game.md).
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

  # boot.lua sets the window's icon from t.window.icon before it opens the
  # window (boot.lua:400-403), decoding the file it names with
  # love.image.newImageData.
  def test_a_games_icon_from_conf_is_the_windows_icon
    logo = File.binread(File.join(ROOT, "vendor/love/testing/resources/love.png"))
    conf = "def Lota.conf(t)\n  t.window.icon = \"logo.png\"\nend\n"
    main = "def Lota.load\n  icon = Lota::Window.icon\n  p [icon.width, icon.height]\n  Lota::Event.quit\nend\n"
    in_game("logo.png" => logo, "conf.rb" => conf, "main.rb" => main) do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "[64, 64]\n", output
    end
  end

  # boot.lua asserts that love.image is loaded when an icon is set
  # (boot.lua:401), which Lota says of its own module, and the error
  # screen shows it.
  def test_an_icon_without_the_image_module_shows_loves_assertion
    conf = "def Lota.conf(t)\n  t.window.icon = \"logo.png\"\n  t.modules.image = false\nend\n"
    in_game("conf.rb" => conf, "main.rb" => "") do |directory|
      output, status = lota_run(directory, preload: QUIT_ON_ERROR)

      assert_equal 1, status.exitstatus, output
      assert_includes output, "If an icon is set in Lota.conf, Lota::Image must be loaded."
    end
  end

  # boot.lua checks t.version once the modules are open (boot.lua:378-393):
  # a version love.isVersionCompatible refuses is printed, and, with the
  # window module open, shown in a dialog before the window opens, which
  # waits until the player presses Return.
  def test_a_game_made_for_another_version_shows_loves_warning_in_a_dialog
    in_game("conf.rb" => "def Lota.conf(t) = (t.version = '11.3')\n",
      "main.rb" => "def Lota.load = (p Lota::Window.open?; Lota::Event.quit)\n") do |directory|
      output, status = lota_run(directory, preload: PRESS_RETURN, environment: answering_dialogs)

      assert_predicate status, :success?, output
      assert_equal "#{self.class.version_warning('11.3')}true\ndialogs 1\n", output
    end
  end

  # w_showMessageBox (wrap_Window.cpp:590-653) shows a box of one button and
  # returns whether it could, or shows the buttons it is given and returns
  # the one the player pressed, counting from 1. Return presses the
  # enterbutton, the first unless it says otherwise (SDL's
  # SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT, set in Window::showMessageBox).
  def test_a_game_shows_message_boxes_and_learns_which_button_was_pressed
    in_game("main.rb" => <<~RUBY) do |directory|
      def Lota.load
        p Lota::Window.show_message_box("Saved", "Your game was saved.", :info, false)
        p Lota::Window.show_message_box("Quit?", "Unsaved progress is lost.", %w[Quit Stay], :warning)
        p Lota::Window.show_message_box("Quit?", "Unsaved progress is lost.", %w[Quit Stay], enterbutton: 2)
        Lota::Event.quit
      end
    RUBY
      output, status = lota_run(directory, preload: PRESS_RETURN, environment: answering_dialogs)

      assert_predicate status, :success?, output
      assert_equal "true\n1\n2\ndialogs 3\n", output
    end
  end

  # w_close (wrap_Window.cpp:353-358) closes the window and is marked
  # deprecated without a replacement (luax_markdeprecated), so the first
  # use prints the notice, with where it was used.
  def test_closing_the_window_works_and_says_it_is_deprecated
    in_game("main.rb" => <<~RUBY) do |directory|
      def Lota.load
        Lota::Window.close
        p Lota::Window.open?
        Lota::Event.quit
      end
    RUBY
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "Lota - Warning: #{directory}/main.rb:2: Using deprecated function Lota::Window.close\nfalse\n", output
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
        output, status = lota_run(directory, preload: PRESS_RETURN, environment: answering_dialogs)

        assert_predicate status, :success?, output
        assert_equal "#{warned && self.class.version_warning(warned)}dialogs 0\n", output, version
      end
    end
  end

  # Where a game's saves go: the system's application data folder under
  # the tests' home of their own (test/test_helper.rb), then Lota's folder
  # unless the game is fused, then its identity
  # (doc/contributors/design/game.md; physfs/Filesystem.cpp:608-616).
  def self.save_directory(identity, fused: false)
    support = TestHome.application_data(ENV.fetch("LOTA_TEST_HOME"))
    TestHome.system_path(File.join(*[support, (TestHome::LOTA_FOLDER unless fused), identity].compact))
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
  # fused game saves, without Lota's folder (doc/contributors/design/game.md),
  # which is how the entry script lota fuse writes starts one.
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

  # A game that reads fingers and the mouse together, as one that runs on
  # a tablet and a desktop does, finds a touch and a mouse at one point of
  # the window at one position, in Lota::Graphics.width's units, whether
  # high DPI is on or off: LÖVE scales a touchscreen's position across the
  # window by the window's size in those units (normalizedToDPICoords,
  # vendor/love/src/modules/event/sdl/Event.cpp:62-77), and a mouse's
  # position in the window's own coordinates into them
  # (windowToDPICoords, lines 330-384). The game pushes the finger and the
  # click SDL would send (LotaNativeTest.push_finger and push_mouse_click)
  # from its load callback, and prints what its callbacks received. Where
  # the display has more pixels than points, high DPI doubles the pixels
  # and leaves the units alone; without it, a unit is a pixel.
  def test_a_touch_and_a_mouse_share_the_graphics_units_with_high_dpi_on_and_off
    main = <<~RUBY
      require "json"
      require "lota_native_test"
      def Lota.load
        w, h = LotaNativeTest.window_size
        LotaNativeTest.push_finger("down", 7, [0.25, 0.5, 0, 0, 1])
        LotaNativeTest.push_mouse_click(true, [w * 0.25, h * 0.5])
      end
      def Lota.touchpressed(id, x, y) = (@touch = [x, y])
      def Lota.mousepressed(x, y, _button, istouch) = (@mouse = [x, y, istouch])
      def Lota.update(_dt)
        @frames = (@frames || 0) + 1
        return unless (@touch && @mouse) || @frames > 60

        puts JSON.generate([Lota::Window.dpi_scale, Lota::Graphics.width, Lota::Graphics.pixel_width,
          @touch && Lota::Window.to_pixels(@touch.first), @touch, @mouse])
        Lota::Event.quit
      end
    RUBY
    scales = {}
    [true, false].each do |highdpi|
      in_game("conf.rb" => "def Lota.conf(t) = (t.highdpi = #{highdpi})\n", "main.rb" => main) do |directory|
        output, status = lota_run(directory, preload: QUIT_ON_ERROR)

        assert_predicate status, :success?, output
        scale, width, pixel_width, touch_pixel_x, touch, mouse = JSON.parse(output.lines.last)
        refute_nil touch, "highdpi #{highdpi}: no touchpressed in 60 frames: #{output}"
        refute_nil mouse, "highdpi #{highdpi}: no mousepressed in 60 frames: #{output}"
        assert_equal [touch, false], [mouse.take(2), mouse.last], "highdpi #{highdpi}: #{output}"
        assert_in_delta width * 0.25, touch.first, 1e-6, "highdpi #{highdpi}: #{output}"
        assert_in_delta pixel_width * 0.25, touch_pixel_x, 1e-6, "highdpi #{highdpi}: #{output}"
        assert_equal (width * scale).round, pixel_width, "highdpi #{highdpi}: #{output}"
        scales[highdpi] = scale
      end
    end
    # Without high DPI a unit is a pixel, except where LÖVE's usedpiscale
    # (on by default, Windows only here) scales the units to the display's
    # setting whatever highdpi says.
    expected = Gem.win_platform? ? scales[true] : 1.0
    assert_in_delta expected, scales[false], 1e-9, "the scale without high DPI"
  end

  # LÖVE 12 still honors the deprecated t.window.highdpi: boot.lua passes
  # it to setMode (boot.lua:421), which, before the window opens, allows
  # high DPI as t.highdpi does, and prints its notice, unless the game is
  # fused (boot.lua:96, wrap_Window.cpp:98-107).
  def test_the_deprecated_window_highdpi_still_allows_high_dpi
    conf = "def Lota.conf(t) = (t.window.highdpi = true)\n"
    main = "def Lota.load = (p Lota::Window.high_dpi_allowed?; Lota::Event.quit)\n"
    in_game("conf.rb" => conf, "main.rb" => main) do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      notice = "Using deprecated field window.highdpi (replaced by t.highdpi in Lota.conf)"
      assert_match(%r{\ALota - Warning: \S+/lib/lota/boot\.rb:\d+: #{Regexp.escape(notice)}\ntrue\n\z}, output)
    end
    in_game("main.rb" => main) do |directory|
      output, status = lota_run(directory)

      assert_predicate status, :success?, output
      assert_equal "false\n", output
    end
    in_game("conf.rb" => conf, "main.rb" => main) do |directory|
      native = File.dirname(File.dirname(loaded("lota/native")))
      output, status = capture2e({}, RbConfig.ruby, "-w", "-I#{native}#{File::PATH_SEPARATOR}#{File.join(ROOT, 'lib')}",
        "-rlota", "-e", "exit Lota::Boot.new(ARGV.first, fused: true).call", directory)

      assert_predicate status, :success?, output
      assert_equal "true\n", output, "a fused game prints no notices"
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
        output, status = lota_run(directory, environment: TestHome.environment(home))

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
