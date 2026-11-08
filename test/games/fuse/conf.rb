# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A game for lota fuse's check on every platform (.github/workflows/fuse.yml),
# whose runners may have no GPU: it opens no window and no graphics, as
# the delivery jobs' game does (WINDOWLESS_GAME in tasks/package.rake),
# and names itself and the folder it saves in, which lota fuse reads.
def Lota.conf(t)
  t.title = "Fuse Check"
  t.identity = "FuseCheck"
  %i[window graphics image font keyboard mouse].each { |name| t.modules.public_send(:"#{name}=", false) }
end
