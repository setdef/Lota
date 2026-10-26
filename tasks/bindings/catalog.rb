# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "cpp_source"
require_relative "statements"
require_relative "wrap_file"

module Bindings
  # Every function LÖVE registers with Lua from its wrap_*.cpp files.
  #
  # LÖVE's Lua API is spread over 74 wrap files: module functions in each
  # module's luaopen_love_* table, and methods in the tables each type
  # registers. A type's methods include tables it inherits (ImageData
  # registers Data's functions first), so a method belongs to the type
  # whose own file defines its table. The catalog lists each function
  # once, under that owner, with the C++ function that implements it.
  class Catalog
    # A function of LÖVE's Lua API.
    #
    # [module_name] The LÖVE module ("graphics" for love.graphics).
    # [type_name] The type whose method it is ("Texture"), or nil for a
    #   module function.
    # [lua_name] Its Lua name ("getWidth").
    # [file] The wrap file whose table lists it.
    # [line] The line of its table entry.
    # [definition] The WrapFile::Function that implements it, or nil when
    #   no wrap file defines it.
    # [wrap] The WrapFile that defines it.
    class LoveFunction < Data.define(:module_name, :type_name, :lua_name, :file, :line, :definition, :wrap)
      # Its name in LÖVE's own notation: love.graphics.getWidth for a
      # module function, Texture:getWidth for a method.
      def love_name
        type_name ? "#{type_name}:#{lua_name}" : "love.#{module_name}.#{lua_name}"
      end

      # Where its C++ starts, as path:line.
      def location
        definition ? "#{wrap.path}:#{definition.line}" : "#{file}:#{line}"
      end
    end

    attr_reader :files

    # [root] The LÖVE checkout (vendor/love).
    def self.load(root)
      paths = Dir.glob("src/**/wrap_*.cpp", base: root).sort
      new(paths.map { |path| WrapFile.new(CppSource.read(File.join(root, path), label: path)) })
    end

    # [files] WrapFile objects.
    def initialize(files)
      @files = files
    end

    # Every function, in file order: module functions, then methods.
    def functions
      @functions ||= module_functions + methods
    end

    # The WrapFile and WrapFile::Function named +name+, preferring
    # +near+'s own file, then its module's other files.
    def definition(name, near)
      candidates = files.flat_map { |file| file.functions.select { |fn| fn.name == name }.map { |fn| [file, fn] } }
      candidates.find { |file, _| file == near } ||
        candidates.find { |file, _| file.module_name == near.module_name } ||
        ((candidates.size == 1) ? candidates.first : nil)
    end

    # LÖVE's helpers that check an argument's class, by name, to the class
    # each checks for: luax_checktexture, whose body is
    # luax_checktype<Texture>(L, idx), to Texture.
    def helpers
      @helpers ||= files.flat_map(&:functions).filter_map do |function|
        type = function.body[/\A\s*return\s+luax_checktype\s*<\s*([\w:]+)\s*>\s*\(\s*L\s*,\s*\w+\s*\)\s*;\s*\z/, 1]
        [function.name, type.split("::").last] if type && function.name.start_with?("luax_check")
      end.to_h
    end

    # The types LÖVE registers, by name, with the module whose file
    # registers them.
    def types
      @types ||= files.flat_map do |file|
        file.type_registrations.map { |registration| [registration.type_name, file.module_name] }
      end.to_h
    end

    private def module_functions
      files.flat_map do |file|
        name, table_name = file.module_registration
        next [] unless name

        entries(file, file.tables.fetch(table_name)).map { |entry, wrap, fn| build(name, nil, entry, file, wrap, fn) }
      end
    end

    private def methods
      files.flat_map do |file|
        file.type_registrations.flat_map do |registration|
          own = registration.tables.filter_map { |name| file.tables[name] }
          own.flat_map do |table|
            entries(file, table).map do |entry, wrap, fn|
              build(file.module_name, registration.type_name, entry, file, wrap, fn)
            end
          end
        end
      end
    end

    private def entries(file, table)
      table.entries.map { |entry| [entry, *definition(entry.cpp_name, file)] }
    end

    private def build(module_name, type_name, entry, file, wrap, function)
      LoveFunction.new(module_name:, type_name:, lua_name: entry.lua_name, file: file.path, line: entry.line,
        definition: function, wrap: wrap || file)
    end
  end
end
