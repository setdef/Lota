# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A class the game requires, which counts how often it was loaded in this
# run of the game: once, when each run loads it afresh.
class Helper
  @loads = 0

  def self.load_once
    @loads += 1
  end
end
