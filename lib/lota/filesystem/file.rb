# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Filesystem
    # A file LÖVE's filesystem opened, matching LÖVE's File class
    # (src/modules/filesystem/File.h), which Lota::Filesystem.open_file
    # returns. Its other methods, reading and writing among them, come
    # with Plan 002's story 4; a File not closed closes when Ruby collects
    # it, as a File LÖVE no longer refers to does.
    #
    # === Example
    #
    #   file, = Lota::Filesystem.open_file("save.dat", :r)
    #   file.object_type # => "File"
    class File
      include Object

      # The engine's File, for Lota's own modules. :nodoc:
      attr_reader :native

      # Wraps a File the engine opened. :nodoc:
      def self.from_native(native)
        file = allocate
        file.instance_variable_set(:@native, native)
        file
      end

      # Closes the file, matching File:close
      # (src/modules/filesystem/wrap_File.cpp, w_File_close), and returns
      # whether it was open to close (ADR 001, rule 7).
      #
      # === Example
      #
      #   file.close # => true
      def close
        @native.close
      end
    end
  end
end
