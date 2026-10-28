# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "analysis"
require_relative "calls"
require_relative "rules"

module Bindings
  # One wrap function, ported to a Rice binding.
  #
  # A wrap function reads its arguments from the Lua stack, calls the
  # engine, and pushes its results. A binding does the same with C++
  # parameters and a return value, so the port keeps LÖVE's own statements,
  # in LÖVE's order, and replaces only what touches Lua: a read becomes a
  # parameter, a push becomes the return value, luaL_error becomes a
  # love::Exception (which Lota's error translation passes to Ruby), and
  # luax_enumerror becomes raise_enum_error. A form the binding list
  # leaves out is pruned first, by the conditions that select it. Anything
  # else that touches Lua stops the port with Unsupported, naming it,
  # rather than guessing.
  class Port
    # A body or form the port cannot write.
    class Unsupported < StandardError; end

    # A parameter of the binding: one argument of the wrap function.
    #
    # [index] Its Lua stack position.
    # [name] Its C++ and Ruby name, in snake_case.
    # [kind] Its Analysis::Read kind.
    # [cpp] Its C++ type, before std::optional.
    # [object] The class of an :object parameter.
    # [optional] Whether the binding tests for it at run time
    #   (lua_isnoneornil), so it is a std::optional.
    # [default] The C++ literal Rice passes when it is left out, or nil.
    # [checked] Whether it is optional only because it follows an optional
    #   parameter, as a Ruby method's positional parameters must, while LÖVE
    #   reads it with a check: the form that reads it requires it.
    class Parameter < Data.define(:index, :name, :kind, :cpp, :object, :optional, :default, :checked)
      # Its C++ declaration. An optional class, such as a String, is taken
      # by reference, as the class itself is: Rice converts it once.
      def declaration
        return "const std::optional<#{base}> &#{name}" if optional && cpp.end_with?("&")
        return "std::optional<#{base}> #{name}" if optional

        cpp.end_with?("&", "*") ? "#{cpp}#{name}" : "#{cpp} #{name}"
      end

      # Its Rice::Arg, with its default.
      def rice_arg
        return %(Rice::Arg("#{name}") = std::optional<#{base}>()) if optional
        return %(Rice::Arg("#{name}") = #{default}) if default

        %(Rice::Arg("#{name}"))
      end

      # Its RBS.
      def rbs
        type = {
number: "Float | Integer",
integer: "Integer",
string: "String",
boolean: "bool",
truthy: "bool",
object:,
}.fetch(kind) { raise Unsupported, "no Ruby type for a #{kind} argument" }
        type = "(#{type})" if type.include?("|") && (optional || default)
        return "?#{type}? #{name}" if optional
        return "?#{type} #{name}" if default

        "#{type} #{name}"
      end

      # Its type without references and const, for std::optional.
      def base
        cpp.sub(/\Aconst\s+/, "").delete("&").strip
      end
    end

    INTEGRAL = /\A(?:const\s+)?(?:unsigned\s+|signed\s+)?(?:int|long|short|long long|size_t|ptrdiff_t|u?int\d+(?:_t)?|lua_Integer)\z/
    FLOATING = /\A(?:const\s+)?(?:float|double|lua_Number)\z/
    STRING_READERS = {
"luaL_checkstring" => :c_str,
"luaL_checklstring" => :c_str,
"luaL_optstring" => :c_str,
"luax_checkstring" => :string,
}.freeze

    attr_reader :function, :native_name, :parameters, :self_parameter

    # [entry] The Survey::Entry of a readable wrap function.
    # [binding] Its BindingList::Generated entry.
    # [native_name] Its name in Lota::Native.
    # [types] A CppTypes.
    # [module_class] The class LÖVE's instance() names in its wrap file.
    # [helpers] LÖVE's luax_check* helpers, to the classes they check for
    #   (Catalog#helpers).
    # [main_thread] The Lota module to name when a method checks for the
    #   main thread (Lota::Graphics), or nil when any thread may call it.
    # [checks] The helpers that check the object they read, to their
    #   Catalog::Check (Catalog#checks).
    def initialize(entry, binding, native_name:, types:, module_class:, helpers: {}, main_thread: nil, checks: {})
      @function = entry.function
      @analysis = entry.analysis
      raise Unsupported, "#{@function.love_name} is not readable" unless @analysis&.readable?

      @native_name = native_name
      @types = types
      @helpers = helpers
      @checks = checks
      @module_class = module_class
      @main_thread = main_thread
      @module_dir = File.dirname(@function.wrap.path)
      @offset = @function.type_name ? 1 : 0
      @arity = binding.arguments ? binding.arguments + @offset : Float::INFINITY
      @assume = binding.assume.transform_keys { |key| key.gsub(/\s+/, "") }
      @body = prune(@analysis.statements)
      collect
    end

    # The C++ name of the ported function: LÖVE's own (w_getWidth), with
    # a double underscore made single, since C++ reserves names with one
    # (w_RandomGenerator__random).
    def cpp_name
      @function.definition.name.squeeze("_")
    end

    # Whether it binds a module function rather than a method.
    def singleton?
      @function.type_name.nil?
    end

    # Its wrap file and lines, as a citation.
    def citation
      definition = @function.definition
      "#{File.basename(@function.wrap.path)}:#{definition.line}-#{definition.end_line}"
    end

    # The C++ function.
    def definition
      @definition ||= begin
        @result_mode = result_mode
        body = emit(@body, top: true)
        body.unshift(*helper_checks)
        body.unshift("Rice::Array results;") if @result_mode == :many
        body.unshift("require_main_thread(MODULE);") if @main_thread && !singleton?
        params = ([@self_parameter && "#{self_const? ? 'const ' : ''}#{@self_parameter[:type]} &#{@self_parameter[:name]}"] +
          parameters.map(&:declaration)).compact
        <<~CPP
          // #{@function.love_name}: #{cpp_name} (#{citation}).
          #{return_type} #{cpp_name}(#{params.join(', ')}) {
          #{body.join("\n")}
          }
        CPP
      end
    end

    # The Rice call that binds it, on a Rice::Module or Data_Type.
    def registration
      args = parameters.map(&:rice_arg)
      kind = singleton? ? "define_singleton_function" : "define_method"
      ".#{kind}(#{[%("#{native_name}"), "&#{cpp_name}", *args].join(', ')})"
    end

    # Its RBS signature.
    def rbs
      definition
      params = parameters.map(&:rbs).join(", ")
      returns = (native_name.end_with?("=") && parameters.size == 1) ? parameters.first.rbs.split.first : rbs_result
      "def #{singleton? ? 'self.' : ''}#{native_name}: (#{params}) -> #{returns}"
    end

    # The types its results take, as [C++, RBS] pairs, in push order.
    def results
      @results ||= pushes(@body).map { |push| result_type(push) }
    end

    # Whether the method's object is only read: every method the body
    # calls on it is a const method, by LÖVE's headers.
    private def self_const?
      name = @self_parameter[:name]
      calls = []
      walk_texts(@body) do |text, _node|
        Calls.in(text).each { |call| calls << call if call.member && call.receiver == name }
      end
      helper_checks.each do |text|
        Calls.in(text).each { |call| calls << call if call.member && call.receiver == name }
      end
      calls.all? do |call|
        count = call.arguments.size
        method = @types.methods(self_type, call.base_name, module_dir: @module_dir).find do |candidate|
          candidate.parameters.size == count
        end
        method&.const
      end
    end

    private def return_type
      case @result_mode
      when :none then "void"
      when :one then results.first.first
      else "Rice::Array"
      end
    end

    private def rbs_result
      case result_mode
      when :none then "nil"
      when :one then results.first.last
      else "Array[#{(results.map(&:last) + (io_error? ? %w[nil String] : [])).uniq.join(' | ')}]"
      end
    end

    # Rule 4: a function that returns several values returns an Array of
    # all of them, whatever it returns on the way, so a form that can
    # return more than one value returns an Array on every path, empty
    # where LÖVE returns none (ADR 001, section 7). A form that returns
    # one value on some paths and none on others is not one rule 4 covers.
    private def result_mode
      counts = returns(@body)
      return :many if counts.max > 1
      raise Unsupported, "#{@function.love_name} returns #{counts.join(' or ')} values in the bound form" if counts.uniq.size > 1

      (counts.first == 0) ? :none : :one
    end

    # Whether the form returns luax_ioError's nil and message on a path.
    private def io_error?
      found = false
      walk_texts(@body) { |text, node| found ||= node.kind == :return && text.start_with?("luax_ioError") }
      found
    end

    # Each check a helper makes of the object it reads, as the helper makes
    # it before the wrap function goes on (luax_checkbody's "Attempt to use
    # destroyed body."), on the method's object or the parameter it reads.
    # A pointer compared with 0 is compared with nullptr, as clang-tidy's
    # modernize-use-nullptr asks.
    private def helper_checks
      @reads.uniq { |read| read[:index] }.filter_map do |read|
        check = @checks[read[:call].base_name] or next
        target = if read[:index] == 1 && @offset == 1
          "#{@self_parameter[:name]}."
        else
          parameter = parameters.find { |candidate| candidate.index == read[:index] } or next
          "#{parameter.name}->"
        end
        variable = Regexp.escape(check.variable)
        condition = check.condition.gsub(/\b#{variable}\s*->\s*(\w+)\s*==\s*0\b/) do
          field = Regexp.last_match(1)
          type = @types.field(helper_type(read[:call]), field, module_dir: @module_dir).to_s
          "#{check.variable}->#{field} == #{type.include?('*') ? 'nullptr' : '0'}"
        end
        "if (#{condition.gsub(/\b#{variable}\s*->\s*/, target)}) {\nthrow love::Exception(#{check.message});\n}"
      end
    end

    # --- Pruning: the statements of the bound form.

    private def prune(nodes)
      nodes.each_with_object([]) do |node, kept|
        case node.kind
        when :block, :catch then kept.concat(prune(node.body))
        when :if then kept.concat(prune_if(node))
        else kept << node
        end
        break kept if ends?(kept.last)
      end
    end

    private def prune_if(node)
      case condition(node.text)
      when true then prune(node.body)
      when false then prune(node.alternative)
      else [node.with(body: prune(node.body), alternative: prune(node.alternative))]
      end
    end

    # Whether +node+ ends its block: a return with nothing after it.
    private def ends?(node)
      node&.kind == :return
    end

    # true or false when the binding decides +text+, or nil when it is
    # tested at run time.
    private def condition(text)
      key = text.gsub(/\s+/, "")
      return @assume.fetch(key) if @assume.key?(key)

      match = key.match(/\A(?<not>!?)lua_isnone(?:ornil)?\(L,(?<index>\d+)\)\z/) or return nil
      return nil if match[:index].to_i <= @arity

      match[:not].empty?
    end

    # --- Parameters.

    private def collect
      @reads = []
      @optional = []
      @aliases = {}
      @renames = {}
      walk_texts(@body) do |text, node|
        @optional.concat(text.scan(/lua_isnone(?:ornil)?\s*\(\s*L\s*,\s*(\d+)\s*\)/).flatten.map(&:to_i))
        Calls.in(text).each { |call| record_read(call, text, node) if read?(call) }
      end
      @parameters = trailing_optional(
        @reads.group_by { |read| read[:index] }.sort.filter_map { |index, reads| parameter(index, reads) }
      )
      @reads.select { |read| read[:variable] }.each do |read|
        value = read_value(read[:call], read[:cast] || cast_of(read[:declared], read[:call]))
        @aliases[read[:variable]] = read[:rest].empty? ? value : "(#{value} #{read[:rest]})"
      end
    end

    # +parameters+, each after an optional one made optional too: Ruby
    # cannot leave out a positional argument and pass a later one, and
    # LÖVE reads such an argument only in the form that reads the optional
    # one before it (w_Quad_setViewport reads its texture's height only
    # with a width), so the port requires it there (read_value).
    private def trailing_optional(parameters)
      seen = false
      parameters.map do |parameter|
        optional = parameter.optional || parameter.default
        next parameter.tap { seen ||= optional } if optional || !seen

        parameter.with(optional: true, checked: true)
      end
    end

    private def read?(call)
      call.lua? && (Analysis::READERS.key?(call.base_name) || @helpers.key?(call.base_name))
    end

    private def record_read(call, text, node)
      index = call.arguments[1].to_s
      raise Unsupported, "#{@function.love_name} reads argument #{index}, a position it computes" unless index.match?(/\A\d+\z/)

      index = index.to_i
      cast = text[/\(\s*([\w:]+)\s*\)\s*#{Regexp.escape(call.name)}\s*\(/, 1]
      declared = text.match(/\A(?<const>const\s+)?(?<type>[\w:]+(?:\s*[*&]+\s*|\s+))(?<name>\w+)\s*=\s*(?:\([\w:]+\)\s*)?#{Regexp.escape(call.name)}\s*\(/)
      field = text[/\A\w+\.(\w+)\s*=/, 1]
      # What a declaration adds to its read (int start = (int)
      # luaL_checkinteger(L, 2) - 1 subtracts 1), which the variable keeps.
      rest = declared ? text[(Statements.matching(text, text.index("(", call.offset)) + 1)..].strip : ""
      @reads << {
index:,
call:,
cast:,
variable: declared&.[](:name),
declared: declared&.[](:type)&.strip,
constant: !declared&.[](:const).nil?,
field:,
rest:,
text:,
line: node.line,
}
    end

    private def parameter(index, reads)
      read = reads.first
      call = read[:call]
      if index == 1 && @offset == 1
        type = (Analysis::READERS[call.base_name] == :object) ? call.template : helper_type(call)
        @self_parameter = { name: read[:variable] || "self", type: }
        return nil
      end
      return nil if index > @arity

      kind = reads.map { |r| Analysis::READERS[r[:call].base_name] || :object }.uniq
      raise Unsupported, "#{@function.love_name} reads argument #{index} as #{kind.join(' and ')}" if kind.size > 1

      kind = kind.first
      name = parameter_name(index, read)
      cpp = cpp_type(kind, read)
      optional = @optional.include?(index)
      default = (!optional && call.base_name.match?(/opt/)) ? literal_default(call.arguments.last, cpp) : nil
      optional ||= call.base_name.match?(/opt/) && default.nil?
      Parameter.new(index:, name:, kind:, cpp:, object: (kind == :object) ? helper_type(call) : nil, optional:, default:,
        checked: false)
    end

    private def helper_type(call)
      call.template || @helpers.fetch(call.base_name)
    end

    private def cpp_type(kind, read)
      case kind
      when :number then "double"
      when :integer then integral(read[:cast]) || integral(read[:declared]) || "long long"
      when :string then "const std::string &"
      when :boolean, :truthy then "bool"
      when :object then "#{'const ' if read[:constant]}#{helper_type(read[:call])} *"
      else raise Unsupported, "#{@function.love_name} reads a #{kind} argument"
      end
    end

    private def integral(type)
      type&.strip&.then { |name| name.match?(INTEGRAL) ? name.sub(/\Aconst\s+/, "") : nil }
    end

    # The name LÖVE gives the value: the variable it reads it into, the
    # field it assigns, the enum it checks it as, or the engine
    # parameter it passes it to.
    private def parameter_name(index, read)
      if read[:variable] && (enum = enum_variable(read[:variable]))
        @renames[enum] = "#{Rules.snake_case(enum)}_value"
        return Rules.snake_case(enum)
      end
      return Rules.snake_case(read[:variable]) if read[:variable]
      return Rules.snake_case(read[:field]) if read[:field]

      engine_parameter(read) || "argument#{index - @offset}"
    end

    # The enum variable +variable+'s string is checked into, by
    # getConstant(variable, enum).
    private def enum_variable(variable)
      walk_texts(@body) do |text, _node|
        found = text[/\bgetConstant\s*\(\s*#{Regexp.escape(variable)}\s*,\s*(\w+)\s*\)/, 1]
        return found if found
      end
      nil
    end

    private def engine_parameter(read)
      Calls.in(read[:text]).each do |call|
        next unless call.member

        position = call.arguments.index { |argument| argument.include?(read[:call].name) } or next
        owner = (call.receiver == "instance()") ? @module_class : self_type
        method = @types.methods(owner, call.base_name, module_dir: @module_dir)
          .find { |candidate| candidate.parameters.size == call.arguments.size }
        return Rules.snake_case(method.parameters[position].name) if method
      end
      nil
    end

    private def literal_default(text, cpp)
      value = text.strip.sub(/(?<=\d)[fF]\z/, "")
      return nil unless value.match?(/\A-?\d+(?:\.\d+)?\z/) || %w[true false].include?(value)
      return value.include?(".") ? value : "#{value}.0" if cpp == "double"

      value
    end

    # --- Emission.

    private def emit(nodes, top: false)
      lines = []
      nodes.each_with_index do |node, position|
        last = top && position == nodes.size - 1
        lines.concat(emit_node(node, last:))
      end
      lines
    end

    private def emit_node(node, last:)
      case node.kind
      when :expression then emit_expression(node.text)
      when :return then emit_return(node.text, last:)
      when :if then emit_if(node)
      else raise Unsupported, "#{@function.love_name} has a #{node.kind} in its bound form (line #{node.line})"
      end
    end

    private def emit_expression(text)
      return [] if parameter_declaration?(text)
      return emit_push(text) if push?(text)
      if (together = Analysis.declared_together(text))
        return together[:names].map { |name| "#{declaration("#{together[:type]} #{name}")};" }
      end

      ["#{declaration(rewrite(text))};"]
    end

    private def emit_if(node)
      lines = ["if (#{rewrite(node.text)}) {", *emit(node.body), "}"]
      lines.push("else {", *emit(node.alternative), "}") if node.alternative.any?
      lines
    end

    private def emit_return(text, last:)
      if text.match?(/\A\d+\z/)
        return ["return results;"] if @result_mode == :many
        return [] if @result_mode == :one || last

        return ["return;"]
      end
      call = Calls.in(text).first
      case call&.base_name
      when "luaL_error" then ["throw love::Exception(#{rewrite(call.arguments[1..].join(', '))});"]
      when "luax_ioError" then ["return io_error(#{rewrite(call.arguments[1..].join(', '))});"]
      when "luax_enumerror" then ["raise_enum_error(#{enum_error_arguments(call)});"]
      else raise Unsupported, "#{@function.love_name} returns #{text}"
      end
    end

    # luax_enumerror's arguments, for raise_enum_error, which takes the
    # bad name as the std::string the parameter already is.
    private def enum_error_arguments(call)
      arguments = call.arguments[1..].map { |argument| rewrite(argument) }
      arguments[-1] = arguments[-1].delete_suffix(".c_str()")
      arguments.join(", ")
    end

    private def emit_push(text)
      call = Calls.in(text).first
      type, = result_type(call)
      value = convert(rewrite(call.arguments[1]), call, type)
      case @result_mode
      when :one then ["return #{value};"]
      when :many then ["results.push(#{value}, false);"]
      else raise Unsupported, "#{@function.love_name} pushes a result it does not return"
      end
    end

    # A declaration with no initializer gets one, and one never changed
    # afterward becomes const.
    private def declaration(text)
      match = text.match(/\A(?<type>(?:const\s+)?[\w:]+(?:\s*<[^;=]*?>)?)(?<pointer>\s*\*\s*|\s+)(?<name>\w+)(?<rest>\s*=.*)?\z/m)
      return text unless match && !text.match?(/\A(?:return|throw|delete)\b/)

      name = match[:name]
      type = "#{match[:type]}#{match[:pointer].include?('*') ? ' *' : ' '}"
      return "#{type}#{name}#{match[:pointer].include?('*') ? ' = nullptr' : '{}'}" unless match[:rest]
      return text if modified?(name, text) || match[:type].start_with?("const ")

      "const #{text}"
    end

    # Whether a statement other than +declaration+ changes +name+.
    private def modified?(name, declaration)
      walk_texts(@body) do |text, _node|
        next if rewrite(text) == declaration

        return true if text.match?(%r{(?<![\w.>])#{Regexp.escape(name)}(?:\.\w+)?\s*(?:[-+*/]?=(?!=)|\+\+|--)})
        return true if text.match?(/getConstant\s*\([^,]+,\s*#{Regexp.escape(name)}\s*\)/)
        return true if Calls.in(text).any? { |call| fills?(call, name) }
      end
      false
    end

    # Whether +call+, a method call, passes +name+ where the method takes a
    # reference it may write through, by LÖVE's headers, as
    # SpriteBatch::getDrawRange fills its start and count.
    private def fills?(call, name)
      return false unless call.member

      position = call.arguments.index { |argument| argument.strip == name } or return false
      owner = (call.receiver == "instance()") ? @module_class : variable_type(call.receiver.to_s)
      method = @types.methods(owner, call.base_name, module_dir: @module_dir)
        .find { |candidate| candidate.parameters.size == call.arguments.size }
      type = method&.parameters&.[](position)&.type.to_s
      type.end_with?("&") && !type.start_with?("const ")
    end

    private def parameter_declaration?(text)
      @reads.any? { |read| read[:variable] && read[:text] == text }
    end

    private def push?(text)
      Calls.in(text).first&.then { |call| call.lua? && call.base_name.match?(Analysis::PUSHERS) && text.start_with?(call.name) }
    end

    # +text+ with each Lua read replaced by its parameter, each renamed
    # variable renamed, and the method's object reached with a dot.
    # Lua's number, lua_Number, is a double in the LuaJIT LÖVE builds
    # with (luaconf.h, LUA_NUMBER), so a wrap function's limits on it, as
    # Source:setPitch's std::numeric_limits<lua_Number>, are a double's. A
    # float literal's suffix is written F, as clang-tidy's
    # readability-uppercase-literal-suffix asks.
    private def rewrite(text)
      text = replace_reads(text)
      text = replace_identifiers(text)
      text = text.gsub(/\blua_Number\b/, "double")
      text = text.gsub(/\b(\d+\.\d*|\d*\.\d+)f\b/, '\1F')
      text = text.gsub(/\b#{Regexp.escape(@self_parameter[:name])}\s*->/, "#{@self_parameter[:name]}.") if @self_parameter
      text = keep_strings(text)
      text.gsub(/(!?)\s*lua_isnone(?:ornil)?\s*\(\s*L\s*,\s*(\d+)\s*\)/) do
        parameter = parameters.find { |candidate| candidate.index == Regexp.last_match(2).to_i }
        raise Unsupported, "#{@function.love_name} tests argument #{Regexp.last_match(2)}, which it does not bind" unless parameter

        "#{Regexp.last_match(1).empty? ? '!' : ''}#{parameter.name}.has_value()"
      end
    end

    # A string LÖVE reads as a const char * becomes a std::string
    # parameter, which a read passes on with c_str(); where the engine
    # method takes a std::string, as System::setClipboardText does, the
    # parameter passes as it is, rather than as a new copy of its bytes.
    private def keep_strings(text)
      Calls.in(text).select(&:member).reverse_each do |call|
        owner = (call.receiver == "instance()") ? @module_class : (@self_parameter && self_type)
        method = owner && @types.methods(owner, call.base_name, module_dir: @module_dir)
          .find { |candidate| candidate.parameters.size == call.arguments.size }
        next unless method

        start = text.index("(", call.offset)
        finish = Statements.matching(text, start)
        arguments = call.arguments.each_with_index.map do |argument, position|
          stripped = argument.strip
          if stripped.end_with?(".c_str()") && method.parameters[position].type.include?("std::string")
            stripped.delete_suffix(".c_str()")
          else
            stripped
          end
        end
        text = "#{text[0..start]}#{arguments.join(', ')}#{text[finish..]}"
      end
      text
    end

    private def replace_reads(text)
      Calls.in(text).select { |call| read?(call) }.reverse_each do |call|
        start = call.offset
        finish = Statements.matching(text, text.index("(", start)) + 1
        cast = text[0...start][/\(\s*([\w:]+)\s*\)\s*\z/]
        start -= cast.length if cast
        text = text[0...start] + read_value(call, cast && cast[/[\w:]+/]) + text[finish..]
      end
      text
    end

    # The C++ expression a read becomes.
    private def read_value(call, cast)
      index = call.arguments[1].to_i
      return @self_parameter[:name] if index == 1 && @offset == 1
      return cast_to(rewrite(call.arguments.last), cast) if index > @arity

      parameter = parameters.find { |candidate| candidate.index == index }
      value = if parameter.checked
        %(required(#{parameter.name}, "#{parameter.name}"))
      elsif parameter.optional && call.base_name.match?(/opt/)
        "#{parameter.name}.value_or(#{rewrite(call.arguments.last)})"
      elsif parameter.optional
        "#{parameter.name}.value()"
      else
        parameter.name
      end
      value = "#{value}.c_str()" if STRING_READERS[call.base_name] == :c_str
      cast_to(value, (cast == parameter.cpp) ? nil : cast)
    end

    private def cast_to(value, cast)
      cast ? "static_cast<#{cast}>(#{value})" : value
    end

    private def replace_identifiers(text)
      map = @renames.merge(@aliases)
      return text if map.empty?

      out = +""
      index = 0
      while index < text.length
        if ['"', "'"].include?(text[index])
          finish = Statements.skip_literal(text, index)
          out << text[index...finish]
          index = finish
        elsif (word = text[index..][/\A[A-Za-z_]\w*/])
          before = out[/(?:\.|->|::)\s*\z/]
          out << ((before.nil? && map.key?(word)) ? map.fetch(word) : word)
          index += word.length
        else
          out << text[index]
          index += 1
        end
      end
      out
    end

    # The type a declaration converts its read to, when it differs from
    # the parameter's (float width = luaL_checknumber(L, 1)).
    private def cast_of(declared, call)
      return nil unless declared

      type = declared.strip
      return nil if type.include?("*") || type.include?("string") || type.include?("auto")
      return nil if type == "double" && Analysis::READERS[call.base_name] == :number

      parameter = parameters.find { |candidate| candidate.index == call.arguments[1].to_i }
      (parameter && parameter.cpp == type) ? nil : type
    end

    # --- Results.

    private def pushes(nodes)
      found = []
      walk_texts(nodes) do |text, _node|
        call = Calls.in(text).first
        found << call if call&.lua? && call.base_name.match?(Analysis::PUSHERS) && text.start_with?(call.name)
      end
      found
    end

    # The numbers of values the form's returns give: each return of a
    # count, and luax_ioError's two, nil and its message
    # (src/modules/filesystem/wrap_File.cpp:34-46).
    private def returns(nodes)
      counts = []
      walk_texts(nodes) do |text, node|
        next unless node.kind == :return

        counts << text.to_i if text.match?(/\A\d+\z/)
        counts << 2 if text.start_with?("luax_ioError")
      end
      counts.empty? ? [0] : counts.uniq
    end

    # The C++ return type and RBS type of a push.
    private def result_type(call)
      expression = call.arguments[1]
      case call.base_name
      when "luax_pushboolean", "lua_pushboolean" then %w[bool bool]
      when "lua_pushstring", "luax_pushstring" then ["std::string", "String"]
      when "lua_pushnumber", "lua_pushinteger" then number_type(call.base_name, expression)
      else raise Unsupported, "#{@function.love_name} pushes with #{call.base_name}"
      end
    end

    # Rule 14: an Integer where LÖVE's C++ holds the number as an integer,
    # a Float otherwise.
    private def number_type(pusher, expression)
      type = expression_type(expression)
      raise Unsupported, "#{@function.love_name} pushes #{expression}, whose C++ type the headers do not give" unless type

      type = type.sub(/\Aconst\s+/, "").delete("&").strip
      return [type, "Integer"] if type.match?(INTEGRAL)
      return ["double", "Float"] if type.match?(FLOATING) && pusher == "lua_pushnumber"

      raise Unsupported, "#{@function.love_name} pushes #{expression} (#{type}) with #{pusher}"
    end

    # A float pushed as a lua_Number, a double, is widened to one; an
    # integer cast to a lua_Number keeps its own type (rule 14), so the
    # cast goes.
    private def convert(value, call, type)
      return value.sub(/\A\(\s*double\s*\)\s*/, "") if type.match?(INTEGRAL)
      return value unless call.base_name == "lua_pushnumber" && type == "double"

      source = expression_type(call.arguments[1]).to_s.sub(/\Aconst\s+/, "").delete("&").strip
      (source == "double") ? value : "static_cast<double>(#{value})"
    end

    # The C++ type of a pushed expression, from LÖVE's declarations.
    private def expression_type(expression)
      text = expression.strip
      if (match = text.match(/\A\(\s*(?<cast>[\w:]+)\s*\)\s*(?<rest>.+)\z/))
        return match[:cast] unless match[:cast].match?(/lua_Number|lua_Integer/)

        return expression_type(match[:rest])
      end
      return expression_type(Regexp.last_match(1)) if text =~ %r{\A(\w+)\s*(?:\+|-(?!>)|\*|/)\s*\S.*\z}
      return method_type(@module_class, Regexp.last_match(1), Regexp.last_match(2)) if text =~ /\Ainstance\(\)\s*->\s*(\w+)\s*\((.*)\)\z/m
      return method_type(variable_type(Regexp.last_match(1)), Regexp.last_match(2), Regexp.last_match(3)) if text =~ /\A(\w+)\s*(?:->|\.)\s*(\w+)\s*\((.*)\)\z/m
      return @types.field(variable_type(Regexp.last_match(1)), Regexp.last_match(2), module_dir: @module_dir) if text =~ /\A(\w+)\.(\w+)\z/

      @analysis.declared_type(text) if text.match?(/\A\w+\z/)
    end

    private def variable_type(variable)
      return self_type if @self_parameter && variable == @self_parameter[:name]

      @analysis.type_of(variable)
    end

    private def self_type
      @self_parameter&.fetch(:type)
    end

    private def method_type(owner, name, arguments)
      count = arguments.strip.empty? ? 0 : Calls.split(arguments).size
      methods = @types.methods(owner, name, module_dir: @module_dir)
      (methods.find { |method| method.parameters.size == count } || methods.first)&.return_type
    end

    private def walk_texts(nodes, &)
      nodes.each do |node|
        yield node.text, node unless node.kind == :catch
        walk_texts(node.body, &)
        walk_texts(node.alternative, &)
      end
    end
  end
end
