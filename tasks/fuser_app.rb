# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "rbconfig"
require "lota"
require "lota/fuse"
require "lota/fuser"

# Builds the fuser app, which makes a game in one file dropped on it into an
# app of its own (Lota::Fuser; doc/contributors/design/packaging.md, "A
# game in one file"), as lota fuse builds a game: the fuser is a Lota game,
# its window Lota::Fuser::Screen, whose Gemfile ships Lota and the Fledge
# Lota::Fuse builds with, since fledge build --from builds only from an app
# the same Fledge release built (Fledge's lib/fledge/built_app.rb,
# BuiltApp#check, at Lota::Fuse::FLEDGE_REF).
#
# Its fledge.yml adds what lota fuse never writes and Fledge's guide asks of
# an app that builds apps (doc/building_from_an_app.md): build_tools, so a
# Windows fuser carries the launchers, rcedit, and NSIS that --from takes,
# and a Linux one AppImage's runtime; and a file association for .lota, so
# macOS hands the app a game dropped on its icon, as an event its window
# receives. Its entry script makes an app when its program is given
# Lota::Fuser::BUILD, before anything opens a window, and otherwise starts
# the window.
#
# The app's name, identity, identifier, and file type's name are NAME,
# IDENTITY, IDENTIFIER, and FILE_TYPE. The fuser needs no sound, so its
# conf.rb turns the audio and sound modules off.
class FuserApp < Lota::Fuse
  # The app's name.
  NAME = "Lota Fuser"

  # The app's identity, under which it saves, and the folder of its game.
  IDENTITY = "LotaFuser"

  # The reverse-DNS name the systems know the app by, in the form Fledge
  # gives its own apps (com.setdef.fledge.NAME).
  IDENTIFIER = "com.setdef.lota.Fuser"

  # The name the systems give a .lota in the fuser's "Open With".
  FILE_TYPE = "Lota game"

  # The fuser's game: its window's settings, and the window, which is
  # Lota::Fuser::Screen.
  GAME = {
    "conf.rb" => <<~RUBY,
      # frozen_string_literal: true

      # Written by FuserApp (tasks/fuser_app.rb). The window's words are
      # printed as they change, each line at once.
      $stdout.sync = true

      def Lota.conf(t)
        t.identity = #{IDENTITY.dump}
        t.window.title = #{NAME.dump}
        t.window.width = 640
        t.window.height = 360
        t.modules.audio = false
        t.modules.sound = false
      end
    RUBY
    "main.rb" => <<~RUBY,
      # frozen_string_literal: true

      # Written by FuserApp (tasks/fuser_app.rb). The fuser's window, which
      # makes each game in one file dropped on it, or given to its program,
      # into an app.
      require "lota/fuser/screen"

      SCREEN = Lota::Fuser::Screen.new(File.expand_path("../..", __dir__))

      def Lota.load(arguments)
        arguments.each { |path| SCREEN.drop(path) }
      end

      def Lota.filedropped(file)
        SCREEN.drop(file.filename)
      end

      # What the window shows is printed too, each time it changes, for a
      # fuser started from a terminal.
      def Lota.update(_dt)
        shown = SCREEN.text
        SCREEN.update
        puts SCREEN.text unless SCREEN.text == shown
      end

      def Lota.draw
        Lota::Graphics.printf(SCREEN.text, 24, 24, Lota::Graphics.width - 48)
      end
    RUBY
  }.freeze

  # Prepares to build the fuser into the folder +out+, shipping the Lota
  # gem at +gem_file+, and writes its game, with a Gemfile and its
  # lockfile, into +out+'s GAME_SOURCE folder.
  def initialize(gem_file, out)
    game = File.join(File.expand_path(out), "fuser-game")
    super(game, FuserApp.options(out), gem_file:)
    write_game(game, gem_file)
  end

  # The options lota fuse builds the fuser with, into the folder +out+: the
  # fuser's identifier, and the version of the Lota it ships as its own.
  def self.options(out)
    Lota::Fuse.options(out:, identifier: IDENTIFIER, app_version: Lota::VERSION)
  end

  # The settings of fledge.yml: lota fuse's, with build_tools and the file
  # association for a .lota.
  private def fledge_config(name, identity, folder)
    super.merge("build_tools" => true, "file_associations" => [{ "name" => FILE_TYPE, "extensions" => ["lota"] }])
  end

  # The entry script: Lota::Fuser.main for a program given
  # Lota::Fuser::BUILD, and otherwise the fuser's window, as lota fuse
  # starts a game.
  private def entry_script(folder)
    script = super
    build = <<~RUBY
      if ARGV.first == #{Lota::Fuser::BUILD.dump}
        require "lota/fuser"
        exit Lota::Fuser.main(__dir__, ARGV.drop(1))
      end
    RUBY
    script.sub(/^exit Lota::Boot/) { "#{build}#{$&}" }
  end

  # Writes the fuser's game into +game+, with a Gemfile that ships Lota,
  # from the gem at +gem_file+ in its vendor/cache, and Fledge, and locks
  # it, as a game's developer would.
  private def write_game(game, gem_file)
    FileUtils.rm_rf(game)
    cache = File.join(game, "vendor", "cache")
    FileUtils.mkdir_p(cache)
    GAME.each { |file, text| File.write(File.join(game, file), text) }
    FileUtils.cp(gem_file, cache)
    File.write(File.join(game, "Gemfile"), gemfile(IDENTITY, nil))
    unless system(environment(game), RbConfig.ruby, Gem.bin_path("bundler", "bundle"), "lock", chdir: game)
      raise Error, "Bundler could not lock the fuser's gems in #{game}."
    end

    lockfile = File.join(game, "Gemfile.lock")
    File.write(lockfile, FuserApp.with_checksum(File.read(lockfile), "lota", gem_file))
  end

  # The Gemfile of the fuser's game and of its project, the same file: it
  # asks for Lota and Fledge alone, rather than evaluating the game's
  # Gemfile in its folder as lota fuse's project does, because fledge
  # build --from keeps the fuser's Gemfile in every app it makes and
  # replaces the game folder it would name. Fledge comes from Git at the
  # tag Lota::Fuse builds with, as lota fuse's tools take it: from v0.15.0
  # on, Fledge judges only the compiled files a gem from Git holds as a
  # gem, and keeps its own test fixtures in an app as text (its
  # CHANGELOG.md, 0.15.0), where it had refused them.
  private def gemfile(_folder, _locked)
    <<~RUBY
      # frozen_string_literal: true

      # Written by FuserApp (tasks/fuser_app.rb).
      source "https://rubygems.org"

      gem "lota", #{Lota::VERSION.dump}
      gem "fledge", git: "#{Lota::Fuse::FLEDGE_GIT}", ref: "#{Lota::Fuse.fledge_ref}"
    RUBY
  end

  # The lockfile +lockfile+ with the SHA-256 of the gem at +gem_file+
  # after the entry of the gem named +name+ in its CHECKSUMS. Bundler
  # writes that entry empty for a gem only vendor/cache holds, unless this
  # Ruby has the gem installed, and Fledge refuses an empty one (its
  # doc/gems.md, "A gem that only vendor/cache holds"); Bundler keeps a
  # checksum written there when lota fuse locks the project again.
  #
  # === Example
  #
  #   FuserApp.with_checksum("CHECKSUMS\n  lota (1.0.0-arm64-darwin)\n", "lota", "pkg/lota-1.0.0-arm64-darwin.gem")
  #   # => "CHECKSUMS\n  lota (1.0.0-arm64-darwin) sha256=...\n"
  def self.with_checksum(lockfile, name, gem_file)
    checksum = Digest::SHA256.file(gem_file).hexdigest
    lockfile.sub(/^(CHECKSUMS\n(?:  .*\n)*?  #{Regexp.escape(name)} \([^)]+\))$/) { "#{$1} sha256=#{checksum}" }
  end
end
