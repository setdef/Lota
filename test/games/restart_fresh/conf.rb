# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game that restarts in the same process, for
# test/native/in_process_restart_test.rb, with a small window.
def Lota.conf(t)
  t.title = "Restart fresh"
  t.window.width = 64
  t.window.height = 48
end
