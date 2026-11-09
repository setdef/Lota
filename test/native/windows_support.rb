# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# What the native suite does on Windows alone, where native_helper.rb
# loads this file.
module WindowsSupport
  # Why a test that needs the test extension to reach Lota's SDL skips on
  # Windows. There each extension links SDL into itself, as every other
  # library LÖVE links but OpenAL Soft (tasks/windows_build.rb), so the
  # test extension's SDL is not the one Lota's windows, input, and events
  # run on: it has opened no window and knows no device, and a key it holds
  # or an event it pushes never reaches Lota. On macOS and Linux both
  # extensions load one shared SDL.
  SDL_APART = "on Windows each extension links SDL into itself (tasks/windows_build.rb), " \
    "so the test extension cannot reach the SDL Lota runs on"

  # The test extension's functions that work through its SDL.
  SDL_FUNCTIONS = %i[
    scancode
    press_mouse
    press_key
    push_finger
    push_touch_mouse
    push_mouse_click
    touch_devices
    attach_virtual_joystick
    detach_virtual_joystick
    set_virtual_button
    set_virtual_axis
    set_virtual_hat
    window_size
    click_mouse
    edit_text
    resize_window
    request_modal_draw
    rotate_display
    sdl_error
    clear_sdl_error
    swap_interval
    text_input_area
  ].freeze

  # Skips the test that calls one of SDL_FUNCTIONS, or holds a key, which
  # is +hold+ with a scancode, where +hold+ with a Counted alone holds an
  # engine object.
  module SkipWhereSDLIsApart
    SDL_FUNCTIONS.each do |name|
      define_method(name) { |*| raise Minitest::Skip, SDL_APART }
    end

    def hold(*arguments)
      raise Minitest::Skip, SDL_APART if arguments.size == 2

      super
    end
  end
  LotaNativeTest.singleton_class.prepend(SkipWhereSDLIsApart)

  # Starts +command+ as NativeHelper.spawn does. Ruby starts a process on
  # Windows with CreateProcess (win32/win32.c, CreateChild), never a fork,
  # and waits only for a process it started itself, so Process.spawn
  # starts it.
  def self.spawn(command, output, variables)
    environment = variables.to_h { |variable| variable.split("=", 2) }
    Process.spawn(environment, *command, unsetenv_others: true, in: File::NULL, out: output, err: output)
  end
end
