# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Lota::Record: a record Lota returns where LÖVE returns a table of fields
# answers +[]+ with a field's name, as a Lua table answers brackets
# (ADR 001, rule 10), so a field no reader can name, such as
# getTextureTypes' +2d+, reads as Lua reads it.
class RecordTest < Minitest::Test
  def types
    Lota::Graphics::TextureTypes.new("2d": true, volume: false, array: true, cube: true)
  end

  def info
    Lota::Filesystem::Info.new(type: :file, readonly: false, size: 18, modtime: 7)
  end

  def test_a_field_reads_by_its_name_as_a_string
    assert(types["2d"])
    refute(types["volume"])
  end

  def test_a_field_reads_by_its_name_as_a_symbol
    assert(types[:cube])
    assert_equal 18, info[:size]
  end

  def test_a_name_the_record_lacks_reads_as_nil_as_a_missing_key_does_in_lua
    assert_nil types["3d"]
    assert_nil info[:name]
  end

  def test_a_key_that_is_not_a_name_reads_as_nil
    assert_nil types[1]
    assert_nil info[nil]
  end

  def test_brackets_never_reach_a_method_that_is_not_a_field
    assert_nil info[:to_h]
    assert_nil info["frozen?"]
  end

  def test_every_record_lota_returns_answers_brackets
    records = [
      Lota::Filesystem::Info,
      Lota::Window::Mode,
      Lota::Graphics::Stats,
      Lota::Graphics::Supported,
      Lota::Graphics::SystemLimits,
      Lota::Graphics::TextureFormats,
      Lota::Graphics::TextureTypes,
    ]

    records.each { |record| assert_operator record, :<, Lota::Record, record.name }
  end

  def test_a_record_stays_frozen
    assert_predicate types, :frozen?
  end
end
