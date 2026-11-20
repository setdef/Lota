# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "archive"
require_relative "fuse"
require_relative "notices"

module Lota
  # Makes a game in one file, a <tt>.lota</tt>, into an app of its own,
  # inside the fuser app, an app Fledge built that ships Lota and Fledge
  # (doc/contributors/design/packaging.md, "A game in one file").
  #
  # The person who drops a game on the fuser has no Ruby, no Bundler, no
  # Git, no compiler, and maybe no network. The fuser already holds a
  # Ruby and the gems a game may use, each built for its system, so Fledge's
  # <tt>fledge build --from</tt> makes the new app by copying the fuser:
  # it keeps the fuser's runtime, gems, Gemfile, and lockfile, puts the
  # new project in place of the fuser's, gives the copy the project's
  # name and identity, and on macOS seals it again (Fledge's
  # doc/contributors/design/desktop-apps.md, "Building from a built app",
  # at the tag Fuse::FLEDGE_REF names). The new app is as large as the
  # fuser, holds only the fuser's gems, and runs only on the system it was
  # made on.
  #
  # Fuser turns the archive into that project, as Fledge leaves it to the
  # app it builds from: it unpacks the archive with Lota::Archive, through
  # the engine's filesystem, as <tt>lota run</tt> unpacks one, and refuses
  # what Lota::Archive refuses; reads the game's conf.rb without opening a
  # window (Lota::Boot#read_settings); and writes the project as
  # <tt>lota fuse</tt> writes one for a game without a Gemfile: the game
  # in a folder named for its identity (Fuse.folder_name), so it saves
  # where LÖVE's fused game saves (doc/contributors/design/game.md),
  # <tt>fledge.yml</tt> with the app's name (Fuse.app_name) and a
  # placeholder identifier (Fuse.placeholder_identifier), the entry
  # script (Fuse.entry_script), and the app's notices, which are the
  # fuser's own, since the new app ships the very Lota gem the fuser ships,
  # at the same paths. Then it runs the +fledge+ command of the fuser's own
  # Fledge, as Fledge asks a framework to run it, with
  # <tt>RUBYOPT=-rbundler/setup</tt> and no +RUBYLIB+. On Linux, where an
  # AppImage needs +mksquashfs+, which no app may carry, the app gets no
  # installer when the computer has none, and its archive alone.
  #
  # The engine's filesystem takes one source in a process, and conf.rb
  # defines <tt>Lota.conf</tt>, so each archive is made into an app in a
  # process of its own: the fuser's own program, given BUILD, the archive,
  # and the folder to write to (Fuser.main), which the fuser's window
  # starts when a game is dropped on it.
  #
  # === Example
  #
  #   Lota::Fuser.new("Sample Game.lota", app: "Fuser.app", notices: "Fuser.app/Contents/Resources/app/NOTICES.txt",
  #     out: ".").call
  #   # => ["./Sample Game-arm64-darwin.tar.gz", "./Sample Game-arm64-darwin.dmg"]
  class Fuser
    # The error Fuser raises when it cannot make the app, with a message for
    # the person who dropped the game.
    class Error < StandardError; end

    # The argument that has the fuser's program make an app of the archive
    # after it, rather than open its window (Fuser.main).
    BUILD = "--build"

    # The folder, in the work folder, of the project Fuser writes.
    PROJECT = "project"

    # The program that writes an AppImage, which Fledge runs and no app may
    # carry, since it is under the GPL.
    MKSQUASHFS = "mksquashfs"

    # Makes the archive +arguments+ name into an app, from inside the fuser
    # whose entry script is in the folder +entry+, as that script runs it
    # when its program is given BUILD first: +arguments+ are the archive
    # and, optionally, the folder to write to, by default the archive's
    # own. Prints each path Fledge wrote, one per line, and returns 0, or
    # prints what stood in the way and returns 1.
    #
    # === Example
    #
    #   Lota::Fuser.main("Fuser.app/Contents/Resources/app", ["Sample Game.lota"]) # => 0
    def self.main(entry, arguments, out: $stdout, err: $stderr)
      archive, folder = arguments
      return usage(err) unless archive

      fuser = new(archive, app: app_folder(entry), notices: File.join(entry, Notices::FILE), out: folder || File.dirname(archive))
      fuser.call.each { |path| out.puts path }
      0
    rescue Error => e
      err.puts "lota fuser: #{e.message}"
      1
    end

    # Says how the fuser's program takes BUILD, and returns 1.
    private_class_method def self.usage(err)
      err.puts "lota fuser: #{BUILD} needs the game in one file to make an app of: #{BUILD} GAME.lota [FOLDER]"
      1
    end

    # The folder of the app <tt>fledge build</tt> wrote, as
    # <tt>fledge build --from</tt> takes it, whose entry script is in the
    # folder +entry+, its +app+ folder: on macOS the <tt>.app</tt> whose
    # <tt>Contents/Resources</tt> holds that folder, and elsewhere the
    # folder that holds it.
    #
    # === Example
    #
    #   Lota::Fuser.app_folder("/Applications/Fuser.app/Contents/Resources/app") # => "/Applications/Fuser.app"
    def self.app_folder(entry)
      contents = File.dirname(File.expand_path(entry))
      bundle = File.dirname(contents, 2)
      macos = File.basename(contents) == "Resources" && File.basename(File.dirname(contents)) == "Contents" && bundle.end_with?(".app")
      macos ? bundle : contents
    end

    # Prepares to make the game in the archive at +archive+ into an app.
    #
    # [app] String path of the fuser, the app the new one is built from.
    # [notices] String path of the fuser's notices, which the new app
    #   carries too.
    # [out] String folder Fledge writes the new app to.
    # [fledge] The command that runs Fledge, as an Array of Strings: by
    #   default this Ruby, with the +fledge+ program of the Fledge in this
    #   bundle.
    # [env] The environment, from which only +PATH+ is read.
    def initialize(archive, app:, notices:, out:, fledge: nil, env: ENV)
      @archive = File.expand_path(archive)
      @app = app
      @notices = notices
      @out = File.expand_path(out)
      @fledge = fledge
      @env = env
    end

    # Makes the app, and returns the paths Fledge reports, the archive
    # first. Raises Error when the archive, its conf.rb, or the build stands
    # in the way, saying which.
    def call
      raise Error, "found no game at #{@archive}." unless File.file?(@archive)
      raise Error, "found no notices at #{@notices} to put in the app." unless File.file?(@notices)

      Dir.mktmpdir("lota-fuser-") do |work|
        game = unpack(File.join(work, "unpacked"))
        project = File.join(work, PROJECT)
        write_project(project, game, read_settings(game))
        build(project)
      end
    end

    # The <tt>fledge.yml</tt> of the project for the app named +name+ of
    # the game whose identity is +identity+, for a computer that is Linux,
    # if +linux+, and that has +mksquashfs+, if +squashfs+.
    #
    # === Example
    #
    #   Lota::Fuser.fledge_yml("Sample Game", "SampleGame", linux: false, squashfs: false)
    #   # => "# Written by the Lota fuser.\n---\nname: Sample Game\nkind: windowed\nidentifier: com.example.SampleGame\n"
    def self.fledge_yml(name, identity, linux:, squashfs:)
      config = { "name" => name, "kind" => "windowed", "identifier" => Fuse.placeholder_identifier(identity) } #: Hash[String, ::Object]
      config["installers"] = [] if linux && !squashfs
      "# Written by the Lota fuser.\n#{YAML.dump(config)}"
    end

    # Opens the engine's filesystem with the archive as its source, as
    # <tt>lota run</tt> opens it (Lota::Boot), and unpacks the archive into
    # the folder +cache+ (Lota::Archive#unpack). Returns the folder of the
    # game.
    private def unpack(cache)
      unless Native::Filesystem.open?
        Native::Filesystem.open
        Native::Filesystem.init($PROGRAM_NAME)
      end
      begin
        Native::Filesystem.set_source(@archive)
      rescue RuntimeError
        nil
      end
      # The filesystem names a source it mounted in its own form, which may
      # not be the path given, and none that it could not mount, so
      # Lota::Boot#unpack asks only whether it names one.
      raise Error, "#{@archive} is not a game in one file: it cannot be read as a zip." if Filesystem.source.empty?

      Archive.new(@archive).unpack(cache)
    rescue Archive::Refused => e
      raise Error, e.message
    end

    # The game's settings, as its conf.rb leaves them, read without opening
    # a window.
    private def read_settings(game)
      Boot.new(game).read_settings
    rescue StandardError, ScriptError => e
      raise Error, "the game's conf.rb raised #{e.class}: #{e.message}"
    end

    # Writes the project in the folder +project+, with the game unpacked
    # in +game+ whose conf.rb leaves +settings+.
    private def write_project(project, game, settings)
      identity = Fuse.identity(settings, @archive)
      folder = Fuse.folder_name(identity)
      name = Fuse.app_name(settings, File.basename(@archive, File.extname(@archive)))
      FileUtils.mkdir_p(File.join(project, Fuse::GAME_FOLDER))
      File.rename(game, File.join(project, Fuse::GAME_FOLDER, folder))
      File.write(File.join(project, "fledge.yml"), Fuser.fledge_yml(name, identity, linux: linux?, squashfs: !executable(MKSQUASHFS).nil?))
      File.write(File.join(project, "main.rb"), Fuse.entry_script(folder))
      FileUtils.cp(@notices, File.join(project, Notices::FILE))
    end

    # Runs <tt>fledge build --from</tt> on +project+, from the fuser, into
    # the folder of #initialize's +out+, and returns the paths it printed.
    # What Fledge says goes to this program's standard error.
    private def build(project)
      command = [*fledge, "build", "--from", @app, "--out", @out, project]
      output = IO.popen({ "RUBYOPT" => "-rbundler/setup", "RUBYLIB" => nil }, command, &:read)
      raise Error, "fledge build --from failed (exit status #{$?&.exitstatus}). Fledge says above why." unless $?&.success?

      output.lines(chomp: true)
    end

    # The command that runs Fledge.
    private def fledge
      @fledge || [RbConfig.ruby, Gem.bin_path("fledge", "fledge")]
    end

    # Whether this computer runs Linux.
    private def linux?
      RbConfig::CONFIG["host_os"].to_s.include?("linux")
    end

    # The path of the program +name+ on PATH, or +nil+.
    private def executable(name)
      @env.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |folder| File.join(folder, name) }.find do |candidate|
        File.file?(candidate) && File.executable?(candidate)
      end
    end
  end
end
