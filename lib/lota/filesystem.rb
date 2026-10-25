# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "filesystem/file_data"

module Lota
  # Files and the bytes read from them, translated from love.filesystem.
  #
  # A game loads its images, sounds, and fonts from files. LÖVE's engine
  # decodes them from bytes in memory, and it wants to know each file's
  # name, so that a decoder can tell a PNG from a WAV.
  #
  # So far this module holds only FileData, which carries bytes and a
  # name into the engine. Finding files by name, in a game's own directory
  # and its save directory, waits on how a Lota game is laid out.
  module Filesystem
  end
end
