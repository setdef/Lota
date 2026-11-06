# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The diagnostics game of the Windows kit (tasks/windows_kit/), which the
# kit runs fused, built with lota fuse, on a real Windows PC. It opens no
# window at boot: main.rb opens one itself, so that a computer that
# refuses the renderer gets the engine's message on standard output and
# an exit status of 4, rather than a message box that waits for a click.
#
# On a phone, where a game draws at 1x unless t.highdpi is true, as in
# LÖVE (boot.lua), WINKIT_HIGHDPI=1 asks for the screen's own pixels, and
# WINKIT_DPI_PROBE=1 (main.rb) does too.
$stdout.sync = true
$stderr.sync = true

def Lota.conf(t)
  t.title = "Winkit"
  t.identity = "winkit"
  t.window = false
  t.highdpi = true if %w[WINKIT_HIGHDPI WINKIT_DPI_PROBE].any? { |name| ENV.fetch(name, nil) == "1" }
end
