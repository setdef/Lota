# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # What every one of LÖVE's Data objects answers, whatever its class,
  # translated from Data's methods (src/modules/data/wrap_Data.cpp), and
  # LÖVE's love.data module.
  #
  # A sound's samples, an image's pixels, and a file's bytes are all
  # memory the engine holds. A game that saves a screenshot's bytes, sends
  # a sound over the network, or reads numbers from a binary file needs
  # those bytes, whatever kind of Data holds them.
  #
  # LÖVE's root type for such memory is Data, and every class that holds
  # some, Lota::Sound::SoundData, Lota::Image::ImageData, and
  # Lota::Filesystem::FileData, includes this module, as each inherits
  # Data's methods in LÖVE. Rule 1 of ADR 001 gives love.data the name
  # Lota::Data, and LÖVE's root type keeps its name there too, so inside
  # <tt>module Lota</tt> a bare +Data+ means this module, and Ruby's own
  # class is written <tt>::Data</tt>.
  #
  # Data's getPointer and getFFIPointer give Lua a raw pointer and a
  # LuaJIT FFI pointer, which Ruby has no use for, so Lota leaves them
  # out. getUInt8, getUInt16, and getUInt32 wait for the maintainer, since
  # rule 13 does not say where "UInt" splits into words.
  #
  # === Example
  #
  #   sound = Lota::Sound::SoundData.new("click.ogg")
  #   sound.size              # => 11708
  #   sound.string(0, 4).size # => 4
  module Data
    # How many bytes the Data holds, as an Integer, matching Data:getSize
    # (src/modules/data/wrap_Data.cpp, w_Data_getSize).
    #
    # === Example
    #
    #   sound.size # => 11708
    def size
      native.size
    end

    # The Data's bytes, as a String, matching Data:getString
    # (src/modules/data/wrap_Data.cpp, w_Data_getString).
    #
    # [offset] Integer byte to start at.
    # [size] Integer bytes to take; every byte from +offset+ on when +nil+
    #   or left out.
    #
    # The String is in Ruby's default external encoding, as File.read's
    # is, holding the bytes as they are. Raises RuntimeError, with LÖVE's
    # message, for a +size+ below 1, or bytes outside the Data.
    #
    # === Example
    #
    #   sound.string(0, 4).bytesize # => 4
    def string(offset = 0, size = nil)
      native.string(offset, size)
    end

    # Calls the block with +arguments+ while no other thread can use the
    # Data, and returns what the block returns, matching
    # Data:performAtomic (src/modules/data/wrap_Data.cpp,
    # w_Data_performAtomic), whose function becomes the block (ADR 001,
    # rule 12).
    #
    # [arguments] Anything, passed on to the block.
    #
    # The Data's lock is let go when the block returns or raises.
    #
    # === Example
    #
    #   sound.perform_atomic(0) { |i| sound.sample(i) }
    def perform_atomic(*arguments, &block)
      native.perform_atomic([block, *arguments])
    end

    # +count+ 32-bit floats from byte +offset+, as an Array of Floats,
    # matching Data:getFloat (src/modules/data/wrap_Data.cpp,
    # w_Data_getFloat), which returns each as a value of its own.
    #
    # [offset] Integer byte the first starts at.
    # [count] Integer how many, at least 1.
    #
    # Raises RuntimeError, with LÖVE's message, for a +count+ below 1, or
    # values outside the Data.
    #
    # === Example
    #
    #   data.float(0) # => [1.5]
    def float(offset, count = 1)
      native.float(offset, count)
    end

    # +count+ 64-bit floats from byte +offset+, as an Array of Floats,
    # matching Data:getDouble (src/modules/data/wrap_Data.cpp,
    # w_Data_getDouble), as #float reads them.
    #
    # === Example
    #
    #   data.double(0, 2) # => [1.5, -2.0]
    def double(offset, count = 1)
      native.double(offset, count)
    end

    # +count+ signed 8-bit integers from byte +offset+, as an Array of
    # Integers, matching Data:getInt8 (src/modules/data/wrap_Data.cpp,
    # w_Data_getInt8), as #float reads them.
    #
    # === Example
    #
    #   data.int8(0, 2) # => [-1, 7]
    def int8(offset, count = 1)
      native.int8(offset, count)
    end

    # +count+ signed 16-bit integers from byte +offset+, in the machine's
    # byte order, as an Array of Integers, matching Data:getInt16
    # (src/modules/data/wrap_Data.cpp, w_Data_getInt16), as #float reads
    # them.
    #
    # === Example
    #
    #   sound.int16(0) # => [-7]
    def int16(offset, count = 1)
      native.int16(offset, count)
    end

    # +count+ signed 32-bit integers from byte +offset+, in the machine's
    # byte order, as an Array of Integers, matching Data:getInt32
    # (src/modules/data/wrap_Data.cpp, w_Data_getInt32), as #float reads
    # them.
    #
    # === Example
    #
    #   data.int32(4) # => [65536]
    def int32(offset, count = 1)
      native.int32(offset, count)
    end
  end
end
