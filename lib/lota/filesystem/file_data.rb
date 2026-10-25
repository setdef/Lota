# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
    # memory.
    #
    # === Examples
    #
    #   png = File.binread("player.png")
    #   data = Lota::Filesystem::FileData.new(png, "player.png")
    #   image = Lota::Image::ImageData.new(data)
    #
    #   # The name matters only for its extension.
    #   Lota::Filesystem::FileData.new(png, "anything.png")
    class FileData
      # The engine's FileData, for Lota's own modules. :nodoc:
      attr_reader :native

      # Copies +contents+ into a new FileData named +name+, matching
      # love.filesystem.newFileData(contents, name)
      # (src/modules/filesystem/wrap_Filesystem.cpp, w_newFileData).
      #
      # [contents] String of the file's bytes, copied as they are.
      # [name] String, the file's name, such as <tt>"player.png"</tt>.
      #
      # LÖVE also takes a filename alone, and reads the file through
      # love.filesystem. Lota does not bind that form yet; read the bytes
      # with File.binread instead.
      #
      # === Example
      #
      #   Lota::Filesystem::FileData.new(File.binread("hit.png"), "hit.png")
      def initialize(contents, name)
        @native = Native::Filesystem.new_file_data(contents, name)
      end
    end
  end
end
