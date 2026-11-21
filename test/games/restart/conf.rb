# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game that restarts, for test/native/in_process_restart_test.rb, the
# no-game screen's tests, and .github/windows_checks.rb. It opens no window
# and no graphics, since nothing a restart carries over depends on one.
def Lota.conf(t)
  t.title = "Restart"
  t.window.width = 64
  t.window.height = 48
  t.modules.audio = false
  t.modules.sound = false
  t.modules.window = false
  t.modules.graphics = false
  t.modules.image = false
  t.modules.font = false
  t.modules.keyboard = false
  t.modules.mouse = false
end
