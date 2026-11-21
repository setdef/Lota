# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "lota/fuse"

# Builds Lota's app, which plays a game in one file, a .lota, or a game's
# folder, opened with it or dropped on its no-game screen, as LÖVE's own
# app plays a .love (doc/contributors/design/packaging.md, "A game in one
# file"). It is built as lota fuse builds a game, with Lota::Fuse and the
# Fledge it pins, from a folder of its own that holds no game: its entry
# script starts the game whose path its program is given, as a file
# manager gives the path of a file opened with it on Windows and Linux, or
# the file macOS opened it with, which arrives as an Apple event, and with
# none it starts the no-game screen, as the +lota+ program does
# (Lota::Boot). Like LÖVE's app, it plays a game unfused, so the game
# saves where the +lota+ program saves it, and restarts as it restarts;
# and as LÖVE's app carries LÖVE's version
# (platform/xcode/love.xcodeproj, MARKETING_VERSION), Lota's carries the
# version of the Lota it ships.
#
# LÖVE's app is named for the engine and known by the identifier
# org.love2d.love, so Lota's is named Lota and known by org.setdef.lota,
# the prefix Lota's phone host shares (ext/lota/phone/host). Its
# fledge.yml adds what lota fuse never writes: what the app opens, as
# LÖVE's app opens a .love on every system and a folder on macOS
# (vendor/love/platform/xcode/macosx/love-macosx.plist,
# CFBundleDocumentTypes, and platform/unix/love.desktop.in, whose MimeType
# names only the game's), which Fledge offers the app for without making
# it their default (Fledge's doc/desktop_apps.md, "Open files and
# folders", at Lota::Fuse::FLEDGE_REF); and build_tools, so that a game
# can be made into an app from a copy of this one with fledge build
# --from, which takes the launchers, rcedit, and NSIS on Windows, and
# AppImage's runtime on Linux, from the app it copies (Fledge's
# doc/building_from_an_app.md).
class PlayerApp < Lota::Fuse
  # The app's name.
  NAME = "Lota"

  # The app's identity, and the name of the folder its own files go in.
  IDENTITY = "Lota"

  # The reverse-DNS name the systems know the app by.
  IDENTIFIER = "org.setdef.lota"

  # A game in one file, as fledge.yml's file_associations names it: by
  # its extension, and by the MIME type a Linux desktop knows it by, of
  # the form of LÖVE's application/x-love-game.
  GAME_FILE = { "name" => "Lota game", "extensions" => ["lota"], "mime_types" => ["application/x-lota-game"] }.freeze

  # A game's folder, which LÖVE's app opens on macOS alone.
  GAME_FOLDER_TYPE = { "name" => "Folder", "folders" => true }.freeze

  # The app's own folder, which holds no game: its conf.rb names the app,
  # and its main.rb, which Fuse asks of every game, never runs.
  FILES = {
    "conf.rb" => <<~RUBY,
      # frozen_string_literal: true

      # Written by PlayerApp (tasks/player_app.rb). Read only as the app is
      # built, for its name and identity; a game played in the app reads
      # its own.
      def Lota.conf(t)
        t.identity = #{IDENTITY.dump}
        t.title = #{NAME.dump}
      end
    RUBY
    "main.rb" => <<~RUBY,
      # frozen_string_literal: true

      # Written by PlayerApp (tasks/player_app.rb). The app has no game of
      # its own, so its entry script never loads this file.
    RUBY
  }.freeze

  # Prepares to build the app into the folder +out+, shipping the Lota gem
  # at +gem_file+, or, for +nil+, the one RubyGems installed for this
  # platform (Lota::Fuse.installed_gem), and writes its folder there. The
  # gem must be one RubyGems installed, as for lota fuse, since Bundler
  # writes the checksum of an installed build alone into the lockfile
  # Fledge builds from. +platform+ is the RubyGems platform it is built
  # for, this computer's.
  def initialize(gem_file, out, platform: Lota::Fuse.this_platform)
    folder = File.join(File.expand_path(out), "player")
    FileUtils.rm_rf(folder)
    FileUtils.mkdir_p(folder)
    FILES.each { |name, text| File.write(File.join(folder, name), text) }
    options = Lota::Fuse.options(out: File.expand_path(out), identifier: IDENTIFIER, app_version: Lota::VERSION)
    super(folder, options, platform:, gem_file:)
  end

  # What the app opens: a game in one file, and on macOS a folder.
  def file_associations
    [GAME_FILE, *(@platform.include?("darwin") ? [GAME_FOLDER_TYPE] : [])].map(&:dup)
  end

  # lota fuse's settings, with what the app opens and build_tools.
  private def fledge_config(name, identity, folder)
    super.merge("file_associations" => file_associations, "build_tools" => true)
  end

  # The entry script: the game at the path the program is given, with the
  # arguments after it, or the no-game screen when it is given none.
  private def entry_script(_folder)
    <<~RUBY
      # frozen_string_literal: true

      # Written by PlayerApp (tasks/player_app.rb), which writes it again on
      # every build. Plays the game the arguments this program is given
      # name, a .lota or a folder, as the lota program does, or shows the
      # no-game screen, which starts a game dropped on it, when they name
      # none. The game is not fused, as LÖVE's app plays a .love unfused,
      # and it restarts as the lota program restarts it (Lota::Restart).
      #
      # On macOS a file opened with the app arrives as an Apple event, not
      # as an argument, so unless the program runs in a terminal it asks
      # for one first and puts it ahead of the arguments, as LÖVE's main
      # does (src/love.cpp:105-120); the game it names then starts again
      # with it when it restarts, as LÖVE keeps it.
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
      require "lota"
      argv = ARGV.dup
      unless $stdin.tty?
        dropped = Lota::Native.check_drop_events
        argv.unshift(dropped) unless dropped.empty?
      end
      exit Lota::Boot.new(nil, argv).call
    RUBY
  end
end
