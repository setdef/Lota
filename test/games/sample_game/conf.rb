# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Sample Game, a made-up game for the iOS kit's own check (ipad/ and
# .github/workflows/ios-kit-caller.yml, which calls ios-kit.yml): a
# ball and two paddles that play by themselves, and a touch moves the
# bottom paddle. Its icons and its own program in bin/ are what the
# kit's build must carry.
def Lota.conf(t)
  t.identity = "sample_game"
  t.highdpi = true
  t.window.title = "Sample Game"
end
