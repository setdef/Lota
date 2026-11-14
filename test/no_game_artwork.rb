# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The pictures LÖVE's no-game screen draws, read from its own nogame.lua in
# the pinned submodule as a test runs, for Lota::NoGame.artwork. Lota
# ships no pictures of LÖVE's, so the tests that compare the screen with
# LÖVE's, and that drop a game on it, give it LÖVE's own.
module NoGameArtwork
  # LÖVE's no-game screen.
  NOGAME = File.expand_path("../vendor/love/src/scripts/nogame.lua", __dir__)

  # Each picture's line in nogame.lua, R.group[density].name =
  # love.data.decode("data", "base64", "..."), and the string's text.
  PICTURE = /^\s*R\.(\w+)\[(\d)\]\.(\w+) = love\.data\.decode\("data", "base64", "(.*?)"\)/m

  # The pictures as Lota::NoGame.artwork holds them: each group, density,
  # and name to the base64 text of the picture's PNG file, as Lua reads the
  # string, in which a backslash before a line's end stands for that line
  # end.
  def self.read(path = NOGAME)
    artwork = Hash.new { |groups, group| groups[group] = Hash.new { |densities, density| densities[density] = {} } }
    File.read(path).scan(PICTURE) do |group, density, name, text|
      artwork[group.to_sym][Integer(density)][name.to_sym] = text.gsub("\\\n", "\n")
    end
    raise "found no pictures in #{path}" if artwork.empty?

    artwork.transform_values(&:to_h)
  end
end
