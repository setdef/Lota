# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# test/games/fuse's game, with a gem of pure Ruby from a folder in the game
# itself, named by its Gemfile's path:, for lota fuse's check on every
# platform (.github/workflows/fuse.yml).
def Lota.conf(t)
  t.title = "Fuse Check Path Gems"
  t.identity = "FuseCheckPathGems"
  %i[window graphics image font keyboard mouse].each { |name| t.modules.public_send(:"#{name}=", false) }
end
