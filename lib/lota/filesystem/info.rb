# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Filesystem
    # What the filesystem knows of a file or directory, which
    # Lota::Filesystem.info returns, translated from the table
    # love.filesystem.getInfo returns
    # (src/modules/filesystem/wrap_Filesystem.cpp, w_getInfo): a frozen
    # value with LÖVE's field names (ADR 001, rule 10).
    #
    # [type] What it is: +:file+, +:directory+, +:symlink+, or +:other+.
    # [readonly] Whether the game cannot write to it, as for a file in the
    #   game's own folder.
    # [size] Its size in bytes, an Integer, or +nil+ when the filesystem
    #   cannot tell, where LÖVE leaves the field out.
    # [modtime] When it last changed, as an Integer of seconds since the
    #   epoch, or +nil+ likewise.
    #
    # === Example
    #
    #   info = Lota::Filesystem.info("settings.txt")
    #   info.type # => :file
    #   info.size # => 18
    class Info < ::Data.define(:type, :readonly, :size, :modtime)
      include Record
    end
  end
end
