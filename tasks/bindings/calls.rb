# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "statements"

module Bindings
  # The function calls in one C++ expression.
  #
  # A wrap function talks to Lua only through calls that take the
  # lua_State, L, first: luaL_checknumber(L, 1), lua_pushinteger(L, w).
  # Calls finds every call in an expression, with its arguments split at
  # the top level, so an analysis can ask what each one reads or pushes.
  module Calls
    # One call.
    #
    # [name] The called name, template arguments included
    #   (luax_checktype<Texture>).
    # [arguments] Each argument's text, trimmed.
    # [member] Whether it is called through . or -> on an object.
    # [receiver] The object's text, for a member call.
    # [offset] Where the name starts in the expression.
    class Call < Data.define(:name, :arguments, :member, :receiver, :offset)
      # The name without template arguments or namespace.
      def base_name
        name.sub(/<.*>\z/m, "").split("::").last
      end

      # The template argument (Texture in luax_checktype<Texture>), or nil.
      def template
        name[/<\s*([\w:]+)\s*>\z/, 1]&.split("::")&.last
      end

      # Whether L, the lua_State, is its first argument.
      def lua?
        arguments.first == "L"
      end
    end

    NAME = /(?<![\w.>:])(?<receiver>(?:[A-Za-z_]\w*(?:\(\))?\s*(?:->|\.)\s*)*)(?<name>[A-Za-z_][\w:]*(?:\s*<[\w:\s*]+>)?)\s*\(/
    NOT_CALLS = %w[
      if
      for
      while
      switch
      return
      sizeof
      static_cast
      reinterpret_cast
      const_cast
      dynamic_cast
      decltype
      catch
].freeze

    # Every call in +text+, nested calls included, in order.
    def self.in(text)
      calls = []
      text.to_enum(:scan, NAME).each do
        match = Regexp.last_match
        name = match[:name].gsub(/\s+/, "")
        next if NOT_CALLS.include?(name)

        open = match.end(0) - 1
        close = Statements.matching(text, open)
        receiver = match[:receiver].sub(/\s*(?:->|\.)\s*\z/, "")
        calls << Call.new(name:, arguments: split(text[(open + 1)...close]), member: !receiver.empty?,
          receiver:, offset: match.begin(:name))
      end
      calls
    end

    # +text+ split at its top-level commas.
    def self.split(text)
      parts = []
      depth = 0
      current = +""
      index = 0
      while index < text.length
        char = text[index]
        if ['"', "'"].include?(char)
          finish = Statements.skip_literal(text, index)
          current << text[index...finish]
          index = finish
          next
        end
        depth += 1 if "([{".include?(char)
        depth -= 1 if ")]}".include?(char)
        if char == "," && depth.zero?
          parts << current.strip
          current = +""
        else
          current << char
        end
        index += 1
      end
      parts << current.strip unless current.strip.empty? && parts.empty?
      parts
    end
  end
end
