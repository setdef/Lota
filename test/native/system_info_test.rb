# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# The rest of Lota::System, translated from love.system
# (vendor/love/src/modules/system/wrap_System.cpp): what the computer says
# about itself. Lövetest checks only that most of these answer
# (test/lovetest/tests/system.rb) and skips openURL and vibrate, which
# these check as far as they can without opening a browser.
class SystemInfoTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  def test_processors_and_memory_are_positive_integers
    assert_kind_of Integer, Lota::System.processor_count
    assert_operator Lota::System.processor_count, :>, 0
    assert_kind_of Integer, Lota::System.memory_size
    assert_operator Lota::System.memory_size, :>, 0
  end

  # w_getPowerInfo (wrap_System.cpp:65-88) pushes the state and then a
  # percentage and seconds that are nil where the system cannot tell, so a
  # machine without a battery has neither.
  def test_power_info_is_a_state_symbol_then_a_percentage_and_seconds_or_nil
    state, percent, seconds = Lota::System.power_info

    assert_includes %i[unknown battery nobattery charging charged], state
    assert(percent.nil? || (0..100).cover?(percent))
    assert(seconds.nil? || seconds >= 0)
  end

  def test_preferred_locales_are_strings
    locales = Lota::System.preferred_locales

    assert_kind_of Array, locales
    assert(locales.all?(String))
  end

  def test_background_music_is_true_or_false
    assert_includes [true, false], Lota::System.background_music?
  end

  # A computer has no motor, so vibrating does nothing and returns nothing
  # (System::vibrate, system/System.cpp), whether or not it is told how
  # long; w_vibrate waits half a second by default (wrap_System.cpp:100).
  # This shows only that the call reaches the engine and returns nil: a
  # computer does nothing a test can read, so a binding that dropped the
  # seconds would pass too.
  def test_vibrating_a_computer_does_nothing
    assert_nil Lota::System.vibrate
    assert_nil Lota::System.vibrate(0.01)
  end

  # Opening a URL would open the person's browser, so this checks that the
  # binding reads a String (luax_checkstring, wrap_System.cpp:92) and
  # nothing else.
  def test_a_url_is_a_string
    assert_raises(TypeError) { Lota::System.open_url(1) }
    assert_raises(TypeError) { Lota::System.open_url(nil) }
  end

  def test_lota_system_is_the_module
    assert_same Lota::System, Lota.system
  end
end
