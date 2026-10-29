# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # What every record Lota returns where LÖVE returns a table of fields
  # answers besides its readers (ADR 001, rule 10): +[]+ with a field's
  # name, as a Lua table answers brackets.
  #
  # A field Lua reads only with brackets reads the same way in Ruby, as
  # Lota::Graphics.texture_types' +2d+ does, which no reader can be
  # called by without +public_send+.
  #
  # === Example
  #
  #   types = Lota::Graphics.texture_types
  #   types["2d"]   # => true
  #   types[:cube]  # => true
  #   types.cube    # => true
  module Record
    # The field named +name+, a String or a Symbol, or +nil+ when the
    # record has no such field, as Lua gives +nil+ for a key a table does
    # not hold.
    def [](name)
      return nil unless name.is_a?(String) || name.is_a?(Symbol)

      field = name.to_sym
      members.include?(field) ? public_send(field) : nil
    end
  end
end
