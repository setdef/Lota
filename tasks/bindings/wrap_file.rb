# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "cpp_source"

module Bindings
  # One of LÖVE's wrap_*.cpp files, read for what it registers with Lua.
  #
  # A wrap file defines C++ functions that take a lua_State, lists them in
  # luaL_Reg tables under their Lua names, and registers each table either
  # as a module's functions (a WrappedModule, in luaopen_love_*) or as a
  # type's methods (luax_register_type). WrapFile finds all three, by the
  # exact shapes LÖVE writes them in, and keeps their line numbers.
  class WrapFile
    # A function that takes a lua_State first.
    #
    # [name] Its C++ name (w_getWidth).
    # [signature] Its parameter list, lua_State first.
    # [body] Its body, between the braces, comments blanked.
    # [body_offset] Where the body starts in the file.
    # [line] The line its definition starts on.
    # [end_line] The line of its closing brace.
    class Function < Data.define(:name, :signature, :body, :body_offset, :line, :end_line)
    end

    # A luaL_Reg table's entry: a Lua name and the C++ function it calls.
    class Entry < Data.define(:lua_name, :cpp_name, :line)
    end

    # A luaL_Reg table.
    class Table < Data.define(:name, :entries, :line)
    end

    # A luax_register_type call: a type and the tables of its methods, in
    # the order LÖVE merges them (inherited tables first).
    class TypeRegistration < Data.define(:type_name, :tables, :line)
    end

    FUNCTION = /
      ^[ \t]*(?:extern\s+"C"\s+)?(?:static\s+)?(?:inline\s+)?(?:LOVE_EXPORT\s+)?
      (?<return>[\w:<>]+(?:\s*[*&])?)\s*(?<pointer>[*&]?)\s*
      (?<name>[A-Za-z_]\w*)\s*\(\s*(?<signature>lua_State\s*\*[^()]*)\)\s*\{
    /x
    TABLE = /\bluaL_Reg\s+(?<name>\w+)\s*\[\s*\]\s*=\s*\{/
    ENTRY = /\{\s*"(?<lua>[^"]+)"\s*,\s*(?<cpp>[\w:]+)\s*\}/
    REGISTER_TYPE = /\bluax_register_type\s*\(\s*L\s*,\s*&\s*(?<type>[\w:]+)::type\s*(?<tables>(?:,\s*[\w:]+\s*)*)\)/
    MODULE_NAME = /\bw\.name\s*=\s*"(?<name>\w+)"\s*;/
    MODULE_FUNCTIONS = /\bw\.functions\s*=\s*(?<table>\w+)\s*;/

    attr_reader :source

    # [source] The file, as a CppSource.
    def initialize(source)
      @source = source
    end

    # The file's path, as reports name it.
    def path
      @source.path
    end

    # The LÖVE module the file belongs to: the directory under
    # src/modules ("physics" for src/modules/physics/box2d/wrap_Body.cpp).
    def module_name
      path[%r{(?:\A|/)modules/(\w+)/}, 1]
    end

    # Every function in the file that takes a lua_State first, by name.
    def functions
      @functions ||= text.to_enum(:scan, FUNCTION).map { function(Regexp.last_match) }
    end

    # Every luaL_Reg table in the file, by name.
    def tables
      @tables ||= text.to_enum(:scan, TABLE).to_h do
        match = Regexp.last_match
        close = Statements.matching(text, match.end(0) - 1)
        entries = text[(match.end(0))...close].to_enum(:scan, ENTRY).map do
          entry = Regexp.last_match
          Entry.new(lua_name: entry[:lua], cpp_name: entry[:cpp].split("::").last,
            line: @source.line_of(match.end(0) + entry.begin(0)))
        end
        [match[:name], Table.new(name: match[:name], entries:, line: @source.line_of(match.begin(0)))]
      end
    end

    # The module this file registers ("graphics"), with the name of its
    # functions table, or nil when it registers none.
    def module_registration
      name = text[MODULE_NAME, :name]
      table = text[MODULE_FUNCTIONS, :table]
      name && table && [name, table]
    end

    # The class LÖVE's instance() macro names in this file
    # (Module::getInstance<Timer>), or nil when the file defines none.
    def instance_class
      @source.raw[/#define\s+instance\(\)\s*\(\s*Module::getInstance<\s*([\w:]+)\s*>/, 1]&.split("::")&.last
    end

    # The types this file registers.
    def type_registrations
      text.to_enum(:scan, REGISTER_TYPE).map do
        match = Regexp.last_match
        tables = match[:tables].split(",").map(&:strip).reject { |name| name.empty? || name == "nullptr" }
        TypeRegistration.new(type_name: match[:type].split("::").last, tables: tables.map { |name| name.split("::").last },
          line: @source.line_of(match.begin(0)))
      end
    end

    private def text
      @source.text
    end

    private def function(match)
      open = match.end(0) - 1
      close = Statements.matching(text, open)
      Function.new(name: match[:name], signature: match[:signature].strip, body: text[(open + 1)...close],
        body_offset: open + 1, line: @source.line_of(match.begin(:return)), end_line: @source.line_of(close))
    end
  end
end
