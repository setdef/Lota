# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Starts Lota with no game, as LÖVE starts when it is given none, for the
# parity harness's run of the no-game screen (Parity::NO_GAME): Lota shows
# its no-game screen (Lota::NoGame) with LÖVE's own pictures
# (test/no_game_artwork.rb), so that it can be compared with LÖVE's.
require "lota"
require_relative "../no_game_artwork"

Lota::NoGame.artwork = NoGameArtwork.read
exit Lota::Boot.__send__(:no_game).call
