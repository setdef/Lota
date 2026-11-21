# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"

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
# - On Windows, LÖVE asks the shell for the user's roaming application
#   data folder (src/modules/filesystem/physfs/Filesystem.cpp:659-660,
#   SHGetKnownFolderPath with FOLDERID_RoamingAppData, and for the
#   desktop, documents, and home folders beside it at 656-667). The shell
#   makes each of these from USERPROFILE as the program's environment has
#   it, and answers only for a folder that exists, so a run is given
#   USERPROFILE in its own home, which holds those folders
#   (WINDOWS_FOLDERS). Without it every run of one Windows account saves
#   in the same folder, and two runs at once overwrite and remove each
#   other's files.
#
# LOTA_TEST_HOME names the home itself, for alsoft.conf and for the tests.
module TestHome
  # Whether the tests run on Linux, or on Windows, rather than macOS.
  LINUX = RUBY_PLATFORM.include?("linux")
  WINDOWS = Gem.win_platform?

  # The folders of a Windows home that the shell answers for: the roaming
  # and local application data folders, which APPDATA and LOCALAPPDATA
  # also name, the desktop, and the documents.
  WINDOWS_FOLDERS = %w[AppData/Roaming AppData/Local Desktop Documents].freeze

  # The folder LÖVE adds under the application data folder for a game run
  # by the love program, not fused (src/modules/filesystem/Filesystem.h:36-54),
  # and Lota's for a game run by the lota program (doc/contributors/design/game.md):
  # each program's name, as LÖVE writes its own on each system.
  LOVE_FOLDER = LINUX ? "love" : "LOVE"
  LOTA_FOLDER = LINUX ? "lota" : "Lota"

  # The environment that gives a program +home+. On Windows it first makes
  # the home's folders, since the shell answers for none that is missing.
  def self.environment(home)
    system = if LINUX then { "XDG_DATA_HOME" => File.join(home, ".local/share") }
    elsif WINDOWS then windows_environment(home)
    else { "CFFIXED_USER_HOME" => home }
    end
    { "LOTA_TEST_HOME" => home, **system }
  end

  # USERPROFILE, APPDATA, and LOCALAPPDATA in +home+, with Windows'
  # separators, once the folders they name exist.
  private_class_method def self.windows_environment(home)
    WINDOWS_FOLDERS.each { |folder| FileUtils.mkdir_p(File.join(home, folder)) }
    profile = home.tr("/", "\\")
    {
      "USERPROFILE" => profile,
      "APPDATA" => "#{profile}\\AppData\\Roaming",
      "LOCALAPPDATA" => "#{profile}\\AppData\\Local",
    }
  end

  # The system's application data folder (LÖVE's COMMONPATH_USER_APPDATA)
  # for a program given +home+.
  def self.application_data(home)
    return File.join(home, "AppData/Roaming") if WINDOWS

    File.join(File.realpath(home), LINUX ? ".local/share" : "Library/Application Support")
  end

  # +path+ as LÖVE gives a save directory: on Windows with Windows'
  # separators, since it makes it canonical with std::filesystem's
  # weakly_canonical (src/modules/filesystem/Filesystem.cpp:194-204, which
  # physfs/Filesystem.cpp:615 calls), whose string is the system's.
  def self.system_path(path)
    WINDOWS ? path.tr("/", "\\") : path
  end

  # The folders macOS makes in every home, which LÖVE's user common paths
  # name (COMMONPATH_USER_DESKTOP and COMMONPATH_USER_DOCUMENTS, through
  # src/common/apple.mm) and Lövetest's mountCommonPath test mounts, as it
  # mounts them in the home of LÖVE's CI runner. On Linux a run keeps its
  # own home, so they are the system's.
  HOME_FOLDERS = %w[Desktop Documents].freeze

  # Gives this process, and each program it starts, the home +home+, with
  # the folders a home has on macOS. mise, which installs the tools the
  # tests run (mise.toml), finds them under XDG_DATA_HOME on Linux and
  # under the local application data folder on Windows, unless told where
  # they are, so there it is told first, from where it would look now.
  def self.enter(home)
    if LINUX
      ENV["MISE_DATA_DIR"] ||= File.join(ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local/share")), "mise")
    elsif WINDOWS
      ENV["MISE_DATA_DIR"] ||= File.join(ENV["LOCALAPPDATA"], "mise") if ENV.key?("LOCALAPPDATA")
    else
      HOME_FOLDERS.each { |folder| FileUtils.mkdir_p(File.join(home, folder)) }
    end
    ENV.update(environment(home))
  end
end
