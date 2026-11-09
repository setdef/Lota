# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/error_message/names"

# The guide's and the README's tables pair a line of LÖVE with its Lota
# translation, and a reader copies the right-hand side. Each name a row
# gives on the Lota side must be the one the binding generator's name table
# (lib/lota/error_message/names.rb) gives the LÖVE name beside it, so a
# wrong example fails here rather than in a reader's game.
class TranslationExamplesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DOCUMENTS = %w[doc/guide/translating.md README.md].freeze
  NAMES = Lota::ErrorMessage::NAMES

  # One row of a table with a LÖVE column and a Lota column.
  Row = Data.define(:document, :line, :love, :lota)

  # love.module.function, love.module, or love.callback.
  LOVE_FUNCTION = /\blove\.(\w+)(?:\.(\w+))?/
  # variable:method(, a call on an object.
  LOVE_METHOD = /\b([a-z]\w*):(\w+)\(/
  # Lota::Module.function, Lota::Module::Class.new, or Lota::Module, with
  # a writer's "=" when one follows.
  LOTA_FUNCTION = /\bLota((?:::[A-Z]\w*)+)(?:\.(\w+[?!]?)(\s*=(?![=~>]))?)?/
  # Lota.callback.
  LOTA_CALLBACK = /\bLota\.([a-z_]\w*)\b(?![?!])/

  def test_every_example_names_what_the_generator_names
    rows = DOCUMENTS.flat_map { |document| rows_of(document) }

    assert_operator rows.size, :>=, 30, "the tables should hold the guide's examples"
    wrong = rows.flat_map { |row| mistakes(row) }

    assert_empty wrong, "these examples name what the translation rules do not"
  end

  def test_a_wrong_example_is_caught
    row = Row.new(document: "planted", line: 1, love: "`love.window.setTitle(\"Game\")`",
      lota: "`Lota::Window.set_title(\"Game\")`")

    refute_empty mistakes(row)
  end

  def test_a_function_lota_does_not_name_is_caught
    row = Row.new(document: "planted", line: 1, love: "`love.mouse.getPos()`", lota: "`Lota::Mouse.pos`")

    refute_empty mistakes(row)
  end

  # Every row of every table in +document+ whose header has a LÖVE column
  # and a Lota column.
  def rows_of(document)
    lines = File.readlines(File.join(ROOT, document), chomp: true)
    lines.each_with_index.flat_map do |line, index|
      next [] unless line.start_with?("|") && lines[index + 1].to_s.match?(/\A\|\s*-+/)

      header = cells(line)
      love = header.index { |cell| cell.include?("LÖVE") }
      lota = header.index { |cell| cell.include?("Lota") && !cell.include?("LÖVE") }
      next [] unless love && lota

      body = lines[(index + 2)..].take_while { |row| row.start_with?("|") }
      body.each_with_index.map do |row, offset|
        columns = cells(row)
        Row.new(document:, line: index + 3 + offset, love: columns[love], lota: columns[lota])
      end
    end
  end

  # The cells of a table row; a "\|" inside a cell stays in it.
  def cells(line)
    line.strip.delete_prefix("|").delete_suffix("|").split(/(?<!\\)\|/).map { |cell| cell.strip.gsub("\\|", "|") }
  end

  # What is wrong with +row+: each Lota name that no LÖVE name in the row
  # translates to, each LÖVE name the generator does not know, and a row
  # whose LÖVE side names something its Lota side does not translate.
  def mistakes(row)
    love = code(row.love)
    lota = code(row.lota)
    expected = expected_names(love)
    return [] if expected.empty? && lota_names(lota, love).empty?

    unknown = expected.select { |_, ruby| ruby.nil? }.map { |name, _| "#{where(row)}: #{name} is not a LÖVE function" }
    allowed = expected.values.compact.flat_map { |names| Array(names) }
    named = lota_names(lota, love)
    stray = (named - allowed).map { |name| "#{where(row)}: #{name} translates none of #{expected.keys.join(', ')}" }
    missing = named.empty? ? ["#{where(row)}: no Lota name translates #{expected.keys.join(', ')}"] : []
    unknown + stray + missing
  end

  def where(row)
    "#{row.document}:#{row.line}"
  end

  # The code spans of a cell, joined.
  def code(cell)
    cell.to_s.scan(/`([^`]+)`/).flatten.join(" ")
  end

  # Each LÖVE name in +love+, with the Ruby names the rules allow for it,
  # or nil when the generator does not name it.
  def expected_names(love)
    functions = love.scan(LOVE_FUNCTION).to_h do |mod, function|
      function ? ["love.#{mod}.#{function}", NAMES["love.#{mod}.#{function}"]] : ["love.#{mod}", module_or_callback(mod)]
    end
    methods = love.scan(LOVE_METHOD).to_h do |variable, method|
      found = NAMES.select { |name, _| name.end_with?(":#{method}") }.values.map { |ruby| "#{variable}.#{ruby.split('#').last}" }
      ["#{variable}:#{method}", found.empty? ? nil : found.uniq]
    end
    functions.merge(methods)
  end

  # Lota::Module for one of LÖVE's modules, or Lota.name for a callback.
  def module_or_callback(name)
    ruby = NAMES.find { |love, _| love.start_with?("love.#{name}.") }&.last
    ruby ? ruby[/\ALota(?:::[A-Z]\w*)+?(?=[.:#])/] : "Lota.#{name}"
  end

  # Each Lota name in +lota+: module functions and constructors, callbacks
  # (not Ruby's own Module methods, such as respond_to?), and calls on a
  # variable the LÖVE side calls a method on.
  def lota_names(lota, love)
    functions = lota.scan(LOTA_FUNCTION).map do |path, function, writer|
      function ? "Lota#{path}.#{function}#{'=' if writer}" : "Lota#{path}"
    end
    callbacks = lota.scan(LOTA_CALLBACK).flatten.reject { |name| Module.method_defined?(name) }.map { |name| "Lota.#{name}" }
    variables = love.scan(LOVE_METHOD).map(&:first).uniq
    methods = variables.flat_map do |variable|
      lota.scan(/\b#{variable}\.(\w+[?!]?)(\s*=(?![=~>]))?/).map { |method, writer| "#{variable}.#{method}#{'=' if writer}" }
    end
    functions + callbacks + methods
  end
end
