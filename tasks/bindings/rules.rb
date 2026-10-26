# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Bindings
  # ADR 001's translation rules, applied to one LÖVE function.
  #
  # The rules turn every LÖVE name into a Ruby one without a decision per
  # function (ADR 001, section 7): newSpriteBatch becomes SpriteBatch.new,
  # setTitle becomes title=, isDown becomes down?. Some rules read only the
  # name; others need the function's shape, which an Analysis gives: what
  # it returns, whether it takes an option table or a function. Rules
  # reports the Ruby name, the rules that gave it, and every way the
  # function fits no rule or more than one, which goes to the maintainer
  # as a question (Plan 001, story step 2), never answered here.
  class Rules
    # A function's Ruby translation.
    #
    # [scope] Where the method lives: "Lota::Graphics" for a module
    #   function, "Lota::Graphics::Texture" for a method.
    # [singleton] Whether it is a module function (Lota::Graphics.x)
    #   rather than an instance method (texture.x).
    # [name] The Ruby method name, or nil when no rule gives one.
    # [rules] The rule numbers that shaped it, in order.
    # [collisions] Collision objects: why it fits no rule or several.
    class Translation < Data.define(:scope, :singleton, :name, :rules, :collisions)
      # The method as Ruby writes it: Lota::Graphics.width,
      # Lota::Graphics::Texture#width, or Lota::Graphics::Canvas.new.
      def ruby_name
        return "#{scope}::#{name}" if name&.end_with?(".new")

        "#{scope}#{singleton ? '.' : '#'}#{name}"
      end
    end

    # Why a function fits no rule, or fits more than one.
    #
    # [kind] :no_rule, :several_rules, or :open (one rule fits but leaves
    #   a decision to make).
    # [rules] The rule numbers involved.
    # [why] A sentence for the maintainer.
    class Collision < Data.define(:kind, :rules, :why)
    end

    # The rule table's decisions that live in ADR 001's prose rather than
    # its table, each cited, so that every decision the rules depend on
    # is written down once.
    #
    # Rule 11's explicit pairs, as its examples name them:
    # love.graphics.push and pop, File:open and close.
    PAIRS = { "love.graphics.push" => "love.graphics.pop", "File:open" => "File:close" }.freeze
    # Pairs rule 11 decides against: mount and unmount, which "get no
    # block form until a game needs one" (ADR 001, section 7, after the
    # table).
    NOT_PAIRS = { "love.filesystem.mount" => "love.filesystem.unmount" }.freeze
    # Verbs that often open and close a pair, to find pairs rule 11 has
    # not decided.
    ANTONYMS = {
      "push" => "pop",
      "open" => "close",
      "mount" => "unmount",
      "lock" => "unlock",
      "begin" => "end",
      "start" => "stop",
      "attach" => "detach",
      "acquire" => "release",
      "enable" => "disable",
      "map" => "unmap",
      "grab" => "ungrab",
      "play" => "stop",
    }.freeze
    # Rule 2's module factories whose === the ADR decides: Canvas ===
    # texture asks texture.canvas? (rule 2's text).
    MODULE_FACTORY_MATCHES = { "newCanvas" => "Texture:isCanvas" }.freeze
    # Rule 7's setters, as ADR 001 lists them after the table.
    RULE_7_SETTERS = %w[
      setMode
      setFullscreen
      setVibration
      setIcon
      setRelativeMode
      setEffect
      setFilter
      setOutputSpatialization
      setMixWithSystem
      setBuffer
      setGamepadMapping
].freeze

    # Ruby's keywords, which no method defined with def can be called by
    # without a receiver.
    KEYWORDS = %w[
      alias
      and
      begin
      break
      case
      class
      def
      defined?
      do
      else
      elsif
      end
      ensure
      false
      for
      if
      in
      module
      next
      nil
      not
      or
      redo
      rescue
      retry
      return
      self
      super
      then
      true
      undef
      unless
      until
      when
      while
      yield
].freeze

    # Rule 1: a LÖVE module's Ruby module.
    def self.module_constant(module_name)
      "Lota::#{module_name.capitalize}"
    end

    # Rule 13: a camelCase name in snake_case. An acronym stays one word
    # (getDPIScale becomes dpi_scale), as Lota's hand-written bindings
    # spell set_high_dpi_allowed.
    def self.snake_case(name)
      name.gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    # Whether rule 13 leaves the spelling open: the name runs capitals
    # together (DPIScale) or puts one after a digit (texture2D), where
    # word boundaries are a judgment, not a rule.
    def self.ambiguous_case?(name)
      snake_case(name) != run_together(name)
    end

    # The other reading of rule 13: a capital starts a word only after a
    # lower-case letter or a digit, so capitals run together (getDPIScale
    # becomes get_dpiscale).
    def self.run_together(name)
      name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end

    # [types] The class names LÖVE registers, with their modules.
    def initialize(types:)
      @types = types
    end

    # The Translation of +function+ (a Catalog::LoveFunction or
    # LuaFunctions::Function), whose shape +analysis+ gives, or nil for a
    # function the analysis could not read or that is defined in Lua.
    def translate(function, analysis)
      Translator.new(function, analysis, @types).translation
    end

    # Applies the rules to one function.
    class Translator
      def initialize(function, analysis, types)
        @function = function
        @analysis = analysis&.readable? ? analysis : nil
        @facts = analysis
        @types = types
        @name = function.lua_name
        @rules = [1]
        @collisions = []
      end

      def translation
        name = base_name
        shape_rules
        Translation.new(scope:, singleton: @function.type_name.nil?, name:, rules: @rules.uniq,
          collisions: @collisions)
      end

      private def scope
        constant = Rules.module_constant(@function.module_name)
        @function.type_name ? "#{constant}::#{@function.type_name}" : constant
      end

      private def base_name
        return no_rule("is a Lua metamethod, which no rule maps to a Ruby operator") if @name.start_with?("__")
        return no_rule("starts with an underscore, which marks a hook for LÖVE's own Lua wrapper") if @name.start_with?("_")
        return factory(Regexp.last_match(1)) if @name =~ /\Anew([A-Z]\w*)\z/
        return getter(Regexp.last_match(1)) if @name =~ /\Aget([A-Z]\w*)\z/
        return setter(Regexp.last_match(1)) if @name =~ /\Aset([A-Z]\w*)\z/
        return predicate(Regexp.last_match(2)) if @name =~ /\A(is|has|are)([A-Z]\w*)\z/

        @rules << 13
        spelled(@name)
        Rules.snake_case(@name)
      end

      # Rule 2.
      private def factory(class_name)
        @rules << 2
        made = made_type
        if @types.key?(class_name)
          if made && made != class_name && !@types.key?(made)
            several([2], "#{class_name} is a LÖVE class, but #{@name} pushes a #{made}")
          elsif made && made != class_name
            several([2], "rule 2 makes it #{class_name}.new, but it returns a #{made}, another LÖVE class")
          end
        elsif !MODULE_FACTORY_MATCHES.key?(@name)
          note = made ? "it returns a #{made}" : "the analysis cannot tell what it returns"
          open_question([2], "LÖVE has no #{class_name} class, so rule 2 makes #{class_name} a module, " \
            "and no rule says what #{class_name} === asks (#{note})")
        end
        "#{class_name}.new"
      end

      # Rules 3 and 4.
      private def getter(rest)
        @rules << 3
        @rules << 4 if results > 1
        spelled(rest)
        Rules.snake_case(rest)
      end

      # Rules 5, 6, and 7.
      private def setter(rest)
        spelled(rest)
        snake = Rules.snake_case(rest)
        if returns_value?
          @rules << 7
          several([5, 7], "returns a value from some forms and nothing from others") if @analysis&.counts&.include?(0)
          "set_#{snake}"
        else
          @rules << ((arguments > 1) ? 6 : 5)
          writer_collisions
          "#{snake}="
        end
      end

      # Rule 8.
      private def predicate(rest)
        @rules << 8
        spelled(rest)
        if @analysis && results > 1
          several([4, 8], "a predicate that returns #{results} values")
        elsif @analysis && non_boolean_result
          several([8], "a predicate whose result is not true or false (#{non_boolean_result})")
        end
        "#{Rules.snake_case(rest)}?"
      end

      # Rules 9, 10, 12, and 14 read what a function reads, which an
      # analysis gives even for a function it cannot read whole; the
      # results rules 4 and 7 need come only from a readable one.
      private def shape_rules
        return unless @facts

        @rules << 9 if @facts.enums.any? || @facts.enum_results.any?
        option_tables
        functions
        @rules << 14 if @facts.reads.any? { |read| %i[number integer].include?(read.kind) } ||
          @facts.pushes.any? { |push| %i[number integer].include?(push.kind) }

        several_results if @analysis
      end

      private def option_tables
        keyed = @facts.tables.select(&:key).map(&:index).grep(Integer).uniq
        return if keyed.empty?

        @rules << 10
        return unless @analysis

        last = @analysis.indices.grep(Integer).max
        keyed.each do |index|
          next if index == last

          several([10], "takes an option table at argument #{argument_label(index)} but reads arguments after it, " \
            "and Ruby's keyword arguments come last")
        end
      end

      private def functions
        count = (@facts.reads.select { |read| read.kind == :function }.map(&:index) +
          @facts.tests.select { |test| test.predicate == "lua_isfunction" }.map(&:index)).uniq.size
        return if count.zero?

        @rules << 12
        several([12], "takes #{count} functions, and a Ruby method takes one block") if count > 1
      end

      private def several_results
        return if results <= 1 || @rules.intersect?([3, 7, 8])

        no_rule("returns #{results} values, and rule 4 turns several values into an Array only for getters")
      end

      private def writer_collisions
        return unless @facts

        if @facts.tables.any?(&:key)
          several([5, 10], "a writer takes one value, so it cannot take keyword arguments for its option table")
        end
        return unless @facts.reads.any? { |read| read.kind == :function }

        several([5, 12], "a writer cannot take a block")
      end

      # Rule 13's spelling, for the part of the name a rule keeps.
      private def spelled(rest)
        return unless Rules.ambiguous_case?(rest)

        open_question([13], "rule 13 does not say where #{rest}'s capitals split into words: " \
          "#{Rules.snake_case(rest)}, as set_high_dpi_allowed splits them, or #{Rules.run_together(rest)}, " \
          "with the capitals run together")
      end

      private def made_type
        return nil unless @analysis

        @analysis.pushes.select { |push| push.kind == :object }.map do |push|
          @analysis.type_of(push.expression.split(",").first.to_s.strip)
        end.compact.first
      end

      private def returns_value?
        return @function.lua_name.then { |name| RULE_7_SETTERS.include?(name) } unless @analysis

        @analysis.pushes.any? { |push| !(push.kind == :argument && push.expression.strip == "1") } &&
          @analysis.result_count.positive?
      end

      private def results
        @analysis ? @analysis.result_count : 0
      end

      private def arguments
        return 1 unless @analysis

        indices = @analysis.indices
        own = @function.type_name ? indices - [1] : indices
        (own.include?(:varargs) || @analysis.tables.any? { |table| table.access == "lua_rawgeti" }) ? 2 : own.size
      end

      private def non_boolean_result
        kinds = @analysis.pushes.map(&:kind).uniq - [:boolean]
        kinds.empty? ? nil : kinds.join(", ")
      end

      private def argument_label(index)
        @function.type_name ? index - 1 : index
      end

      private def no_rule(why)
        @collisions << Collision.new(kind: :no_rule, rules: [], why:)
        nil
      end

      private def several(rules, why)
        @collisions << Collision.new(kind: :several_rules, rules:, why:)
      end

      private def open_question(rules, why)
        @collisions << Collision.new(kind: :open, rules:, why:)
      end
    end
  end
end
