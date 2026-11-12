# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "shellwords"

# The compilers that built tmp/, and a clean build when they change.
#
# Lota builds with the C and C++ compilers CMake finds (CC and CXX, else cc
# and c++), as a contributor's distribution gives them. A build tree keeps
# the compilers it was configured with, in CMake's caches and in Lota's own
# records that its builds are configured, so once those compilers are gone
# or upgraded, as when a machine moves to a newer GCC, CMake fails in
# project() rather than configure again. So tmp/ records the compilers in
# FILE, and when they differ, tmp/ goes, once, and builds from scratch;
# ccache keeps that short. A tmp/ with no record, such as one CI restores
# from its cache, gets one and stays.
class CompilerStamp
  # The record, in tmp/.
  FILE = ".compilers"

  # The compilers +env+ names, CC and CXX, each described by where it is
  # and the first line its --version prints, as +which+ (a command name to
  # its path or nil) and +version+ (a command to that line) find them.
  def self.describe(env, which:, version:)
    lines = [["CC", "cc"], ["CXX", "c++"]].map do |variable, fallback|
      command = Shellwords.split(env.fetch(variable, "").then { |given| given.empty? ? fallback : given })
      path = which.call(command.first)
      path ? "#{variable} #{File.realpath(path)} #{version.call([path, *command.drop(1)])}" : "#{variable} missing"
    end
    "#{lines.join("\n")}\n"
  end

  # The first line +command+ --version prints.
  def self.version(command)
    output, = Open3.capture2e(*command, "--version")
    output.lines.first.to_s.strip
  rescue SystemCallError
    ""
  end

  # [tmp] The build tree.
  # [compilers] The description of the compilers there are now.
  # [out] Where it says that it starts again.
  def initialize(tmp:, compilers:, out: $stdout)
    @tmp = tmp
    @compilers = compilers
    @out = out
  end

  # Removes +tmp+ if its compilers were others, then records these;
  # answers :kept, :recorded, or :removed.
  def refresh
    record = File.join(@tmp, FILE)
    return :kept if File.exist?(record) && File.read(record) == @compilers

    outcome = File.exist?(record) ? remove : :recorded
    FileUtils.mkdir_p(@tmp)
    File.write(record, @compilers)
    outcome
  end

  private def remove
    @out.puts "Removing #{@tmp}, to build from scratch: it was built with other compilers"
    FileUtils.rm_rf(@tmp)
    :removed
  end
end
