# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game that restarts once, for test/native/lota_run_test.rb. Its window
# is small, so the two runs open and close theirs quickly.
def Lota.conf(t)
  t.title = "Restart"
  t.window.width = 64
  t.window.height = 48
  t.modules.audio = false
  t.modules.sound = false
end
