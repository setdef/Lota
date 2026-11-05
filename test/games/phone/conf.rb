# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game for the phone route's check (.github/workflows/phones.yml), which
# builds it for the iOS Simulator and an Android emulator as
# doc/guide/phones.md says to build a game. It draws at the screen's own
# pixels, as a game on a phone usually should, since LÖVE's default is 1x.
def Lota.conf(t)
  t.title = "Phone Check"
  t.identity = "PhoneCheck"
  t.highdpi = true
end
