# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2021 Nightwolf-47
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from KleleAtoms' conf.lua
# (test/fixtures/klele_atoms/conf.lua, lines 1-17): love.conf becomes
# Lota.conf (ADR 003), with the settings' names unchanged (ADR 003,
# section 5). Lota does not set the window's icon from t.window.icon yet,
# which only the Dock shows.
def Lota.conf(t)
  t.identity = "kleleatoms"
  t.version = "11.3"
  t.window.vsync = 0
  t.window.title = "KleleAtoms 1.4"
  t.window.width = 640
  t.window.height = 480
  t.window.minwidth = 320
  t.window.minheight = 240
  t.window.resizable = false
  t.modules.joystick = false
  t.modules.physics = false
  t.window.usedpiscale = false
  t.externalstorage = true
  t.console = false
  t.window.icon = "graphics/icon.png"
end
# SPDX-SnippetEnd
