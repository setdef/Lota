# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Words a sample game shouts.
module SampleHelper
  # +word+ in capitals with an exclamation mark.
  def self.shout(word) = "#{word.upcase}!"
end
