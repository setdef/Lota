# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Bindings
  # The functions LÖVE writes in Lua, in its wrap_*.lua files.
  #
  # Some of LÖVE's API is Lua, not C++: love.graphics.stencil,
  # RandomGenerator:random over its C++ _random, love.math.colorToBytes.
  # The wrap files load that Lua into the module or type, so those
  # functions are part of the API the rules translate, but no C++ body
  # says what they read. LuaFunctions lists them, by name and parameter
  # list, for the rules and the report; Lota ports them by hand.
  module LuaFunctions
    # A function defined in a wrap_*.lua file.
    class Function < Data.define(:module_name, :type_name, :lua_name, :parameters, :file, :line)
      # Its name in LÖVE's own notation.
      def love_name
        type_name ? "#{type_name}:#{lua_name}" : "love.#{module_name}.#{lua_name}"
      end

      # Where it is defined, as path:line.
      def location
        "#{file}:#{line}"
      end
    end

    DEFINITION = /^\s*function\s+(?<table>[\w.]+)(?<separator>[.:])(?<name>\w+)\s*\((?<parameters>[^)]*)\)/

    # Every function the wrap_*.lua files under +root+ define on a module
    # or type, once each, in file order. A file may define one twice, one
    # for LuaJIT's FFI and one without; the first counts.
    def self.load(root)
      Dir.glob("src/**/wrap_*.lua", base: root).sort.flat_map do |path|
        parse(File.read(File.join(root, path), encoding: "UTF-8"), path)
      end.uniq(&:love_name)
    end

    # The functions defined in +text+, the contents of +path+.
    def self.parse(text, path)
      module_name = path[%r{modules/(\w+)/}, 1]
      text.each_line.with_index(1).filter_map do |line, number|
        match = DEFINITION.match(line) or next
        table = match[:table].split(".").last
        type_name = table.match?(/\A[A-Z]/) ? table : nil
        Function.new(module_name:, type_name:, lua_name: match[:name],
          parameters: match[:parameters].split(",").map(&:strip).reject(&:empty?), file: path, line: number)
      end
    end
  end
end
