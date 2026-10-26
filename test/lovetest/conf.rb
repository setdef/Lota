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
# conf.lua:1-22). Lua's print becomes puts. t.window.name is a field
# boot.lua never reads, which Lota::Settings accepts and ignores, as a Lua
# table does. conf.lua's love.errorhandler prints the error instead of
# drawing LÖVE's error screen, and returns no frame, so the program ends;
# its error_printer is a copy of LÖVE's own (callbacks.lua:217-219), which
# Lota ports as Lota::Callbacks.error_printer, so the translation calls
# that one, which takes the error's text as tostring does.
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

# custom crash message here to catch anything that might occur with modules
# loading before we hit main.lua
def Lota.errorhandler(msg)
  Lota::Callbacks.error_printer(msg)
end
# SPDX-SnippetEnd
