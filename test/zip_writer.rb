# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"

# Writes a zip archive of stored entries, as the tests of a .lota need
# one, with any name, those no zip tool would write among them. Ruby's
# standard library has Zlib but writes no zip, and the build machines need
# no zip program. Each entry is made on Unix, so PhysFS keeps a backslash
# in its name as it is (physfs_archiver_zip.c, zip_convert_dos_path), and
# names are marked UTF-8 (general purpose flag bit 11).
module ZipWriter
  # The Unix mode bits a zip keeps in an entry's external attributes.
  FILE = 0o100644
  DIRECTORY = 0o040755
  SYMLINK = 0o120777

  # Writes the archive +path+ holding +entries+: a Hash of each entry's
  # name to its contents, a String for a file, +:directory+ for a folder,
  # whose name gains a "/" at its end, or <tt>[:symlink, target]</tt> for a
  # symbolic link.
  def self.write(path, entries)
    local = +"".b
    central = +"".b
    entries.each do |name, value|
      mode, data = case value
      in :directory then [DIRECTORY, ""]
      in [:symlink, String => target] then [SYMLINK, target]
      in String then [FILE, value]
      end
      name = ((value == :directory) ? "#{name.chomp('/')}/" : name).b
      data = data.b
      crc = Zlib.crc32(data)
      offset = local.bytesize
      local << [0x04034b50, 20, 0x0800, 0, 0, 0x21, crc, data.bytesize, data.bytesize, name.bytesize, 0].pack("VvvvvvVVVvv")
      local << name << data
      fields = [0x02014b50, (3 << 8) | 20, 20, 0x0800, 0, 0, 0x21, crc, data.bytesize, data.bytesize, name.bytesize]
      central << [*fields, 0, 0, 0, 0, mode << 16, offset].pack("VvvvvvvVVVvvvvvVV") << name
    end
    ending = [0x06054b50, 0, 0, entries.size, entries.size, central.bytesize, local.bytesize, 0].pack("VvvvvVVv")
    File.binwrite(path, local + central + ending)
  end
end
