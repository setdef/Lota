# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The String LÖVE's engine reads for a name a game passes as a Symbol
  # (ADR 001, rule 9), or as the String LÖVE's Lua API takes. :nodoc:
  #
  # Symbol#name returns a frozen String that Ruby keeps with the Symbol,
  # where Symbol#to_s makes a new String each call, so a draw call that
  # passes +:fill+ every frame allocates nothing for it (ADR 001, section
  # 8).
  module EnumName
    # +value+'s name: a Symbol's frozen name, or +value+ as a String.
    def self.of(value)
      value.is_a?(Symbol) ? value.name : value.to_s
    end
  end
end
