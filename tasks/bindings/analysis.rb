# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "calls"
require_relative "statements"

module Bindings
  # What one wrap function reads, returns, and raises, read from its body.
  #
  # A wrap function is the specification of a binding (ADR 001, section
  # 4): its luaL_check* and luaL_opt* calls are the arguments and their
  # defaults, its lua_push* calls the results, its luaL_error and
  # luax_enumerror calls the errors. Analysis reads those calls by the
  # patterns LÖVE writes them in. Where a body does something those
  # patterns do not cover, such as reading an argument at a position it
  # computes at run time, the analysis records a problem instead of
  # guessing, and the function counts as unreadable.
  class Analysis
    # One read of an argument.
    #
    # [index] Its position on the Lua stack, counting from 1, or :varargs
    #   for each of a run of arguments.
    # [reader] The function that reads it (luaL_checknumber).
    # [kind] What it reads: :number, :integer, :string, :boolean, :truthy,
    #   :object, :variant, :function, :table, :userdata, :converted, or
    #   :helper (a LÖVE helper that reads a value of its own kind).
    # [type] The class an :object read checks for, the helper of a
    #   :helper read, or the function a :converted read goes through.
    # [default] The default an optional read falls back on, as C++ text.
    # [cast] The C++ type the value is converted to, when LÖVE casts it or
    #   declares a variable of that type for it.
    # [line] Where the read is.
    class Read < Data.define(:index, :reader, :kind, :type, :default, :cast, :line)
      # Whether the read accepts a missing argument.
      def optional?
        reader.match?(/opt|\Alua_to|\Aluax_to/) || !default.nil?
      end
    end

    # A test of what an argument is, which picks among a function's forms.
    class Test < Data.define(:index, :predicate, :type, :line)
    end

    # One table an argument is read as: an array (lua_rawgeti) or a table
    # of options (lua_getfield and LÖVE's *flag helpers).
    class TableRead < Data.define(:index, :access, :key, :line)
    end

    # One result pushed onto the stack.
    class Push < Data.define(:pusher, :kind, :expression, :line)
    end

    # An error the function raises itself.
    #
    # [kind] :error (luaL_error), :enum (luax_enumerror), :argument
    #   (luaL_argerror), :type (luax_typerror), or :exception (a
    #   love::Exception thrown in the body).
    class Error < Data.define(:kind, :message, :line)
    end

    # A value of an enum: an argument checked by getConstant, or a result
    # named by it.
    class EnumUse < Data.define(:index, :enum_type, :label, :line)
    end

    NUMBER = %w[
      luaL_checknumber
      luaL_optnumber
      luax_checkfloat
      luax_tofloat
      lua_tonumber
      luax_checknumberclamped
      luax_optnumberclamped
      luax_checknumberclamped01
      luax_optnumberclamped01
].freeze
    INTEGER = %w[luaL_checkinteger luaL_optinteger luax_checkint luax_optint luax_toint lua_tointeger].freeze
    STRING = %w[
      luaL_checkstring
      luaL_checklstring
      luaL_optstring
      luaL_optlstring
      luax_checkstring
      luax_tostring
      lua_tostring
      lua_tolstring
].freeze
    READERS = {
      **NUMBER.to_h { |name| [name, :number] },
      **INTEGER.to_h { |name| [name, :integer] },
      **STRING.to_h { |name| [name, :string] },
      "luax_checkboolean" => :boolean,
      "luax_optboolean" => :boolean,
      "luax_toboolean" => :truthy,
      "lua_toboolean" => :truthy,
      "luax_checktype" => :object,
      "luax_totype" => :object,
      "luax_checkvariant" => :variant,
      "lua_touserdata" => :userdata,
      "luaL_checkany" => :any,
      "luax_convobj" => :converted,
      "luax_pconvobj" => :converted,
    }.freeze
    TESTS = %w[
      lua_isnoneornil
      lua_isnone
      lua_isnil
      lua_isnumber
      lua_isstring
      lua_istable
      lua_isboolean
      lua_isfunction
      lua_isuserdata
      lua_islightuserdata
      lua_type
      luax_istype
      luax_isarrayoftables
      luax_cangetfile
      luax_cangetfiledata
      luax_cangetdata
      luaL_checktype
].freeze
    TABLE_READS = %w[
      lua_rawgeti
      lua_getfield
      lua_rawget
      lua_gettable
      lua_next
      luax_objlen
      lua_objlen
      luax_boolflag
      luax_intflag
      luax_numberflag
      luax_checkboolflag
      luax_checkintflag
      luax_checktablefields
].freeze
    TABLE_WRITES = %w[lua_rawseti lua_setfield lua_settable lua_rawset].freeze
    STACK = %w[lua_pop lua_remove lua_insert lua_replace lua_settop lua_gettop lua_checkstack luax_assert_argc].freeze
    ERRORS = %w[luaL_error luax_enumerror luaL_argerror luax_typerror lua_error luaL_typerror].freeze
    PUSHERS = /\A(?:lua_push\w+|luax_push\w+|lua_createtable|lua_newtable)\z/
    LUA_CALLS = %w[
      lua_call
      lua_pcall
      luaL_loadbuffer
      luaL_loadbufferx
      lua_cpcall
      luax_getfunction
      luax_runwrapper
      luax_refif
      luax_insist
      luax_insistglobal
      luax_insistlove
      luax_getlove
      luax_insistregistry
      luax_getregistry
      luax_getpinnedthread
      luax_insistpinnedthread
      luax_resume
      lua_pushcclosure
      lua_pushcfunction
].freeze
    KNOWN = %w[luax_catchexcept luax_markdeprecated luax_getmodule luax_optmodule luax_checkgraphicscreated].freeze
    HELPER_READER = /\Aluax_(?:check|opt|get|to)\w+\z/
    HELPER_TEST = /\Aluax_(?:is|can)\w+\z/
    RETURN_ERRORS = /\A(?:luaL_error|luax_enumerror|luaL_argerror|luax_typerror|lua_error|luax_effecterror)\s*\(/

    attr_reader :reads, :tests, :tables, :pushes, :counts, :errors, :enums, :enum_results, :engine_calls,
      :deprecation, :delegate, :problems, :count_tests, :statements

    # [function] The WrapFile::Function to read.
    # [source] Its file's CppSource, for line numbers.
    # [helpers] A Hash of LÖVE's luax_check* helpers by name, to the class
    #   each checks for (luax_checktexture to Texture).
    def initialize(function, source, helpers: {})
      @function = function
      @source = source
      @helpers = helpers
      @reads = []
      @tests = []
      @tables = []
      @pushes = []
      @counts = []
      @errors = []
      @enums = []
      @enum_results = []
      @engine_calls = []
      @problems = []
      @count_tests = false
      @variables = {}
      @constants = {}
      @types = {}
      analyze
    end

    # Whether every part of the body fits a pattern the analysis reads.
    def readable?
      problems.empty?
    end

    # The positions the function reads, in order, with :varargs last.
    def indices
      positions = (reads + tests + tables).map(&:index).uniq
      positions.grep(Integer).sort + (positions.include?(:varargs) ? [:varargs] : [])
    end

    # The C++ type LÖVE declares +variable+ with, as written (Colorf,
    # "const char*"), or nil.
    def declared_type(variable)
      @types[variable.to_s.strip]
    end

    # The class or type LÖVE declares +variable+ with, without const,
    # pointers, or namespaces (Texture for "Texture *t"), or nil.
    def type_of(variable)
      @types[variable.to_s.strip]&.then { |type| type.delete("*&").sub(/\Aconst\s+/, "").strip.split("::").last }
    end

    # The most values one call returns.
    def result_count
      counts.max || 0
    end

    private def analyze
      @statements = Statements.parse(@function.body, @function.body_offset, @source)
      @tables_read = @function.body.match?(/\b(?:#{TABLE_READS.join('|')})\s*\(/o)
      walk(@statements, [])
      @problems << "returns no literal count of values" if counts.empty? && delegate.nil? && @problems.empty?
    rescue Statements::Unreadable => e
      @problems << "has a statement the parser does not read (#{e.message})"
    end

    private def walk(nodes, loops)
      nodes.each do |node|
        case node.kind
        when :loop then loop_node(node, loops)
        when :return then return_node(node, loops)
        when :if
          @branch = node.body.flat_map { |inner| inner.each_node.map(&:text) }.join("\n")
          expression(node.text, node.line, loops, condition: true)
          @branch = nil
        when :switch then expression(node.text, node.line, loops, condition: true)
        when :expression, :catch then statement(node, loops)
        end
        walk(node.body, loops) unless node.kind == :loop
        walk(node.alternative, loops)
      end
    end

    private def loop_node(node, loops)
      expression(node.text, node.line, loops, condition: true)
      variable = node.text[/\A\s*(?:int|size_t|lua_Integer|auto)?\s*(\w+)\s*=/, 1] ||
        node.text[/\A\s*(\w+)\s*(?:<|<=|>|>=)/, 1]
      varargs = node.text.include?("lua_gettop(L)") || @variables.fetch(node.text[/[<>]=?\s*(\w+)/, 1], nil) == :top
      walk(node.body, loops + [[variable, varargs]])
    end

    # A luax_catchexcept lambda's own statements are walked as its body.
    private def statement(node, loops)
      return if node.kind == :catch

      declare(node.text)
      expression(node.text, node.line, loops)
    end

    private def return_node(node, loops)
      text = node.text
      if text.match?(/\A\d+\z/)
        counts << text.to_i
      elsif text.match?(RETURN_ERRORS)
        expression(text, node.line, loops)
      elsif (target = text[/\A(w_\w+)\s*\(\s*L\s*\)\z/, 1])
        @delegate = target
      else
        expression(text, node.line, loops)
        @problems << "returns a computed number of values (return #{text})"
      end
    end

    # Records what +text+'s declaration or assignment makes of a variable.
    private def declare(text)
      match = text.match(/\A(?:const\s+)?(?<type>[\w:]+(?:\s*<[^;=]*?>)?(?:\s*[*&]+\s*|\s+))(?<name>\w+)\s*(?:=\s*(?<value>.+)|\((?<value>.+)\))?\z/m)
      match ||= text.match(/\A(?<name>[\w.]+)\s*=\s*(?<value>.+)\z/m)
      return unless match

      @types[match[:name]] = match[:type].strip.squeeze(" ") if match.names.include?("type") && match[:type]
      value = match[:value].to_s
      @constants[match[:name]] = @constants.key?(match[:name]) ? nil : value if value.match?(/\A\d+\z/)
      @constants[match[:name]] = nil if @constants.key?(match[:name]) && !value.match?(/\A\d+\z/)
      @variables[match[:name]] = :top if value.include?("lua_gettop(L)")
      read = Calls.in(value).find { |call| call.lua? && READERS.key?(call.base_name) }
      @variables[match[:name]] = read.arguments[1] if read
    end

    private def expression(text, line, loops, condition: false)
      @count_tests = true if condition && text.include?("lua_gettop(L)")
      Calls.in(text).each { |call| call(call, text, line, loops) }
      lua_state_passed(text, line)
      throws(text, line)
    end

    private def call(call, text, line, loops)
      return engine_call(call) if call.member && !call.lua?
      return enum_check(call, text, line) if call.base_name == "getConstant"
      return unless call.lua?

      name = call.base_name
      return @deprecation = call.arguments[2]&.delete('"') if name == "luax_markdeprecated"
      return if KNOWN.include?(name)

      if READERS.key?(name) || (name == "luaL_checktype" && call.arguments[2] != "LUA_TFUNCTION")
        read(call, text, line, loops)
      elsif TESTS.include?(name) || name.match?(HELPER_TEST)
        test(call, line, loops)
      elsif TABLE_READS.include?(name) then table(call, line, loops)
      elsif name.match?(PUSHERS) then push(call, line)
      elsif ERRORS.include?(name) then error(call, line)
      elsif LUA_CALLS.include?(name) then @problems << "calls back into Lua (#{name}, line #{line})"
      elsif @helpers.key?(name) || name.match?(HELPER_READER) then read(call, text, line, loops)
      elsif !(TABLE_WRITES + STACK).include?(name)
        @problems << "passes the lua_State to #{name} (line #{line}), which the parser does not read"
      end
    end

    private def read(call, text, line, loops)
      name = call.base_name
      index = position(call.arguments[1], line, loops) or return
      kind, type = read_kind(call)
      default = name.match?(/opt/) ? call.arguments.last : nil
      cast = text[/\(\s*([\w:]+)\s*\)\s*#{Regexp.escape(call.name)}\s*\(/, 1]
      reads << Read.new(index:, reader: name, kind:, type:, default:, cast:, line:)
    end

    private def read_kind(call)
      name = call.base_name
      return [READERS.fetch(name), call.template] if %w[luax_checktype luax_totype].include?(name)
      return [:converted, call.arguments[2..3]&.map { |arg| arg.delete('"') }&.join(".")] if READERS[name] == :converted
      return [READERS.fetch(name), nil] if READERS.key?(name)
      return [(call.arguments[2] == "LUA_TTABLE") ? :table : :any, nil] if name == "luaL_checktype"
      return [:object, @helpers.fetch(name)] if @helpers.key?(name)

      [:helper, name]
    end

    private def test(call, line, loops)
      if call.base_name == "luaL_checktype" && call.arguments[2] == "LUA_TFUNCTION"
        index = position(call.arguments[1], line, loops) or return
        return reads << Read.new(index:, reader: "luaL_checktype", kind: :function, type: nil, default: nil,
          cast: nil, line:)
      end
      index = position(call.arguments[1], line, loops) or return
      tests << Test.new(index:, predicate: call.base_name, type: call.arguments[2]&.sub(/::type\z/, ""), line:)
    end

    private def table(call, line, loops)
      index = position(call.arguments[1], line, loops) or return
      key = call.arguments[2]&.then { |arg| arg.start_with?('"') ? arg.delete('"') : nil }
      tables << TableRead.new(index:, access: call.base_name, key:, line:)
    end

    private def push(call, line)
      kind = case call.base_name
      when "lua_pushnumber" then :number
      when "lua_pushinteger" then :integer
      when "luax_pushboolean", "lua_pushboolean" then :boolean
      when "lua_pushstring", "luax_pushstring", "lua_pushlstring", "lua_pushfstring" then :string
      when "lua_pushnil" then :nil
      when "luax_pushtype" then :object
      when "lua_createtable", "lua_newtable" then :table
      when "lua_pushvalue" then :argument
      when "luax_pushvariant" then :variant
      else :helper
      end
      pushes << Push.new(pusher: call.base_name, kind:, expression: call.arguments[1..].join(", "), line:)
    end

    private def error(call, line)
      arguments = call.arguments
      kind, message = case call.base_name
      when "luaL_error" then [:error, arguments[1]]
      when "luax_enumerror" then [:enum, arguments[1]]
      when "luaL_argerror" then [:argument, arguments[2]]
      when "luax_typerror", "luaL_typerror" then [:type, arguments[2]]
      else [:error, nil]
      end
      errors << Error.new(kind:, message: message&.then { |text| literal(text) }, line:)
    end

    private def throws(text, line)
      text.scan(/\bthrow\s+(?:love::)?Exception\s*\(\s*("(?:[^"\\]|\\.)*")/) do |(message)|
        errors << Error.new(kind: :exception, message: literal(message), line:)
      end
    end

    private def enum_check(call, text, line)
      first, second = call.arguments
      index = enum_index(first)
      if index
        enums << EnumUse.new(index:, enum_type: @types[second], label: enum_label("#{text}\n#{@branch}"), line:)
      elsif @variables.key?(first) || Calls.in(first.to_s).any?(&:member) || @types.key?(first)
        enum_results << EnumUse.new(index: nil, enum_type: @types[first], label: nil, line:)
      end
    end

    private def enum_index(argument)
      return nil unless argument

      direct = Calls.in(argument).find { |call| call.lua? && READERS.key?(call.base_name) }
      value = direct ? direct.arguments[1] : @variables[argument]
      value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
    end

    private def enum_label(text)
      text[/luax_enumerror\s*\(\s*L\s*,\s*"([^"]+)"/, 1]
    end

    private def engine_call(call)
      engine_calls << "#{call.receiver}->#{call.base_name}" unless call.receiver.match?(/\A(?:std|lua)/)
    end

    # LÖVE passes L itself to a few engine functions (Graphics::present,
    # for its screenshot callbacks), which leaves Lua inside the engine.
    private def lua_state_passed(text, line)
      Calls.in(text).each do |call|
        next if call.lua?
        next unless call.arguments.include?("L")

        @problems << "passes the lua_State to #{call.base_name} (line #{line}), which the parser does not read"
      end
    end

    # The stack position +argument+ names: an Integer, :varargs for a
    # loop over every argument, or :stack for a slot relative to the top,
    # which only a table read leaves there. Records a problem and returns
    # nil for any other position.
    private def position(argument, line, loops)
      text = argument.to_s.strip
      text = @variables[text] if @variables[text].is_a?(String) && @variables[text].match?(/\A-?\d+\z/)
      text = @constants.fetch(text) if @constants[text]
      return text.to_i if text.match?(/\A\d+\z/)
      return :stack if text.match?(/\A-\d+\z/)

      loop = loops.reverse.find { |variable, _| variable && text.match?(/\b#{Regexp.escape(variable)}\b/) }
      return :varargs if loop&.last
      return :stack if loop && @tables_read

      @problems << "reads the stack at a position it computes (#{text}, line #{line})"
      nil
    end

    private def literal(text)
      text.to_s.strip.then { |value| value.start_with?('"') ? value.undump : value }
    rescue RuntimeError
      text
    end
  end
end
