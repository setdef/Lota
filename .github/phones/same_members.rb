# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Whether two static archives hold the same members, in the same order,
# with the same names and bytes, whatever dates, owners, and modes their
# headers record: ar(5)'s format, with BSD's long names ("#1/LENGTH",
# the name first in the data) and GNU's ("/OFFSET" into the "//" table).
#
# One difference is forgiven, and said: the name of the temporary folder
# fledge build compiles a gem's extension in (Dir.mktmpdir's
# ".fledge-build-DATE-PID-RANDOM"), which a compiler's debug information
# records and which no two builds share. A member that differs in
# anything else fails.
#
# Exits 0 when they match, and 1 when not, naming every member that
# differs.
#
# Usage: ruby same_members.rb ONE.a TWO.a

# Fledge's temporary build folder's name, which differs in every build.
FLEDGE_WORK = /\.fledge-build-\d{8}-\d+-[a-z0-9]+/n

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
forgiven = []
different = []
one.zip(two).each_with_index do |((name, body), (other_name, other_body)), index|
  next if name == other_name && body == other_body

  if name == other_name && body.gsub(FLEDGE_WORK, ".fledge-build") == other_body.gsub(FLEDGE_WORK, ".fledge-build")
    forgiven << name
  else
    different << "member #{index}: #{name} (#{body.bytesize} bytes) and #{other_name} (#{other_body.bytesize} bytes)"
  end
end
unless different.empty?
  puts "#{different.size} of #{one.size} members differ: #{different.join('; ')}"
  exit 1
end
print "the same #{one.size} members"
print ", but for the name of fledge build's temporary folder in #{forgiven.join(', ')}" unless forgiven.empty?
puts
