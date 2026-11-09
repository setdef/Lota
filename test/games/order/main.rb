# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Prints each callback as Lota calls it, and at load the window's size in
# graphics units and in pixels with the display's scale (a display above
# 100% makes the units smaller than the pixels), and whether text input
# is on, which a new window starts without. The first draw asks to quit,
# and the quit callback refuses once, so the game draws a second frame
# and quits on the second request, with the status given on the command
# line.
puts "main"

def Lota.load(arguments, raw_arguments)
  puts "load #{arguments.inspect} #{raw_arguments.inspect}"
  puts "window #{Lota::Graphics.dimensions.join('x')} #{Lota::Window.title}"
  puts "pixels #{Lota::Graphics.pixel_width}x#{Lota::Graphics.pixel_height} scale #{Lota::Window.dpi_scale}"
  puts "text input #{Lota::Keyboard.text_input?}"
  @status = arguments.first&.to_i
  @quits = 0
end

def Lota.update(dt)
  puts "update #{dt.class}"
end

def Lota.draw
  puts "draw"
  Lota::Event.quit(@status)
end

def Lota.quit
  @quits += 1
  puts "quit #{@quits}"
  @quits == 1
end
