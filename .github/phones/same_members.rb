# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Whether two static archives hold the same members, in the same order,
# with the same names and bytes, whatever dates, owners, and modes their
# headers record: ar(5)'s format, with BSD's long names ("#1/LENGTH",
# the name first in the data) and GNU's ("/OFFSET" into the "//" table).
# Exits 0 when they do, and 1, naming the first difference, when not.
#
# Usage: ruby same_members.rb ONE.a TWO.a

def members(path)
  data = File.binread(path)
  raise "#{path} is not an archive" unless data.start_with?("!<arch>\n")

  offset = 8
  names = nil
  list = []
  while offset + 60 <= data.bytesize
    header = data.byteslice(offset, 60)
    name = header[0, 16].rstrip
    size = Integer(header[48, 10].strip)
    body = data.byteslice(offset + 60, size)
    if (length = name[%r{\A#1/(\d+)\z}, 1])
      name = body.byteslice(0, Integer(length)).delete("\0")
      body = body.byteslice(Integer(length)..)
    elsif name == "//"
      names = body
    elsif (index = name[%r{\A/(\d+)\z}, 1]) && names
      name = names.byteslice(Integer(index)..)[%r{\A[^/\n]*}]
    end
    list << [name, body] unless name == "//"
    offset += 60 + size + (size.odd? ? 1 : 0)
  end
  list
end

one, two = ARGV.map { |path| members(path) }
if one.size != two.size
  puts "#{ARGV[0]} holds #{one.size} members, #{ARGV[1]} #{two.size}"
  exit 1
end
one.zip(two).each_with_index do |((name, body), (other_name, other_body)), index|
  next if name == other_name && body == other_body

  puts "member #{index}: #{name} (#{body.bytesize} bytes) and #{other_name} (#{other_body.bytesize} bytes) differ"
  exit 1
end
puts "the same #{one.size} members"
