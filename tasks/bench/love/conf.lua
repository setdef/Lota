-- SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- rake bench's game for the reference love, as tasks/bench/lota/conf.rb
-- is Lota's: an 800 by 600 window without vertical sync, so a frame takes
-- as long as its work and not until the display's next refresh.
function love.conf(t)
  t.window.title = "LÖVE bench"
  t.window.width = 800
  t.window.height = 600
  t.window.vsync = 0
end
