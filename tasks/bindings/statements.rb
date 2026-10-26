# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Bindings
  # The statements of a C++ function body, as a tree.
  #
  # A wrap function's body is straight-line code with a few branches: read
  # the arguments, call the engine, push the results. Its control flow is
  # what tells one overload from another (if (lua_isnoneornil(L, 5))), so
  # the parser needs the branches, but not the expressions inside them.
  # Statements splits a body into blocks, if/else, loops, switches,
  # returns, and expression statements, and keeps each expression as text.
  # A lambda passed to luax_catchexcept is opened up as a block of its own,
  # since LÖVE wraps most engine calls in one.
  module Statements
    # One statement.
    #
    # [kind] :expression, :return, :block, :if, :loop, :switch, :label,
    #   :jump (break or continue), or :catch (a luax_catchexcept lambda).
    # [text] The statement's own text: the expression, the returned value,
    #   or the condition of an if, loop, or switch.
    # [line] The line it starts on, in its file.
    # [body] The statements inside it (a block, a branch, a loop, a lambda).
    # [alternative] An if's else branch, or an empty Array.
    class Node < Data.define(:kind, :text, :line, :body, :alternative)
      # This statement and every statement inside it, depth first.
      def each_node(&)
        return enum_for(:each_node) unless block_given?

        yield self
        (body + alternative).each { |node| node.each_node(&) }
      end
    end

    # Raised when a body has a shape this parser does not read, such as an
    # unbalanced bracket.
    class Unreadable < StandardError; end

    KEYWORDS = %w[if for while do switch return break continue case default else].freeze
    CATCH = /\Aluax_catchexcept\s*\(\s*L\s*,\s*\[[^\]]*\]\s*\(\s*\)\s*(?:->\s*[\w:]+\s*)?\{/

    # The statements of +text+, which starts at +offset+ in +source+ (a
    # CppSource), for line numbers.
    def self.parse(text, offset, source)
      Parser.new(text, offset, source).statements(0, text.length)
    end

    # The offset of the bracket that closes the one at +open+ in +text+.
    def self.matching(text, open)
      closers = { "(" => ")", "[" => "]", "{" => "}" }
      stack = []
      index = open
      while index < text.length
        char = text[index]
        if closers.key?(char)
          stack << closers.fetch(char)
        elsif closers.value?(char)
          raise Unreadable, "unbalanced #{char}" unless stack.pop == char
          return index if stack.empty?
        elsif ['"', "'"].include?(char)
          index = skip_literal(text, index) - 1
        end
        index += 1
      end
      raise Unreadable, "no bracket closes the one at offset #{open}"
    end

    # The offset just past the literal at +start+.
    def self.skip_literal(text, start)
      quote = text[start]
      index = start + 1
      index += (text[index] == "\\") ? 2 : 1 while index < text.length && text[index] != quote
      index + 1
    end

    # Reads statements from a span of text.
    class Parser
      def initialize(text, offset, source)
        @text = text
        @offset = offset
        @source = source
      end

      # The statements between +start+ and +finish+.
      def statements(start, finish)
        nodes = []
        index = skip_space(start, finish)
        while index < finish
          node, index = statement(index, finish)
          nodes << node if node
          index = skip_space(index, finish)
        end
        nodes
      end

      private def statement(index, finish)
        word = @text[index..][/\A[A-Za-z_]\w*/]
        return block(index) if @text[index] == "{"
        return [nil, index + 1] if @text[index] == ";"
        return keyword(word, index, finish) if KEYWORDS.include?(word)

        expression(index, finish)
      end

      private def block(index)
        close = Statements.matching(@text, index)
        [node(:block, "", index, statements(index + 1, close)), close + 1]
      end

      private def keyword(word, index, finish)
        case word
        when "if" then conditional(index, finish)
        when "for", "while", "switch" then looping(word, index, finish)
        when "do" then do_loop(index, finish)
        when "return" then simple(:return, index, index + "return".length, finish)
        when "break", "continue" then simple(:jump, index, index, finish)
        when "case", "default" then label(index)
        else raise Unreadable, "#{word} without an if"
        end
      end

      private def conditional(index, finish)
        condition, after = parenthesized(index + 2)
        consequent, after = statement(skip_space(after, finish), finish)
        alternative = []
        rest = skip_space(after, finish)
        if @text[rest..][/\Aelse\b/]
          other, after = statement(skip_space(rest + 4, finish), finish)
          alternative = [other].compact
        end
        [Node.new(kind: :if, text: condition, line: line(index), body: [consequent].compact, alternative:), after]
      end

      private def looping(word, index, finish)
        header, after = parenthesized(index + word.length)
        inner, after = statement(skip_space(after, finish), finish)
        [node((word == "switch") ? :switch : :loop, header, index, [inner].compact), after]
      end

      private def do_loop(index, finish)
        inner, after = statement(skip_space(index + 2, finish), finish)
        rest = skip_space(after, finish)
        raise Unreadable, "do without while" unless @text[rest..][/\Awhile\b/]

        header, after = parenthesized(rest + 5)
        [node(:loop, header, index, [inner].compact), @text.index(";", after) + 1]
      end

      private def label(index)
        colon = @text.index(/:(?!:)/, index)
        [node(:label, @text[index...colon].strip, index, []), colon + 1]
      end

      private def simple(kind, index, start, finish)
        stop = statement_end(start, finish)
        [node(kind, @text[start...stop].strip, index, []), stop + 1]
      end

      private def expression(index, finish)
        stop = statement_end(index, finish)
        text = @text[index...stop].strip
        match = CATCH.match(text)
        return [node(:expression, text, index, []), stop + 1] unless match

        open = index + match.end(0) - 1
        close = Statements.matching(@text, open)
        [node(:catch, text, index, statements(open + 1, close)), stop + 1]
      end

      # The text inside the parentheses that open at or after +index+,
      # and the offset after them.
      private def parenthesized(index)
        open = @text.index("(", index)
        close = Statements.matching(@text, open)
        [@text[(open + 1)...close].strip, close + 1]
      end

      # The offset of the semicolon that ends the statement at +index+.
      private def statement_end(index, finish)
        while index < finish
          char = @text[index]
          return index if char == ";"

          index = if "([{".include?(char)
            Statements.matching(@text, index) + 1
          elsif ['"', "'"].include?(char)
            Statements.skip_literal(@text, index)
          else
            index + 1
          end
        end
        raise Unreadable, "a statement has no semicolon"
      end

      private def skip_space(index, finish)
        index += 1 while index < finish && @text[index].match?(/\s/)
        index
      end

      private def node(kind, text, index, body)
        Node.new(kind:, text:, line: line(index), body:, alternative: [])
      end

      private def line(index)
        @source.line_of(@offset + index)
      end
    end
  end
end
