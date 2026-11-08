# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Data
    # Lua 5.3's string.pack, string.unpack, and string.packsize, which
    # love.data.pack, unpack, and getPackedSize call in the copy LÖVE
    # bundles (src/libraries/lua53/lstrlib.c:155-599), ported to Ruby,
    # since Lota builds no Lua (ADR 001, section 1). :nodoc:
    #
    # The sizes are those of the machine's C types, as LÖVE's build
    # compiles them: a long is 4 bytes on Windows and 8 elsewhere, and a
    # lua_Integer is LuaJIT's, a ptrdiff_t of 8 bytes. A luaL_argerror
    # raises ArgumentError with its message, and a luaL_error
    # RuntimeError, as Lota raises for the same errors from LÖVE's C++.
    module Packing
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 1994-2014 Lua.org, PUC-Rio
      # SPDX-SnippetCopyrightText: 2015 Kepler Project
      # SPDX-License-Identifier: MIT
      #
      # Ported from vendor/love/src/libraries/lua53/lstrlib.c, as cited
      # below, which the LOVE Development Team modified to work with Lua
      # 5.1's API.

      # MAXINTSIZE, the most bytes of an integer (line 180).
      MAXINTSIZE = 16
      # SZINT, the bytes of a lua_Integer (line 189).
      SZINT = [0].pack("j!").bytesize
      # MAXALIGN, the alignment of the widest of a double, a pointer, and
      # a lua_Integer (lines 200-205).
      MAXALIGN = [[0.0].pack("d").bytesize, [0].pack("j!").bytesize].max
      # MAXSIZE, a size that fits in an int (lines 155-156).
      MAXSIZE = (2 ** 31) - 1
      # nativeendian (lines 193-196).
      NATIVE_LITTLE = [1].pack("s").getbyte(0) == 1
      # The options of a fixed size and kind (getoption, lines 290-325).
      FIXED = {
        "b" => [:int, 1],
        "B" => [:uint, 1],
        "h" => [:int, [0].pack("s!").bytesize],
        "H" => [:uint, [0].pack("s!").bytesize],
        "l" => [:int, [0].pack("l!").bytesize],
        "L" => [:uint, [0].pack("l!").bytesize],
        "j" => [:int, SZINT],
        "J" => [:uint, SZINT],
        "T" => [:uint, [0].pack("J!").bytesize],
        "f" => [:float, 4],
        "d" => [:float, 8],
        "n" => [:float, 8],
        "x" => [:padding, 1],
        "z" => [:zstr, 0],
        "X" => [:paddalign, 0],
      }.freeze
      # Bits of a lua_Unsigned.
      UNSIGNED = (2 ** (8 * SZINT)) - 1

      # A format string being read, with the byte order and alignment its
      # options set (Header, lines 222-226).
      class Format # :nodoc:
        attr_reader :little, :maxalign

        def initialize(format)
          @format = format
          @index = 0
          @little = NATIVE_LITTLE
          @maxalign = 1
        end

        # Whether every option has been read.
        def done?
          @index >= @format.bytesize
        end

        # getdetails (lines 337-355): the next option, its size, and the
        # padding before it that aligns it at +totalsize+.
        def details(totalsize)
          option, size = self.option
          align = size
          if option == :paddalign && (done? || (next_option = self.option).first == :char || (align = next_option.last).zero?)
            raise ArgumentError, "invalid next option for option 'X'"
          end
          return [option, size, 0] if align <= 1 || option == :char

          align = @maxalign if align > @maxalign
          raise ArgumentError, "format asks for alignment not power of 2" unless align.nobits?(align - 1)

          [option, size, (align - (totalsize & (align - 1))) & (align - 1)]
        end

        # getoption (lines 290-325): the next option and its size, or
        # :nop for one that only sets the byte order or the alignment.
        def option
          character = @format.byteslice(@index)
          @index += 1
          return FIXED.fetch(character) if FIXED.key?(character)

          case character
          when "i" then [:int, limited(4)]
          when "I" then [:uint, limited(4)]
          when "s" then [:string, limited([0].pack("J!").bytesize)]
          when "c" then [:char, number(-1).tap { |size| raise "missing size for format option 'c'" if size == -1 }]
          when " " then [:nop, 0]
          when "<" then setting { @little = true }
          when ">" then setting { @little = false }
          when "=" then setting { @little = NATIVE_LITTLE }
          when "!" then setting { @maxalign = limited(MAXALIGN) }
          else raise "invalid format option '#{character}'"
          end
        end

        private def setting
          yield
          [:nop, 0]
        end

        # getnum (lines 251-261): the numeral at the reading position, or
        # +default+ when there is none.
        private def number(default)
          return default unless digit?

          value = 0
          loop do
            value = (value * 10) + @format.getbyte(@index) - 48
            @index += 1
            break unless digit? && value <= (MAXSIZE - 9) / 10
          end
          value
        end

        private def digit?
          byte = @format.getbyte(@index)
          !byte.nil? && byte.between?(48, 57)
        end

        # getnumlimit (lines 268-274).
        private def limited(default)
          size = number(default)
          raise "integral size (#{size}) out of limits [1,#{MAXINTSIZE}]" if size > MAXINTSIZE || size <= 0

          size
        end
      end

      # lua53_str_pack (lines 399-479): +values+ packed by +format+, as a
      # binary String.
      def self.pack(format, values)
        reader = Format.new(string(format))
        packed = "".b
        totalsize = 0
        arg = -1
        until reader.done?
          option, size, ntoalign = reader.details(totalsize)
          totalsize += ntoalign + size
          packed << ("\0" * ntoalign)
          arg += 1
          case option
          when :int then pack_int(packed, values[arg], size, reader.little)
          when :uint then pack_uint(packed, values[arg], size, reader.little)
          when :float then packed << [float(values[arg])].pack(float_directive(size, reader.little))
          when :char
            bytes = string(values[arg]).b
            raise ArgumentError, "string longer than given size" unless bytes.bytesize <= size

            packed << bytes << ("\0" * (size - bytes.bytesize))
          when :string
            bytes = string(values[arg]).b
            unless size >= [0].pack("J!").bytesize || bytes.bytesize < (1 << (size * 8))
              raise ArgumentError, "string length does not fit in given size"
            end

            packint(packed, bytes.bytesize, reader.little, size, false)
            packed << bytes
            totalsize += bytes.bytesize
          when :zstr
            bytes = string(values[arg]).b
            raise ArgumentError, "string contains zeros" if bytes.include?("\0")

            packed << bytes << "\0"
            totalsize += bytes.bytesize + 1
          when :padding
            packed << "\0"
            arg -= 1
          else arg -= 1
          end
        end
        packed
      end

      # lua53_str_packsize (lines 482-504): how many bytes +format+ packs,
      # which may not hold a string of a length of its own.
      def self.packed_size(format)
        reader = Format.new(string(format))
        totalsize = 0
        until reader.done?
          option, size, ntoalign = reader.details(totalsize)
          size += ntoalign
          raise ArgumentError, "format result too large" unless totalsize <= MAXSIZE - size

          totalsize += size
          raise ArgumentError, "variable-length format" if %i[string zstr].include?(option)
        end
        totalsize
      end

      # lua53_str_unpack (lines 541-599): the values +format+ packed in
      # +data+, a binary String, from byte +position+, counted from 1 and
      # back from the end when negative, then the position after them.
      def self.unpack(format, data, position)
        reader = Format.new(string(format))
        length = data.bytesize
        pos = relative(position.nil? ? 1 : integer(position), length) - 1
        raise ArgumentError, "initial position out of string" unless pos.between?(0, length)

        results = [] #: Array[Integer | Float | String]
        until reader.done?
          option, size, ntoalign = reader.details(pos)
          raise ArgumentError, "data string too short" if pos + ntoalign + size > length

          pos += ntoalign
          case option
          when :int, :uint then results << unpackint(data, pos, reader.little, size, option == :int)
          when :float
            number = data.byteslice(pos, size).to_s.unpack1(float_directive(size, reader.little)) #: Float
            results << number
          when :char then results << data.byteslice(pos, size).to_s
          when :string
            len = unpackint(data, pos, reader.little, size, false) & UNSIGNED
            raise ArgumentError, "data string too short" unless pos + len + size <= length

            results << data.byteslice(pos + size, len).to_s
            pos += len
          when :zstr
            len = (data.index("\0", pos) || length) - pos
            results << data.byteslice(pos, len).to_s
            pos += len + 1
          end
          pos += size
        end
        results << (pos + 1)
      end

      # posrelat (lines 160-164): a position counted back from the end
      # when negative.
      private_class_method def self.relative(pos, length)
        if pos >= 0 then pos
        elsif -pos > length then 0
        else length + pos + 1
        end
      end

      # Kint (lines 414-422): a signed integer, which must fit in +size+
      # bytes.
      private_class_method def self.pack_int(packed, value, size, little)
        n = integer(value)
        if size < SZINT
          lim = 1 << ((size * 8) - 1)
          raise ArgumentError, "integer overflow" unless -lim <= n && n < lim
        end
        packint(packed, n & UNSIGNED, little, size, n.negative?)
      end

      # Kuint (lines 423-429): an unsigned integer, which must fit in
      # +size+ bytes, as the lua_Unsigned a negative one becomes does not.
      private_class_method def self.pack_uint(packed, value, size, little)
        n = integer(value) & UNSIGNED
        raise ArgumentError, "unsigned overflow" if size < SZINT && n >= (1 << (size * 8))

        packint(packed, n, little, size, false)
      end

      # packint (lines 364-378).
      private_class_method def self.packint(packed, n, little, size, negative)
        bytes = Array.new(size, 0)
        bytes[little ? 0 : size - 1] = n & 0xFF
        (1...size).each do |i|
          n >>= 8
          bytes[little ? i : size - 1 - i] = n & 0xFF
        end
        (SZINT...size).each { |i| bytes[little ? i : size - 1 - i] = 0xFF } if negative && size > SZINT
        packed << bytes.pack("C*")
      end

      # unpackint (lines 515-538).
      private_class_method def self.unpackint(data, at, little, size, signed)
        limit = [size, SZINT].min
        res = (limit - 1).downto(0).reduce(0) do |sum, i|
          (sum << 8) | data.getbyte(at + (little ? i : size - 1 - i)).to_i
        end
        if size < SZINT
          if signed
            mask = 1 << ((size * 8) - 1)
            res = (res ^ mask) - mask
          end
        elsif size > SZINT
          mask = (!signed || res < (1 << ((SZINT * 8) - 1))) ? 0 : 0xFF
          (limit...size).each do |i|
            raise "#{size}-byte integer does not fit into Lua Integer" if data.getbyte(at + (little ? i : size - 1 - i)) != mask
          end
        end
        (res >= (1 << ((SZINT * 8) - 1))) ? res - (1 << (SZINT * 8)) : res
      end

      # The pack directive of a float of +size+ bytes in the byte order.
      private_class_method def self.float_directive(size, little)
        (size == 4) ? (little ? "e" : "g") : (little ? "E" : "G")
      end

      # luaL_checkinteger: a number, truncated toward zero as LuaJIT's
      # lua_tointeger truncates a double.
      private_class_method def self.integer(value)
        case value
        when Integer then value
        when Float then value.to_i
        else raise TypeError, "wrong argument type #{value.class} (expected Integer)"
        end
      end

      # luaL_checknumber.
      private_class_method def self.float(value)
        case value
        when Integer, Float then value.to_f
        else raise TypeError, "wrong argument type #{value.class} (expected Float or Integer)"
        end
      end

      # luaL_checklstring.
      private_class_method def self.string(value)
        raise TypeError, "wrong argument type #{value.class} (expected String)" unless value.is_a?(String)

        value
      end

      # SPDX-SnippetEnd
    end
  end
end
