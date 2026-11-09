# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Image
    # Reads a compressed image into a Lota::Image::CompressedImageData, as
    # love.image.newCompressedData does, and matches what it reads.
    #
    # LÖVE names the factory newCompressedData, though what it makes is a
    # CompressedImageData, and love.image has no CompressedData class of
    # its own (love.data's CompressedData, Lota::Data::CompressedData, is
    # another thing: bytes squeezed by zlib or LZ4). So CompressedData is a
    # module, as Lota::Graphics::Image is (rule 2 of
    # doc/contributors/design/translation.md), whose +new+ returns a
    # CompressedImageData. Only this factory makes one, so
    # <tt>CompressedData === data</tt> is true of every CompressedImageData, and
    # <tt>when CompressedData</tt> works in a +case+.
    #
    # === Examples
    #
    #   compressed = Lota::Image::CompressedData.new("assets/ship.dds")
    #   compressed.class # => Lota::Image::CompressedImageData
    #
    #   case data
    #   when Lota::Image::CompressedData then data.mipmap_count
    #   end
    module CompressedData
      # Reads the compressed image in +file+, matching
      # love.image.newCompressedData (src/modules/image/wrap_Image.cpp,
      # w_newCompressedData), with the first of LÖVE's format handlers
      # that can parse it: DDS, KTX, PVR, PKM, or ASTC.
      #
      # [file] String name of a file in the game's folder, a
      #   Lota::Filesystem::File, which is read to its end, or any
      #   Lota::Data, such as a Lota::Filesystem::FileData, read as
      #   love.image reads one (luax_getdata).
      #
      # Raises TypeError for anything else, and RuntimeError with LÖVE's
      # message when the file cannot be read, when no handler can parse it
      # ("Could not parse compressed data: Unknown format."), or when the
      # module is not open. Lota::Image.compressed? asks first.
      #
      # === Example
      #
      #   Lota::Image::CompressedData.new("assets/ship.dds").format # => :DXT1
      def self.new(file)
        native = Native::Image.new_compressed_data(Image.__send__(:data_of, file))
        CompressedImageData.__send__(:from_native, native)
      end

      # Whether +object+ is a Lota::Image::CompressedImageData, which only
      # CompressedData.new makes. Anything else is not.
      #
      # === Example
      #
      #   Lota::Image::CompressedData === Lota::Image::CompressedData.new("assets/ship.dds") # => true
      #   Lota::Image::CompressedData === Lota::Image::ImageData.new(1, 1)                 # => false
      def self.===(object)
        case object
        when CompressedImageData then true
        else false
        end
      end
    end
  end
end
