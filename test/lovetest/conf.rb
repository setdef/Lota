# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
# SPDX-License-Identifier: Zlib
#
# Translated to Ruby from Lövetest's conf.lua (vendor/love/testing/
# conf.lua:1-11). Lua's print becomes puts. t.window.name is a field
# boot.lua never reads, which Lota::Settings accepts and ignores, as a Lua
# table does. One part has no translation: conf.lua's love.errorhandler
# (lines 13-22) prints the error instead of drawing LÖVE's error screen;
# Lota has no error screen yet, and prints the error and its backtrace
# already.
def Lota.conf(t)
  puts("love.conf")
  t.console = true
  t.window.name = "love.test"
  t.window.width = 360
  t.window.height = 240
  t.window.resizable = true
  t.window.depth = true
  t.window.stencil = true
  t.window.usedpiscale = false
end
# SPDX-SnippetEnd
