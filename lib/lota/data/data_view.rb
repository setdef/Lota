# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  class Data
    # Some of another Data's bytes, without a copy, matching LÖVE's
    # DataView class (src/modules/data/DataView.h).
    #
    # A file often holds a header, then a table, then the rest. A DataView
    # is one part of it as a Data of its own, which reads, and is read by,
    # whatever takes a Data, while it shares the bytes of the Data it
    # views and keeps that Data alive.
    #
    # === Example
    #
    #   bytes = Lota::Data::ByteData.new("helloworld")
    #   Lota::Data::DataView.new(bytes, 5, 5).string # => "world"
    class DataView < Data
      # Wraps a DataView the engine made. :nodoc:
      private_class_method def self.from_native(native)
        view = allocate
        view.instance_variable_set(:@native, native)
        view
      end

      # Views +size+ of +data+'s bytes from byte +offset+, matching
      # love.data.newDataView (src/modules/data/wrap_DataModule.cpp:55-71).
      #
      # [data] Lota::Data to view.
      # [offset] Integer byte to start at.
      # [size] Integer bytes to view, every byte from +offset+ on when
      #   +nil+.
      #
      # Raises RuntimeError, with LÖVE's message, for a negative offset or
      # size, a size of 0, or bytes outside +data+; TypeError for a +data+
      # that is not a Lota::Data; and RuntimeError when the data module is
      # not open.
      #
      # === Example
      #
      #   Lota::Data::DataView.new(bytes, 0, 5)
      def self.new(data, offset, size = nil)
        case data
        when Data then from_native(Native::Data.new_data_view(data.__send__(:native), offset, size))
        else raise TypeError, "wrong argument type #{data.class} (expected Lota::Data)"
        end
      end

      # Makes this DataView, a copy of +source+ by Ruby's +clone+ or
      # +dup+, LÖVE's copy, matching DataView:clone
      # (src/modules/data/wrap_DataView.cpp:34-42): a new view of the same
      # bytes of the same Data (doc/contributors/design/translation.md).
      #
      # === Example
      #
      #   view.clone.string # => "world"
      def initialize_copy(source)
        super
        @native = source.native.clone
      end
    end
  end
end
