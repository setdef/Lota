# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "rbconfig"

# The programs ext/lota/extconf.rb names to CMake, recorded so that the
# extension's builds are configured again when one of them is another.
#
# rake-compiler keeps the extension's build in a folder named after
# RUBY_VERSION (tasks/native.rake), and runs extconf.rb only when the
# Makefile there is missing or older than what it depends on. extconf.rb
# names three programs by their paths: the Ruby (-DRuby_EXECUTABLE), the
# ninja on PATH (-DCMAKE_MAKE_PROGRAM), and, in the Makefile, the cmake
# that configured the tree. So when a version manager installs any of
# them again in another folder, the tree went on with the old ones: a
# second Ruby of the same version built against the first one's headers
# and Rice, which the package check then found outside every licensing
# record, and a ninja or cmake that had moved was run from where it no
# longer is. FILE records all three, rewritten only when one of them is
# another, and the extension's Makefiles depend on it.
#
# None of them changes what a compile command holds but the Ruby's
# headers, which CMake tracks, so configuring again in place is enough.
# A changed compiler is another matter: on Linux it builds tmp/ afresh
# (CompilerStamp).
class ToolStamp
  # The record, in tmp/.
  FILE = ".tools"

  # The programs, one to a line: +ruby+, and cmake and ninja as +which+
  # (a command name to its path, or nil) finds them.
  def self.describe(ruby:, which:)
    lines = ["ruby #{ruby}", *%w[cmake ninja].map { |tool| "#{tool} #{which.call(tool) || 'missing'}" }]
    "#{lines.join("\n")}\n"
  end

  # Where +name+ is on +env+'s PATH, as extconf.rb's find_executable finds
  # it, or nil.
  def self.which(name, env = ENV)
    names = [name, "#{name}#{RbConfig::CONFIG['EXEEXT']}"].uniq
    env.fetch("PATH", "").split(File::PATH_SEPARATOR).product(names).map { |dir, file| File.join(dir, file) }
      .find { |path| File.executable?(path) && !File.directory?(path) }
  end

  # [tmp] The build tree.
  # [tools] The description of the programs there are now.
  def initialize(tmp:, tools:)
    @tmp = tmp
    @tools = tools
  end

  # Where the record is.
  def path
    File.join(@tmp, FILE)
  end

  # Records the programs unless the record already names them; answers
  # :kept or :recorded.
  def refresh
    return :kept if File.exist?(path) && File.read(path) == @tools

    FileUtils.mkdir_p(@tmp)
    File.write(path, @tools)
    :recorded
  end
end
