# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A fused game for .github/sandbox_run.sh, which runs it under the macOS
# App Sandbox. It opens no window, so it runs where no one is logged in.
def Lota.conf(t)
  t.title = "Fuse Sandbox"
  t.identity = "FuseSandbox"
  %i[window graphics image font keyboard mouse].each { |name| t.modules.public_send(:"#{name}=", false) }
end
