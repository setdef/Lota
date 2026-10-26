# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# rake bench's game for Lota, as tasks/bench/love/conf.lua is LÖVE's: an
# 800 by 600 window without vertical sync, so a frame takes as long as its
# work and not until the display's next refresh.
def Lota.conf(t)
  t.window.title = "Lota bench"
  t.window.width = 800
  t.window.height = 600
  t.window.vsync = 0
end
