# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # The values a message or the restart value carries, between Ruby and
  # the engine, named after love::Variant (vendor/love/src/common/Variant.h),
  # which carries them in LÖVE: tokens translates luax_checkvariant, which
  # reads a Lua value into one, and read translates luax_pushvariant, which
  # makes a Lua value of one again (src/common/runtime.cpp:722-861). :nodoc:
  #
  # Between Ruby and Lota::Native a value is a flat Array of tokens, in the
  # order luax_checkvariant reads them: nil, +true+, +false+, a Float, or
  # a String is a token of its own, and a table is the Symbol +:table+,
  # the number of its pairs, and then each pair's key and value, in the
  # table's order. A Proc or a Method, Ruby's function, is the Symbol
  # +:unknown+, a value of unknown type, as is a table with one in it.
  # Lota::Native reads and writes the tokens of a table without calling
  # itself, so a table nests as deep as Ruby can build it, and each Ruby
  # object it reads stays in the one Array where Ruby's collector sees it.
  module Variant
    # The token that starts a table. :nodoc:
    TABLE = :table

    # The token of a value of unknown type. :nodoc:
    UNKNOWN = :unknown

    # What a table holds that a TypeError names. :nodoc:
    EXPECTED = "nil, true, false, a number, a String, a Symbol, an Array, a Hash, or a Proc"

    # The tokens of +value+, read as luax_checkvariant reads a Lua value:
    # nil, a boolean, a number, which becomes a Float, a String, a Symbol,
    # which becomes the String of its name (rule 9 of
    # doc/contributors/design/translation.md), and a table, an Array, whose keys
    # are 1 to its size, or a Hash, whose keys and values are read so. A Proc or
    # a Method is of unknown type, as a Lua function is, and so is a table with
    # one among its keys or values. Raises RuntimeError for a table that holds
    # itself, with LÖVE's message, TypeError for any other value, and
    # SystemStackError for tables nested too deeply for Ruby's stack, where
    # Lua's would overflow. :nodoc:
    def self.tokens(value)
      tokens = [] #: Array[token]
      outer = {} #: Hash[::Object, bool]
      write(value, tokens, outer.compare_by_identity)
      tokens
    end

    # The tokens of the two results of a modal draw callback, or of the
    # frame boot hands to the event module, that returned +values+, an
    # Array of them or the first alone, each read as tokens reads a value,
    # as drawCallbackInner reads the function's two results with
    # luax_checkvariant (src/modules/event/wrap_Event.cpp:161-174).
    # :nodoc:
    def self.results(values)
      first, second = values.is_a?(Array) ? values : [values]
      [tokens(first), tokens(second)]
    end

    # Whether +value+ is one that tokens reads, at its top. :nodoc:
    def self.value?(value)
      case value
      when nil, true, false, String, Symbol, Array, Hash, ::Proc, ::Method then true
      when Numeric then value.real?
      else false
      end
    end

    # +value+, one of a message's arguments as Lota::Native gives it, as
    # Ruby sees it: a String as a copy in UTF-8, the tokens of a table as
    # read makes them, and anything else as it is. :nodoc:
    def self.ruby(value)
      case value
      when String then value.dup.force_encoding(Encoding::UTF_8)
      when Array then read(value)
      else value
      end
    end

    # The value +tokens+ hold, as luax_pushvariant makes a Lua value of a
    # Variant. A String comes back as a copy in UTF-8. A table comes back
    # as a Hash of its keys and values, each read so, the later of two
    # pairs with one key winning, as luax_pushvariant sets each pair in
    # turn (runtime.cpp:837-853), or as an Array of its values when its
    # keys are 1 to n, a Lua sequence, which the empty table is too.
    # Raises ArgumentError for tokens that are not one value's. :nodoc:
    def self.read(tokens)
      value, after = at(tokens, 0)
      raise ArgumentError, "not the tokens of one value" unless after == tokens.size

      value
    end

    # Appends the tokens of +value+ to +tokens+, inside the tables
    # +outer+. :nodoc:
    private_class_method def self.write(value, tokens, outer)
      case value
      when nil, true, false, String then tokens << value
      when Symbol then tokens << value.name
      when Numeric then tokens << number(value)
      when Array then table(value.each.with_index(1).map { |element, key| [key, element] }, value, tokens, outer)
      when Hash then table(value.to_a, value, tokens, outer)
      when ::Proc, ::Method then tokens << UNKNOWN
      else raise TypeError, "wrong argument type #{value.class} (expected #{EXPECTED})"
      end
    end

    # The Float of the number +value+, which must be real. :nodoc:
    private_class_method def self.number(value)
      number = Float(value, exception: false) if value.real?
      raise TypeError, "wrong argument type #{value.class} (expected #{EXPECTED})" unless number

      number
    end

    # Appends the tokens of the table +value+, whose +pairs+ are its keys
    # and values, inside the tables +outer+, as luax_checkvariant reads a
    # table (runtime.cpp:758-808): it keeps the tables it is inside of,
    # and makes one with a pair of unknown type one itself. :nodoc:
    private_class_method def self.table(pairs, value, tokens, outer)
      raise "Cycle detected in table" if outer.key?(value)

      outer[value] = true
      start = tokens.size
      tokens.push(TABLE, pairs.size)
      pairs.each do |key, element|
        next if pair(key, element, tokens, outer)

        tokens.slice!(start..)
        tokens << UNKNOWN
        break
      end
      outer.delete(value)
    end

    # Appends the tokens of a table's +key+ and +element+, and answers
    # whether both are of a known type. LÖVE reads both before it looks
    # (runtime.cpp:784-798). :nodoc:
    private_class_method def self.pair(key, element, tokens, outer)
      key_at = tokens.size
      write(key, tokens, outer)
      element_at = tokens.size
      write(element, tokens, outer)
      tokens[key_at] != UNKNOWN && tokens[element_at] != UNKNOWN
    end

    # The value whose tokens start at +index+ of +tokens+, and the index
    # after them. :nodoc:
    private_class_method def self.at(tokens, index)
      raise ArgumentError, "not the tokens of one value" unless index < tokens.size

      case (token = tokens.fetch(index))
      when TABLE then table_at(tokens, index + 2, tokens.fetch(index + 1, nil))
      when String then [token.dup.force_encoding(Encoding::UTF_8), index + 1]
      when Symbol then raise ArgumentError, "not the tokens of one value"
      else [token, index + 1]
      end
    end

    # The table of +count+ pairs whose tokens start at +index+ of
    # +tokens+, and the index after them. :nodoc:
    private_class_method def self.table_at(tokens, index, count)
      raise ArgumentError, "not the tokens of one value" unless count.is_a?(Integer)

      hash = {} #: Hash[value, value]
      count.times do
        key, index = at(tokens, index)
        hash[key], index = at(tokens, index)
      end
      [sequence?(hash) ? Array.new(hash.size) { |key| hash.fetch((key + 1).to_f) } : hash, index]
    end

    # Whether the keys of +hash+ are 1 to its size, in any order. :nodoc:
    private_class_method def self.sequence?(hash)
      hash.each_key.all? do |key|
        key.is_a?(Float) && key.finite? && key == key.to_i && key.between?(1, hash.size)
      end
    end
    # SPDX-SnippetEnd
  end
end
