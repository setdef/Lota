# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# What Lota's boot sequence and game loop call on the engine, in this
# process's window, which Lövetest's conf.rb sized (test/lovetest/conf.rb).
class FrameBindingsTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  def test_the_window_has_the_size_conf_rb_gave_it
    assert_equal [360, 240], Lota::Graphics.dimensions
    assert_equal 360, Lota::Graphics.width
    assert_equal 240, Lota::Graphics.height
  end

  def test_the_window_is_titled_from_the_settings_and_takes_a_new_title
    assert_equal "Untitled", Lota::Window.title

    Lota::Window.title = "Lota – tests"

    assert_equal "Lota – tests", Lota::Window.title
    assert_equal Encoding::UTF_8, Lota::Window.title.encoding
  ensure
    Lota::Window.title = "Untitled"
  end

  def test_an_unknown_fullscreen_type_raises_loves_error_before_changing_the_window
    error = assert_raises(ArgumentError) { Lota::Window.set_mode(100, 100, fullscreentype: :windowed) }

    assert_equal "Invalid fullscreen type 'windowed', expected one of: 'exclusive', 'desktop'", error.message
    assert_equal [360, 240], Lota::Graphics.dimensions
  end

  def test_graphics_is_active_with_an_open_window
    assert_predicate Lota::Graphics, :active?
  end

  def test_the_background_color_starts_opaque_black
    assert_equal [0.0, 0.0, 0.0, 1.0], Lota::Graphics.background_color
  end

  def test_present_raises_loves_error_while_a_canvas_is_the_target
    Lota::Graphics.canvas = Lota::Graphics::Canvas.new(4, 4)

    error = assert_raises(RuntimeError) { Lota::Graphics.present }
    assert_equal "present cannot be called while a render target is active.", error.message
  ensure
    Lota::Graphics.canvas = nil
  end

  def test_pumping_raises_loves_error_while_a_canvas_is_the_target
    Lota::Graphics.canvas = Lota::Graphics::Canvas.new(4, 4)

    error = assert_raises(RuntimeError) { Lota::Event.pump }
    assert_equal "Lota::Event.pump cannot be called while a render target is active in Lota::Graphics.", error.message
  ensure
    Lota::Graphics.canvas = nil
  end

  def test_the_timer_steps_and_sleeps
    Lota::Timer.step
    Lota::Timer.sleep(0.01)

    assert_operator Lota::Timer.step, :>=, 0.009
  end

  def test_a_quit_event_carries_its_status_as_a_float
    Lota::Native::Event.pump
    nil while Lota::Callbacks.poll
    Lota::Event.quit(4)

    assert_equal [:quit, [4.0]], Lota::Callbacks.poll
  end

  def test_a_quit_event_without_a_status_carries_nil
    nil while Lota::Callbacks.poll
    Lota::Event.quit

    assert_equal [:quit, [nil]], Lota::Callbacks.poll
  end
end
