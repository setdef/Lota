# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "analysis"
require_relative "catalog"
require_relative "lua_functions"
require_relative "rules"

module Bindings
  # LÖVE's whole Lua API, read and translated.
  #
  # Each story binds a few more LÖVE functions, and each first asks which
  # of them fit no rule or several (Plan 001, story step 2). Answering for
  # one function at a time misses what only shows across the API: two
  # functions that translate to one Ruby name, or a verb pair that rule 11
  # has not decided. Survey reads every function once, from the wrap files
  # and the wrap Lua, translates it, and then looks across the results.
  class Survey
    # One function of the API.
    #
    # [function] A Catalog::LoveFunction or LuaFunctions::Function.
    # [analysis] Its Analysis, or nil for a function with no C++ body in a
    #   wrap file.
    # [translation] Its Rules::Translation.
    # [source] :cpp (a wrap_*.cpp function), :lua (a wrap_*.lua function),
    #   or :outside (a table entry whose C++ is outside the wrap files).
    class Entry < Data.define(:function, :analysis, :translation, :source)
      # Whether the parser read this function.
      def readable?
        source == :cpp && analysis.readable?
      end

      # Every collision, the translation's and the survey's.
      def collisions
        translation.collisions
      end
    end

    attr_reader :catalog, :entries

    # Surveys the LÖVE checkout at +root+.
    def self.load(root)
      new(Catalog.load(root), LuaFunctions.load(root))
    end

    # [catalog] A Catalog.
    # [lua_functions] LuaFunctions::Function objects.
    def initialize(catalog, lua_functions)
      @catalog = catalog
      rules = Rules.new(types: catalog.types)
      @entries = catalog.functions.map { |function| cpp_entry(function, rules) } +
        lua_functions.map { |function| Entry.new(function:, analysis: nil, translation: rules.translate(function, nil), source: :lua) }
      across
    end

    # The entry for +love_name+ (love.graphics.getWidth, Texture:isCanvas).
    def [](love_name)
      @by_name ||= entries.group_by { |entry| entry.function.love_name }
      @by_name.fetch(love_name) { raise KeyError, "LÖVE has no function #{love_name} in its wrap files" }.first
    end

    private def cpp_entry(function, rules)
      return Entry.new(function:, analysis: nil, translation: rules.translate(function, nil), source: :outside) unless function.definition

      analysis = Analysis.new(function.definition, function.wrap.source, helpers: catalog.helpers)
      Entry.new(function:, analysis:, translation: rules.translate(function, analysis), source: :cpp)
    end

    # The collisions that only show across functions.
    private def across
      clashes
      ruby_methods
      pairs
    end

    # Two LÖVE functions that become one Ruby name in one place. LÖVE's
    # Lua functions often replace a C++ one of the same name, which is no
    # clash.
    private def clashes
      named = entries.select { |entry| entry.translation.name }
      named.group_by { |entry| entry.translation.ruby_name }.each_value do |group|
        names = group.map { |entry| entry.function.lua_name }.uniq
        next if names.size < 2

        group.each do |entry|
          others = (names - [entry.function.lua_name]).join(", ")
          add(entry, :several_rules, [13], "becomes #{entry.translation.ruby_name}, as #{others} does too")
        end
      end
    end

    # A name Ruby already gives every object or module, or a keyword.
    private def ruby_methods
      object = Object.public_instance_methods.map(&:to_s)
      mod = Module.public_instance_methods.map(&:to_s)
      entries.each do |entry|
        name = entry.translation.name or next
        builtin = entry.translation.singleton ? mod : object
        owner = entry.translation.singleton ? "Module" : "Object"
        if builtin.include?(name)
          add(entry, :several_rules, [13], "becomes #{name}, which overrides #{owner}##{name}, and Ruby the " \
            "language comes before the rules (AGENTS.md, design precedence)")
        elsif Rules::KEYWORDS.include?(name)
          add(entry, :several_rules, [13], "becomes #{name}, a Ruby keyword")
        elsif !entry.translation.singleton && Rules::OBJECT_METHODS.include?(name)
          add(entry, :several_rules, (entry.translation.rules & [3, 13]) + [16],
            "becomes #{name}, which rule 16 gives every LÖVE object for Object:type and Object:typeOf")
        end
      end
    end

    # Verbs that open and close a pair in one place (rule 11).
    private def pairs
      entries.group_by { |entry| entry.translation.scope + (entry.translation.singleton ? "." : "#") }.each_value do |group|
        names = group.map { |entry| entry.function.lua_name }
        Rules::ANTONYMS.each do |opener, closer|
          group.select { |entry| verb(entry, opener) }.each do |entry|
            rest = entry.function.lua_name.delete_prefix(opener)
            next unless names.include?("#{closer}#{rest}")

            pair(entry, opener, closer, rest)
          end
        end
      end
    end

    private def pair(entry, opener, closer, rest)
      opening = entry.function.love_name
      closing = opening.sub(/(?<=[.:])#{opener}#{rest}\z/, "#{closer}#{rest}")
      return if Rules::NOT_PAIRS[opening] == closing

      if Rules::PAIRS[opening] == closing
        returns = entry.analysis&.pushes&.reject { |push| push.kind == :argument }&.map(&:kind)&.uniq
        return if returns.nil? || returns.empty?

        add(entry, :several_rules, [11], "opens a rule 11 pair but returns #{returns.join(', ')}, so the block " \
          "form has nothing to yield when it fails without raising")
      else
        add(entry, :open, [11], "#{opener}#{rest} and #{closer}#{rest} may be an explicit pair, which rule 11 " \
          "has not decided")
      end
    end

    private def verb(entry, opener)
      entry.function.lua_name.match?(/\A#{opener}(?:[A-Z]\w*)?\z/)
    end

    private def add(entry, kind, rules, why)
      entry.translation.collisions << Rules::Collision.new(kind:, rules:, why:)
    end
  end
end
