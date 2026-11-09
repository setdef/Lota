# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "image/image_data"
require_relative "image/compressed_image_data"
require_relative "image/compressed_data"

module Lota
  # Images as pixels in memory, translated from love.image.
  #
  # A texture lives on the graphics card, where drawing is fast and
  # reading is slow. Checking a pixel, saving a screenshot, or comparing
  # a frame with the one you expected all need the pixels back on the
  # CPU, one color at a time.
  #
  # This module holds ImageData, the engine's grid of decoded pixels, and
  # CompressedImageData, an image the graphics card decodes itself, such
  # as a DXT1 file, which CompressedData.new reads. Unlike Lota::Graphics,
  # it runs on any thread, as love.image does in LÖVE.
  module Image
    # Whether +file+ holds an image in a compressed format the graphics
    # card decodes itself, such as DXT1, ETC, or ASTC, which
    # Lota::Image::CompressedData.new can read, matching
    # love.image.isCompressed (src/modules/image/wrap_Image.cpp,
    # w_isCompressed).
    #
    # [file] String name of a file in the game's folder, a
    #   Lota::Filesystem::File, which is read to its end, or any
    #   Lota::Data, such as a Lota::Filesystem::FileData, read as
    #   love.image reads one (luax_getdata).
    #
    # Raises TypeError for anything else, and RuntimeError with LÖVE's
    # message when the file cannot be read or the module is not open.
    #
    # === Example
    #
    #   Lota::Image.compressed?("assets/ship.dds") # => true
    #   Lota::Image.compressed?("assets/ship.png") # => false
    def self.compressed?(file)
      Native::Image.compressed?(data_of(file))
    end

    # The engine's Data of +file+, as luax_getdata reads it
    # (src/modules/filesystem/wrap_Filesystem.cpp:381-411): a String names
    # a file in the game's folder, a Lota::Filesystem::File is read to its
    # end, and a Lota::Data is used as it is. :nodoc:
    private_class_method def self.data_of(file)
      case file
      when String then Native::Filesystem.file_data(file)
      when Filesystem::File then read_file(file)
      when Lota::Data then file.__send__(:native)
      else raise TypeError, "wrong argument type #{file.class} (expected filename, File, or Data)"
      end
    end

    # The engine's FileData of what +file+ reads to its end, or LÖVE's
    # message, as luax_catchexcept raises it, when it reads none. :nodoc:
    private_class_method def self.read_file(file)
      data, message = file.read(:data)
      raise message.to_s unless data.is_a?(Filesystem::FileData)

      data.__send__(:native)
    end
  end
end
