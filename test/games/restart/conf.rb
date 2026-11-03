# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game that restarts, for test/native/restart_run_test.rb. Unless
# LOTA_RESTART_WINDOW is set it opens no window and no graphics, as a
# process that opened a window keeps system threads that make a restart
# wait on a busy Mac (Lota::Restart), and nothing a restart carries over
# depends on one. With it set the window is small, so the runs open and
# close theirs quickly.
def Lota.conf(t)
  t.title = "Restart"
  t.window.width = 64
  t.window.height = 48
  t.modules.audio = false
  t.modules.sound = false
  return if ENV.key?("LOTA_RESTART_WINDOW")

  t.modules.window = false
  t.modules.graphics = false
  t.modules.image = false
  t.modules.font = false
  t.modules.keyboard = false
  t.modules.mouse = false
end
