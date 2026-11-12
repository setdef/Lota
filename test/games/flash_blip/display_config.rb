# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's display_config.lua
# (test/fixtures/flash_blip/game/display_config.lua, lines 1-54), by the
# rules of doc/contributors/design/translation.md: love.filesystem.getInfo
# becomes Lota::Filesystem.info (rule 3), and read returns an Array (rule 4).
# The configuration, a table with fixed fields that main.lua makes and
# load returns, is a Config, whose fields read and write as Lua's do.
# table.concat writes each number as Lua's tostring does, which Lua.tostring
# does here, and Lua's tonumber is Lua.tonumber. table.insert of nil, for a
# line that is not a number, adds nothing to a Lua array, so here a line
# that is not a number is skipped too.

require "lua"

module DisplayConfig
  # The saved display configuration.
  Config = Struct.new(:pixel_width, :pixel_height, :desktop_width, :desktop_height, :dpi_scale,
    :internal_height, :scale_factor, keyword_init: true)

  CONFIG_FILE = "display_config.txt"

  def self.save(config)
    Lota::Filesystem.write(
      CONFIG_FILE,
      [
        config.pixel_width,
        config.pixel_height,
        config.desktop_width,
        config.desktop_height,
        config.dpi_scale,
        config.internal_height,
        config.scale_factor,
      ].map { |value| Lua.tostring(value) }.join("\n"),
    )
  end

  def self.load
    return nil unless Lota::Filesystem.info(CONFIG_FILE)

    content, = Lota::Filesystem.read(CONFIG_FILE)
    return nil unless content

    values = []
    content.scan(/[^\n]+/) do |line|
      value = Lua.tonumber(line)
      values << value unless value.nil?
    end

    return nil if values.size != 7

    Config.new(
      pixel_width: values[0],
      pixel_height: values[1],
      desktop_width: values[2],
      desktop_height: values[3],
      dpi_scale: values[4],
      internal_height: values[5],
      scale_factor: values[6],
    )
  end

  def self.clear
    Lota::Filesystem.remove(CONFIG_FILE)
  end
end
# SPDX-SnippetEnd
