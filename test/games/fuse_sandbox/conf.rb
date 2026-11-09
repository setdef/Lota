# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A windowless game for the App Sandbox experiment in
# .github/workflows/fuse.yml, as test/games/fuse is.
def Lota.conf(t)
  t.title = "Fuse Sandbox"
  t.identity = "FuseSandbox"
  %i[window graphics image font keyboard mouse].each { |name| t.modules.public_send(:"#{name}=", false) }
end
