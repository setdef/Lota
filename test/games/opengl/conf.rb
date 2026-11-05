# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game that opens a small window with OpenGL alone, for the opengl check
# of .github/windows_checks.rb. It reports the renderer it got and quits,
# or, when the window cannot open, prints why and exits with 1 instead of
# showing LÖVE's message box, which would wait for a player who is not
# there.
$stdout.sync = true

def Lota.conf(t)
  t.title = "OpenGL"
  t.window.width = 64
  t.window.height = 48
  t.graphics.renderers = [:opengl]
  t.modules.audio = false
  t.modules.sound = false
end

def Lota.errorhandler(error)
  puts "error: #{error.message}"
  nil
end
