# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game that reports each callback as Lota calls it, for
# test/native/lota_run_test.rb. Its window's size and title come from
# here, so the test can see them reach the window.
$stdout.sync = true

def Lota.conf(t)
  puts "conf #{t.window.width}x#{t.window.height}"
  t.title = "Order"
  t.window.width = 320
  t.window.height = 200
end
