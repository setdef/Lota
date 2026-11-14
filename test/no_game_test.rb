# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "callback_helper"
require_relative "no_game_artwork"

# Lota::NoGame defines the no-game screen's callbacks on Lota, as
# nogame.lua defines its own on the love table, its Lota.conf among them
# (nogame.lua:3275-3287). What it draws, and how it restarts, are
# test/parity/no_game_test.rb's and test/native/no_game_run_test.rb's to
# prove.
class NoGameTest < Minitest::Test
  include CallbackHelper

  CALLBACKS = %i[conf load update draw mousepressed keypressed resize filedropped directorydropped].freeze

  # Each callback takes what Lota passes, and the screen's method the
  # arguments nogame.lua's function declares: love.keypressed(key) is
  # given the key, the scancode, and whether it repeats.
  def test_it_defines_the_screens_callbacks_and_drops_the_arguments_they_do_not_declare
    Lota::NoGame.call(NoGameArtwork.read)

    assert_equal CALLBACKS.sort, (Lota.singleton_methods(false) & CALLBACKS).sort
    assert_nil Lota.keypressed(:space, :space, false)
  end

  def test_its_conf_asks_for_what_loves_does_under_lotas_name
    Lota::Native::System.open
    Lota::NoGame.call(NoGameArtwork.read)
    t = Lota::Settings.new
    Lota.conf(t)

    assert_equal "Lota #{Lota::VERSION}", t.title
    assert t.graphics.gammacorrect
    assert_equal [false, false, false], [t.modules.audio, t.modules.sound, t.modules.joystick]
    assert t.window.resizable
    assert t.highdpi
    refute t.window.borderless
  end

  def test_without_artwork_there_is_no_screen
    error = assert_raises(ArgumentError) { Lota::NoGame.call(nil) }

    assert_equal "the no-game screen has no artwork", error.message
    assert_empty Lota.singleton_methods(false) & CALLBACKS
  end

  # LuaJIT's a - floor(a / b) * b.
  def test_lua_mod_is_luas
    assert_in_delta 4.0, Lota::NoGame.lua_mod(-1.0, 5)
    assert_in_delta 0.25, Lota::NoGame.lua_mod(10.25, 5)
    assert_in_delta 3.5, Lota::NoGame.lua_mod(3.5, 5)
  end
end
