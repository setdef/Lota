# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"

module Parity
  # A frame's 8-bit RGBA pixels as a PNG file (PNG Specification, Third
  # Edition): its signature, then an IHDR, one IDAT, and an IEND chunk,
  # each with its length and CRC, with every row unfiltered. The probe
  # saves the frame Lota showed this way, beside LÖVE's, when they differ,
  # so the two can be looked at side by side.
  module PNG
    SIGNATURE = "\x89PNG\r\n\x1a\n".b

    # Writes +rgba+, +width+ by +height+ pixels of 4 bytes each, row by row
    # from the top, to +path+.
    def self.write(path, width, height, rgba)
      rows = Array.new(height) { |row| "\0".b + rgba.byteslice(row * width * 4, width * 4) }.join
      header = [width, height, 8, 6, 0, 0, 0].pack("NNCCCCC")
      File.binwrite(path, SIGNATURE + chunk("IHDR", header) + chunk("IDAT", Zlib::Deflate.deflate(rows)) +
        chunk("IEND", "".b))
    end

    def self.chunk(type, data)
      [data.bytesize].pack("N") + type.b + data + [Zlib.crc32(type.b + data)].pack("N")
    end
    private_class_method :chunk
  end
end
