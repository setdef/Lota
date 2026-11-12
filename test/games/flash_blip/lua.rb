# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Lua's conversions between numbers and text, which the translation writes
# wherever FLASH-BLIP's Lua turns a number into text or text into a number,
# so that the text it draws, prints, and saves is the text LuaJIT makes.
module Lua
  # +value+ as Lua's tostring, and its .. operator, write it: a number as
  # LuaJIT writes a double, with C's %.14g (lj_strfmt_num), so 12.0 is
  # "12" and 0.1 is "0.1", and infinities and NaN as "inf", "-inf", and
  # "nan"; nil as "nil"; anything else as Ruby writes it.
  def self.tostring(value)
    case value
    when nil then "nil"
    when Numeric then number(value.to_f)
    else value.to_s
    end
  end

  def self.number(float)
    return "nan" if float.nan?
    return (float.positive? ? "inf" : "-inf") if float.infinite?

    format("%.14g", float)
  end

  # The number the text +text+ is, as Lua's tonumber reads it, or nil when
  # it is not one: leading and trailing spaces are allowed, and an integer
  # stays an Integer, which Lua's double writes and compares the same.
  def self.tonumber(text)
    return text if text.is_a?(Numeric)
    return nil unless text.is_a?(String)

    stripped = text.strip
    Integer(stripped, 10, exception: false) || Float(stripped, exception: false)
  end
end
