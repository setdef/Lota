# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A home of a test run's own, for what LÖVE's filesystem saves and what
# OpenAL Soft's wave file writer writes (test/alsoft.conf), so that a test
# that saves starts with nothing saved and leaves nothing in yours. Each
# system finds the folder LÖVE saves in from a variable of its own, which
# a run is given:
#
# - On macOS, Foundation reads the home directory from CFFIXED_USER_HOME
#   when it is set, and LÖVE saves under the home's Library/Application
#   Support (src/common/apple.mm, getUserDirectory).
# - On Linux, LÖVE saves under XDG_DATA_HOME when it is set, and under the
#   home's .local/share when it is not
#   (src/modules/filesystem/physfs/Filesystem.cpp:721-727), so a run is
#   given the first, pointing at the second in its own home.
#
# LOTA_TEST_HOME names the home itself, for alsoft.conf and for the tests.
module TestHome
  # Whether the tests run on Linux rather than macOS.
  LINUX = RUBY_PLATFORM.include?("linux")

  # The folder LÖVE adds under the application data folder for a game run
  # by the love program, not fused (src/modules/filesystem/Filesystem.h:36-54),
  # and Lota's for a game run by lota run (ADR 003, section 8): each
  # program's name, as LÖVE writes its own on each system.
  LOVE_FOLDER = LINUX ? "love" : "LOVE"
  LOTA_FOLDER = LINUX ? "lota" : "Lota"

  # The environment that gives a program +home+.
  def self.environment(home)
    system = LINUX ? { "XDG_DATA_HOME" => File.join(home, ".local/share") } : { "CFFIXED_USER_HOME" => home }
    { "LOTA_TEST_HOME" => home, **system }
  end

  # The system's application data folder (LÖVE's COMMONPATH_USER_APPDATA)
  # for a program given +home+.
  def self.application_data(home)
    File.join(File.realpath(home), LINUX ? ".local/share" : "Library/Application Support")
  end

  # Gives this process, and each program it starts, the home +home+. mise,
  # which installs the tools the tests run (mise.toml), finds them under
  # XDG_DATA_HOME too, unless told where they are, so on Linux it is told
  # first, from where it would look now.
  def self.enter(home)
    if LINUX
      ENV["MISE_DATA_DIR"] ||= File.join(ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local/share")), "mise")
    end
    ENV.update(environment(home))
  end
end
