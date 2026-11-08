# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Reports the renderer the window opened with: its name, version, vendor,
# and device.
def Lota.load
  puts "renderer: #{Lota::Graphics.renderer_info.join(' / ')}"
  Lota::Event.quit(0)
end
