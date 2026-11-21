# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A file of the game beside main.rb, which main.rb requires.
module FuserCheckHelper
  # Whether this file is a real file in the app's own game folder, as
  # fledge build --from leaves the project, rather than in the archive or
  # the cache the lota program unpacks an archive into.
  def self.from_the_app?
    __dir__.tr("\\", "/").end_with?("/game/FuserCheck/lib") && File.file?(__FILE__)
  end
end
