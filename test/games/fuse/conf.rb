# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game for lota fuse's check on every platform (.github/workflows/fuse.yml):
# it names itself and the folder it saves in, which lota fuse reads, and
# opens the window Lövetest's conf.lua opens (vendor/love/testing/conf.lua),
# so the screenshot it saves can be compared with the one Lövetest's
# captureScreenshot test expects.
def Lota.conf(t)
  t.title = "Fuse Check"
  t.identity = "FuseCheck"
  t.window.width = 360
  t.window.height = 240
  t.window.resizable = true
  t.window.depth = true
  t.window.stencil = true
  t.window.usedpiscale = false
end
