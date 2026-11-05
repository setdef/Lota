# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Moon Pong ’em, a made-up game for the iOS kit's own check (ipad/ and
# .github/workflows/ios-kit.yml on the experiment/ios-kit-* branches): a
# ball and two paddles that play by themselves, and a touch moves the
# bottom paddle. Its icons, its own program in bin/, and its name, which
# has a typographic apostrophe, are what the kit's build must carry.
def Lota.conf(t)
  t.identity = "moon_pong"
  t.highdpi = true
  t.window.title = "Moon Pong ’em"
end
