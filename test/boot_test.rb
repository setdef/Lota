# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "callback_helper"
require "tmpdir"

# Lota::Boot configures a game as love.init does
# (vendor/love/src/modules/love/boot.lua:175-259): it loads conf.rb unless
# Lota.conf is already defined, then calls Lota.conf with the settings,
# and keeps any error for later. Opening the window is
# test/native/lota_run_test.rb's to prove, in a process of its own.
class BootTest < Minitest::Test
  include CallbackHelper

  def setup
    super
    @directory = Dir.mktmpdir("lota-boot-test")
  end

  def teardown
    FileUtils.remove_entry(@directory)
    super
  end

  def write(name, source)
    File.write(File.join(@directory, name), source)
  end

  def boot
    @boot ||= Lota::Boot.new(@directory)
  end

  def test_the_directory_is_the_absolute_path_of_the_folder
    assert_equal File.expand_path("."), Lota::Boot.new(nil).directory
    assert_equal File.expand_path("games/pong"), Lota::Boot.new("games/pong").directory
  end

  # LÖVE given no game looks in no folder for one (boot.lua:156-170), not
  # even the one it runs in.
  def test_with_no_game_there_is_no_folder_and_conf_rb_beside_it_is_not_loaded
    write("conf.rb", "raise 'conf.rb was loaded'\n")
    no_game = Lota::Boot.__send__(:no_game)

    assert_nil no_game.directory
    Dir.chdir(@directory) { assert_nil no_game.configure }
    refute no_game.__send__(:no_game_code?)
  end

  # boot.lua:51-60: the path nogame.lua restarts with goes first in arg,
  # ahead of whatever was there, so it is the game's.
  def test_a_game_dropped_on_the_no_game_screen_is_the_game_it_restarts_into
    no_game = Lota::Boot.__send__(:no_game, ["level2"])
    no_game.__send__(:start_dropped_game, { "_noGameRestartInfo" => { "gamepath" => "games/pong" } })

    assert_equal File.expand_path("games/pong"), no_game.directory
    assert_equal ["games/pong", ["level2"]], [
      no_game.instance_variable_get(:@path),
      no_game.instance_variable_get(:@arguments),
]

    with_game = Lota::Boot.new("games/chess", ["level2"])
    with_game.__send__(:start_dropped_game, { "_noGameRestartInfo" => { "gamepath" => "games/pong" } })

    assert_equal File.expand_path("games/pong"), with_game.directory
    assert_equal %w[games/chess level2], with_game.instance_variable_get(:@arguments)
  end

  def test_any_other_restart_value_leaves_the_game_alone
    [
      nil,
      "games/pong",
      { "gamepath" => "games/pong" },
      { "_noGameRestartInfo" => "games/pong" },
      { "_noGameRestartInfo" => { "gamepath" => 1.0 } },
].each do |value|
      no_game = Lota::Boot.__send__(:no_game)
      no_game.__send__(:start_dropped_game, value)

      assert_nil no_game.directory, value.inspect
    end
  end

  def test_without_conf_the_settings_are_loves_defaults
    assert_nil boot.configure

    assert_equal 800, boot.settings.window.width
  end

  def test_conf_rb_changes_the_settings
    write("conf.rb", <<~RUBY)
      def Lota.conf(t)
        t.window.width = 1280
        t.window.fullscreentype = :exclusive
        t.modules.physics = false
      end
    RUBY

    assert_nil boot.configure

    assert_equal 1280, boot.settings.window.width
    assert_equal :exclusive, boot.settings.window.fullscreentype
    refute boot.settings.modules.physics
  end

  def test_conf_rb_is_not_loaded_when_lota_conf_is_already_defined
    write("conf.rb", "raise 'conf.rb was loaded'\n")
    define_callback(:conf) { |t| t.title = "already defined" }

    assert_nil boot.configure

    assert_equal "already defined", boot.settings.title
  end

  def test_conf_may_take_no_settings
    write("conf.rb", "def Lota.conf = (Lota.instance_variable_set(:@boot_test_conf, true))\n")

    assert_nil boot.configure
    assert Lota.instance_variable_get(:@boot_test_conf)
  ensure
    Lota.remove_instance_variable(:@boot_test_conf) if Lota.instance_variable_defined?(:@boot_test_conf)
  end

  def test_an_error_in_lota_conf_is_returned_not_raised
    write("conf.rb", "def Lota.conf(t) = raise(ArgumentError, 'bad conf')\n")

    error = boot.configure

    assert_instance_of ArgumentError, error
    assert_equal "bad conf", error.message
  end

  def test_an_error_loading_conf_rb_is_returned_not_raised
    write("conf.rb", "raise 'broken conf.rb'\n")

    assert_equal "broken conf.rb", boot.configure.message
  end

  def test_a_syntax_error_in_conf_rb_is_returned_not_raised
    write("conf.rb", "def Lota.conf(t\n")

    assert_kind_of SyntaxError, boot.configure
  end

  def test_an_exit_in_conf_rb_is_not_caught
    write("conf.rb", "exit 3\n")

    assert_raises(SystemExit) { boot.configure }
  end

  def test_read_settings_runs_conf_rb_with_its_folder_on_the_load_path
    write("name.rb", "GAME_NAME = 'Read Settings'\n")
    write("conf.rb", "require 'name'\ndef Lota.conf(t) = (t.identity = GAME_NAME)\n")

    assert_equal "Read Settings", boot.read_settings.identity
  ensure
    $LOAD_PATH.delete(@directory)
  end

  def test_read_settings_raises_what_conf_rb_raised
    write("conf.rb", "def Lota.conf(t) = raise(ArgumentError, 'bad conf')\n")

    error = assert_raises(ArgumentError) { boot.read_settings }

    assert_equal "bad conf", error.message
  ensure
    $LOAD_PATH.delete(@directory)
  end

  # boot.lua:136-148, with Lota's name for a name left empty.
  def test_a_folder_identity_is_its_name_as_boot_lua_makes_it
    assert_equal "pong", Lota::Boot.folder_identity("games/pong")
    assert_equal "sample", Lota::Boot.folder_identity("games/.sample.game")
    assert_equal "a_b", Lota::Boot.folder_identity("/x/a.b.love")
    assert_equal "lotagame", Lota::Boot.folder_identity("/x/...")
  end

  # LÖVE's require looks in the game's folder before anywhere else but
  # package.preload (src/modules/filesystem/wrap_Filesystem.cpp:1122-1124).
  def test_the_game_folder_goes_first_on_the_load_path_once
    2.times { boot.__send__(:add_to_load_path) }

    assert_equal @directory, $LOAD_PATH.first
    assert_equal 1, $LOAD_PATH.count(@directory)
  ensure
    $LOAD_PATH.delete(@directory)
  end

  def test_renderers_default_to_loves_order
    assert_equal Lota::Native::Graphics.default_renderers.map(&:to_sym), renderers
  end

  def test_t_graphics_renderers_replace_the_defaults
    boot.settings.graphics.renderers = [:opengl, "metal"]

    assert_equal %i[opengl metal], renderers
  end

  def test_t_renderers_are_used_unless_t_graphics_renderers_are_set
    boot.settings.renderers = [:opengl]

    assert_equal [:opengl], renderers

    boot.settings.graphics.renderers = [:metal]

    assert_equal [:metal], renderers
  end

  def test_excluded_renderers_remove_their_last_occurrence
    boot.settings.graphics.renderers = %i[metal opengl metal]
    boot.settings.graphics.excluderenderers = [:metal]

    assert_equal %i[metal opengl], renderers
  end

  def test_t_graphics_excluderenderers_replace_t_excluderenderers
    boot.settings.graphics.renderers = %i[metal opengl]
    boot.settings.excluderenderers = [:metal]

    assert_equal [:opengl], renderers

    boot.settings.graphics.excluderenderers = [:opengl]

    assert_equal [:metal], renderers
  end

  def test_renderers_ignore_t_graphics_when_it_is_not_settings
    boot.settings.renderers = [:opengl]
    boot.settings.graphics = false

    assert_equal [:opengl], renderers
  end

  private def renderers
    graphics = boot.settings.graphics
    boot.__send__(:renderers, graphics.is_a?(Lota::Settings::Graphics) ? graphics : nil)
  end
end
