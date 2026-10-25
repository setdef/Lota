# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Prints each callback as Lota calls it. The first draw asks to quit, and
# the quit callback refuses once, so the game draws a second frame and
# quits on the second request, with the status given on the command
# line.
puts "main"

def Lota.load(arguments, raw_arguments)
  puts "load #{arguments.inspect} #{raw_arguments.inspect}"
  puts "window #{Lota::Graphics.dimensions.join('x')} #{Lota::Window.title}"
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
