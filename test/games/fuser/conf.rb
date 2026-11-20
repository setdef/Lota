# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game in one file for the fuser's check: zipped into a .lota, it is
# made into an app by the fuser app, and that app is started with no Ruby
# on its PATH (.github/fuse_check.rb). It opens no window, so it runs where
# no window can open.
def Lota.conf(t)
  t.title = "Fuser Check"
  t.identity = "FuserCheck"
  %i[window graphics image font keyboard mouse].each { |name| t.modules.public_send(:"#{name}=", false) }
end
