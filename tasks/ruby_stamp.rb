# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"

# The Ruby that runs rake, recorded so that the extension's builds are
# configured again for another.
#
# rake-compiler keeps the extension's build in a folder named after
# RUBY_VERSION (tasks/native.rake), and runs ext/lota/extconf.rb, which
# names the Ruby to CMake (-DRuby_EXECUTABLE), only when the Makefile
# there is missing or older than what it depends on. So a second Ruby of
# the same version, as when a version manager installs it again in
# another folder, went on building with the Makefile and CMake cache the
# first one configured, against the first one's headers and Rice, and the
# package check then found those headers outside every licensing record.
# FILE records the Ruby, rewritten only when the Ruby is another, and the
# extension's Makefiles depend on it.
class RubyStamp
  # The record, in tmp/.
  FILE = ".ruby"

  # [tmp] The build tree.
  # [ruby] The Ruby that runs rake, as RbConfig.ruby names it.
  def initialize(tmp:, ruby:)
    @tmp = tmp
    @ruby = ruby
  end

  # Where the record is.
  def path
    File.join(@tmp, FILE)
  end

  # Records the Ruby unless the record already names it; answers :kept
  # or :recorded.
  def refresh
    return :kept if File.exist?(path) && File.read(path) == @ruby

    FileUtils.mkdir_p(@tmp)
    File.write(path, @ruby)
    :recorded
  end
end
