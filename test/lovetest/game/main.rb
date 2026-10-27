# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runs Lövetest's translated tests from inside Lota's game loop, as
# Lövetest's main.lua runs its tests from love.update
# (vendor/love/testing/main.lua:178-182), then quits with 0 when every test
# passed and 1 otherwise. This runner is Lota's own; the tests it runs are
# Lövetest's.
require_relative "../tests/audio"
require_relative "../tests/graphics"
require_relative "../tests/keyboard"
require_relative "../tests/mouse"
require_relative "../tests/math"
require_relative "../tests/event"
require_relative "../tests/clipboard"
require_relative "../tests/window"
require_relative "../tests/filesystem"

def Lota.update(_dt)
  passed = Minitest.run([])
  Lota::Event.quit(passed ? 0 : 1)
end
