# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Filesystem
    # The contents of a file, held in memory under the file's name.
    #
    # LÖVE's decoders read bytes, not paths. A PNG you read with Ruby's
    # own File is a String the engine cannot see, and without a name the
    # engine cannot tell what kind of file it was.
    #
    # A FileData copies the bytes into the engine and keeps the name with
    # them. Hand it to a constructor that decodes, such as
    # Lota::Image::ImageData.new.
    #
    # Use it to decode an image you read yourself, or one you built in
    # memory. It is a Data, so it inherits from Lota::Data, whose #size and
    # #string give its bytes back. Lota::Filesystem.new_file_data makes one.
    #
    # === Examples
    #
    #   png = File.binread("player.png")
    #   data, = Lota::Filesystem.new_file_data(png, "player.png")
    #   image = Lota::Image::ImageData.new(data)
    #
    #   # The name matters only for its extension.
    #   Lota::Filesystem.new_file_data(png, "anything.png")
    class FileData < Data
      # Wraps a FileData the engine made, such as one
      # Lota::Image::ImageData#encode returns. :nodoc:
      private_class_method def self.from_native(native)
        file_data = allocate
        file_data.instance_variable_set(:@native, native)
        file_data.freeze
      end

      # Makes this FileData, a copy of +source+ by Ruby's +clone+ or
      # +dup+, LÖVE's copy, matching FileData:clone
      # (src/modules/filesystem/wrap_FileData.cpp, w_FileData_clone): a new
      # FileData with a copy of the bytes and the name
      # (doc/contributors/design/translation.md).
      #
      # === Example
      #
      #   data.clone.string # => "helloworld"
      def initialize_copy(source)
        super
        @native = source.native.clone
        freeze
      end

      # The file's name, matching FileData:getFilename
      # (src/modules/filesystem/wrap_FileData.cpp, w_FileData_getFilename).
      #
      # === Example
      #
      #   Lota::Filesystem.new_file_data("hi", "note.txt").first.filename # => "note.txt"
      def filename
        @native.filename
      end

      # The file's extension, without its dot, matching
      # FileData:getExtension (src/modules/filesystem/wrap_FileData.cpp,
      # w_FileData_getExtension), or an empty String when its name has
      # none.
      #
      # === Example
      #
      #   Lota::Filesystem.new_file_data("hi", "note.txt").first.extension # => "txt"
      def extension
        @native.extension
      end
    end
  end
end
