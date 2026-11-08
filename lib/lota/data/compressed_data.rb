# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  class Data
    # Compressed bytes that know how they were compressed, matching LÖVE's
    # CompressedData class (src/modules/data/CompressedData.h).
    #
    # Lota::Data.compress returns one for the container +:data+, and
    # Lota::Data.decompress takes it back without being told its format.
    # Its bytes, which it reads as every Lota::Data does, are the compressed
    # ones.
    #
    # === Example
    #
    #   compressed = Lota::Data.compress(:data, :zlib, "helloworld")
    #   compressed.format                        # => :zlib
    #   Lota::Data.decompress(:string, compressed) # => "helloworld"
    class CompressedData < Data
      # Wraps a CompressedData the engine made. :nodoc:
      private_class_method def self.from_native(native)
        data = allocate
        data.instance_variable_set(:@native, native)
        data
      end

      # Makes this CompressedData, a copy of +source+ by Ruby's +clone+ or
      # +dup+, LÖVE's copy, matching CompressedData:clone
      # (src/modules/data/wrap_CompressedData.cpp:35-42): a new one with a
      # copy of the bytes and the same format (ADR 001, section 7).
      #
      # === Example
      #
      #   compressed.clone.format # => :zlib
      def initialize_copy(source)
        super
        @native = source.native.clone
      end

      # How its bytes were compressed, as a Symbol (ADR 001, rule 9):
      # +:lz4+, +:zlib+, +:gzip+, or +:deflate+, matching
      # CompressedData:getFormat
      # (src/modules/data/wrap_CompressedData.cpp:44-54).
      #
      # === Example
      #
      #   compressed.format # => :zlib
      def format
        @native.format.to_sym
      end
    end
  end
end
