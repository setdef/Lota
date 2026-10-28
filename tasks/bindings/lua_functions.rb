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
  # says what they read. Others replace a C++ wrap function of the same
  # name, as SoundData:getSample's LuaJIT code replaces
  # w_SoundData_getSample, once the file's guards pass: LÖVE's builds run
  # LuaJIT with its compiler on and its FFI loaded, so a game runs the Lua,
  # and Lota ports the Lua rather than the C++ (ADR 001, section 7).
  # LuaFunctions lists them, by name and parameter list, with the guards
  # each runs behind, for the rules, the generator, and the report; Lota
  # ports them by hand.
  module LuaFunctions
    # A function defined in a wrap_*.lua file.
    #
    # [guards] What must hold for LÖVE to define it, in words, in the
    #   order the file checks them: each early return of the file before
    #   the definition, such as "LuaJIT's compiler is on". Empty when the
    #   file always defines it.
    class Function < Data.define(:module_name, :type_name, :lua_name, :parameters, :file, :line, :guards)
      # Its name in LÖVE's own notation.
      def love_name
        type_name ? "#{type_name}:#{lua_name}" : "love.#{module_name}.#{lua_name}"
      end

      # Where it is defined, as path:line.
      def location
        "#{file}:#{line}"
      end

      # When LÖVE defines it, as a phrase: "always", or "when" and its
      # guards.
      def condition
        return "always" if guards.empty?

        "when #{(guards.size > 1) ? "#{guards[0..-2].join(', ')}, and #{guards.last}" : guards.first}"
      end
    end

    DEFINITION = /^\s*function\s+(?<table>[\w.]+)(?<separator>[.:])(?<name>\w+)\s*\((?<parameters>[^)]*)\)/
    # A statement at the file's top level that opens an if block.
    GUARD = /\Aif\s+(?<condition>.+?)\s+then\b(?<rest>.*)\z/
    # A library loaded with pcall, whose status a later guard tests.
    LOADED = /\Alocal\s+(?<status>\w+)\s*,\s*\w+\s*=\s*pcall\(\s*require\s*,\s*"(?<library>\w+)"\s*\)/
    # What a guard's condition tests, in words.
    TESTS = {
      /\btype\(jit\)\s*~=\s*"table"/ => "LÖVE runs on LuaJIT",
      /\bjit\.status\(\)/ => "LuaJIT's compiler is on",
    }.freeze

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
      guards = []
      libraries = {}
      lines = text.lines(chomp: true)
      lines.each_with_index.filter_map do |line, index|
        if (loaded = LOADED.match(line))
          libraries[loaded[:status]] = loaded[:library]
        elsif (guard = GUARD.match(line)) && returns?(guard, lines, index)
          guards.concat(tested(guard[:condition], libraries))
        end
        match = DEFINITION.match(line) or next
        table = match[:table].split(".").last
        type_name = table.match?(/\A[A-Z]/) ? table : nil
        Function.new(module_name:, type_name:, lua_name: match[:name],
          parameters: match[:parameters].split(",").map(&:strip).reject(&:empty?), file: path, line: index + 1,
          guards: guards.uniq)
      end
    end

    # Whether the top-level if block +guard+ opens at +index+ returns from
    # the file, on its own line (if not status then return end) or in its
    # body, which ends at the next end at the top level.
    private_class_method def self.returns?(guard, lines, index)
      return guard[:rest].match?(/\breturn\b/) if guard[:rest].match?(/\bend\s*\z/)

      body = lines[(index + 1)..].take_while { |line| !line.match?(/\Aend\b/) }
      body.any? { |line| line.match?(/\A\s*return\s*\z/) }
    end

    # What +condition+, a guard's, needs to be false, in words: LuaJIT, its
    # compiler, or each library whose pcall status it tests.
    private_class_method def self.tested(condition, libraries)
      words = TESTS.filter_map { |pattern, phrase| phrase if condition.match?(pattern) }
      words + libraries.filter_map do |status, library|
        next unless condition.match?(/\bnot\s+#{status}\b/)

        (library == "ffi") ? "LuaJIT's FFI loads" : "LuaJIT's #{library} library loads"
      end
    end
  end
end
