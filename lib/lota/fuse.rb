# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "rbconfig"
require "rubygems/package"
require "tmpdir"
require "yaml"
require_relative "fuse/lockfile"
require_relative "notices"

module Lota
  # Turns a game folder into an app a player runs without Ruby, as LÖVE
  # fuses a game into its own executable (doc/contributors/design/packaging.md).
  #
  # A player of a Lota game has no Ruby, no Lota, and no LÖVE. Fledge
  # (github.com/setdef/Fledge) packages a Ruby program with a Ruby of its
  # own, but it builds a project, with a Gemfile, a lockfile, and an entry
  # script, and a game folder is none of those.
  #
  # Fuse writes that project and has Fledge build it. It reads the game's
  # name and <tt>t.identity</tt> from conf.rb without opening a window
  # (Lota::Boot#read_settings), copies the game into a folder named for
  # its identity, so the fused game saves where LÖVE's fused game saves
  # (doc/contributors/design/game.md), writes a Gemfile that pins Lota to this
  # version, puts the installed Lota gem in the project's <tt>vendor/cache</tt>,
  # since Lota is not on RubyGems.org, writes <tt>fledge.yml</tt> and an
  # entry script that turns YJIT on where the runtime has it, boots the
  # game fused, and starts it again when it restarts (Lota::Restart),
  # locks the bundle, writes the app's notices, and runs
  # <tt>fledge build</tt>. Fledge builds for the computer it runs on, so
  # each platform's app is built on that platform.
  #
  # Fledge runs from a Gemfile of its own, beside the project, which pins
  # it to FLEDGE_REF. Fledge reads the project's Gemfile and lockfile
  # itself, fetches each gem the app ships, checked against the
  # lockfile's checksum, and compiles those it ships with an extension
  # for the app's Ruby, leaving out the +development+ and +test+ groups.
  # So Bundler only locks the project and installs none of the game's
  # gems: a development gem with a C extension never compiles, a game
  # whose gems are pure Ruby fuses with no C compiler, and Fledge, in no
  # Gemfile of the project's, is none of the gems the app ships.
  #
  # The notices (Lota::Notices) are a file, NOTICES.txt, at the top of the
  # project, which Fledge puts in the app's +app+ folder: Lota's own
  # license statement, then each library the Lota gem the app ships
  # carries, as that gem's manifest names them, with their licenses, and
  # the text of each license. They come from that very gem, so they name
  # what this platform's app holds, and a gem without its manifest stops
  # the build. Nothing in Fuse's options changes them.
  #
  # A game with a Gemfile ships the gems it locks. Its Gemfile.lock must
  # lock this platform and, if it locks Lota, this version of it
  # (Lockfile). The project's Gemfile evaluates the game's, and adds Lota
  # if the game's does not ask for it; the project starts from
  # the game's lockfile, locked for this platform alone, and from the
  # gems in the game's <tt>vendor/cache</tt> but those built for other
  # platforms, so Bundler keeps the versions the game was made with and
  # Fledge ships them, compiling those with extensions for its runtime.
  #
  # The app leaves out the paths of LEFT_OUT, and those that match a
  # pattern of Options#exclude (<tt>--exclude</tt>), each of which is a
  # glob relative to the game's folder, matched as File.fnmatch does with
  # File::FNM_PATHNAME, so that <tt>*</tt> stays within a folder and
  # <tt>**/</tt> crosses folders, File::FNM_EXTGLOB, for
  # <tt>{a,b}</tt>, and File::FNM_DOTMATCH, so that <tt>*</tt> and
  # <tt>**</tt> match dotfiles too, as someone who writes
  # <tt>assets/*</tt> means them. A path that matches is left out whole,
  # with everything in it if it is a folder, so <tt>server</tt> leaves out
  # the folder +server+ at the top of the game, and <tt>test/**</tt>,
  # which fnmatch reads as everything in +test+, leaves +test+ itself
  # empty. A pattern that ends in a slash matches folders only. A pattern
  # that matches nothing is reported and does not stop the build. An
  # exclusion that would leave out conf.rb or main.rb, which the game
  # needs to start, stops it with an Error, before anything is
  # written. Fuse reads no file of patterns.
  #
  # Use it through <tt>lota fuse</tt>.
  #
  # === Example
  #
  #   options = Lota::Fuse.options(identifier: "com.example.SampleGame")
  #   Lota::Fuse.new("games/sample_game", options).call
  #   # => ["/home/me/dist/Sample Game-x86_64-linux.tar.gz", ...]
  class Fuse
    # The error Fuse raises when it cannot build, with a message for the
    # person who ran it.
    class Error < StandardError; end

    # What <tt>lota fuse</tt>'s options ask for.
    #
    # [out] String folder, relative to the working directory, where Fledge
    #   writes the app and Fuse writes the project it builds from.
    # [sign] String identity Fledge signs the app with (its
    #   <tt>--sign</tt>), or +nil+ for none.
    # [sign_command] String command Fledge signs a Windows app with, in
    #   place of +sign+ (its <tt>--sign-command</tt>), or +nil+, when
    #   Fledge signs a Windows app with FLEDGE_SIGN_COMMAND if that is set
    #   and +sign+ is +nil+ too. Fledge refuses it for any other system.
    # [notarize] String name of the keychain profile, which
    #   <tt>xcrun notarytool store-credentials</tt> stored, that Fledge
    #   has Apple notarize the app with after +sign+ signs it (its
    #   <tt>--notarize</tt>), or +nil+ for none. Fledge refuses it for any
    #   system but macOS, and with an ad hoc +sign+.
    # [identifier] String reverse-DNS name the system knows the app by, or
    #   +nil+ for a placeholder under IDENTIFIER_PREFIX.
    # [app_version] String version of the app, or +nil+ for Fledge's
    #   default. A game's <tt>t.version</tt> names the version of LÖVE it
    #   was written for, so it never becomes the app's
    #   (doc/contributors/design/packaging.md).
    # [icon] String path of the app's icon files in the game's folder,
    #   without their extension, as Fledge names them (<tt>icons/icon</tt>
    #   for <tt>icons/icon.icns</tt>, <tt>icons/icon.ico</tt>, and
    #   <tt>icons/icon-16.png</tt> and the other sizes), or +nil+ for none.
    # [exclude] Array of String patterns for paths the app leaves out, in
    #   addition to LEFT_OUT. See Fuse for how they match.
    #
    # Fuse refuses +sign+ with +sign_command+, and +notarize+ without
    # +sign+, before it writes anything, as Fledge refuses them as it reads
    # its command line; what Fledge refuses only as it builds, it says
    # itself.
    #
    # Make one with Fuse.options, which fills in DEFAULT_OPTIONS.
    class Options < ::Data.define(:out, :sign, :sign_command, :notarize, :identifier, :app_version, :icon, :exclude)
    end

    # The exclusions of an Options that is given none.
    NO_PATTERNS = Array.new(0, "").freeze

    # What each of Options is when <tt>lota fuse</tt> is not given it.
    DEFAULT_OPTIONS = {
      out: "dist",
      sign: nil,
      sign_command: nil,
      notarize: nil,
      identifier: nil,
      app_version: nil,
      icon: nil,
      exclude: NO_PATTERNS,
    }.freeze

    # Options with DEFAULT_OPTIONS for each that +given+ leaves out.
    #
    # === Example
    #
    #   Lota::Fuse.options(identifier: "com.example.Pong").out # => "dist"
    def self.options(**given)
      Options.new(**DEFAULT_OPTIONS, **given)
    end

    # Where Bundler fetches Fledge from, which is not on RubyGems.org.
    FLEDGE_GIT = "https://github.com/setdef/Fledge"

    # The Git tag of Fledge the project builds with. Fledge 0.5.0 was the
    # first release whose check of a gem's DLLs takes the System32
    # libraries Lota's Windows engine imports; 0.5.1 changes only phones,
    # 0.6.0 adds what a store listing asks of an app (a description, a
    # license file) without changing how the project builds, 0.7.0 has a
    # Windows app carry notices/MODIFIED.txt and stops a bare environment
    # entry from hanging the launcher on macOS and Linux, and 0.8.0
    # relicenses Fledge under the MIT license, so a Windows app no longer
    # carries that file, and retries a download and Apple's timestamp
    # server, 0.9.0 adds macOS notarization and a Windows signing
    # command, 0.10.0 changes only the exit status of
    # <tt>fledge build --from</tt>, which Fuse does not run, and the
    # names a Windows setup program gives file associations, which the
    # project declares none of, 0.11.0 takes a gem's source build when its
    # precompiled build's required_ruby_version excludes the runtime's
    # Ruby, as Bundler does, and 0.12.0 carries Ruby 4.1 in every runtime
    # (ADR 013): 4.1.0-preview1, and on Windows one day's head build of
    # RubyInstaller, which publishes no preview.
    FLEDGE_REF = "v0.12.0"

    # The environment variable that names another FLEDGE_REF, such as a
    # newer tag.
    FLEDGE_REF_VARIABLE = "LOTA_FLEDGE_REF"

    # The first parts of the placeholder identifier given to a game built
    # without <tt>--identifier</tt>: example.com is reserved for examples
    # (RFC 2606), so it names no one's app.
    IDENTIFIER_PREFIX = "com.example"

    # The platforms Lota publishes a precompiled gem for.
    PLATFORMS = %w[arm64-darwin x86_64-linux-gnu aarch64-linux-gnu x64-mingw-ucrt aarch64-mingw-ucrt].freeze

    # The folder, in the project and so in the app, that holds the folder
    # named for the game's identity, so that no identity meets a name the
    # project's own files or Fledge's take.
    GAME_FOLDER = "game"

    # The folder in Options#out that holds the project Fuse writes.
    PROJECT_FOLDER = "fuse-project"

    # The folder in Options#out that holds the Gemfile Fledge runs from,
    # beside the project rather than in it, since everything in the
    # project goes into the app.
    TOOLS_FOLDER = "fuse-tools"

    # The name LÖVE gives a game whose conf sets no title, which the app is
    # not given: it takes the game folder's name instead.
    UNTITLED = "Untitled"

    # Characters no folder name may hold on Windows, macOS, or Linux.
    UNSAFE = %r{[\x00-\x1f<>:"/\\|?*]}

    # Names Windows reserves for devices, which no folder may take.
    RESERVED = /\A(con|prn|aux|nul|com\d|lpt\d)(\..*)?\z/i

    # The folders of a game that its app leaves out, as Fledge leaves them
    # out of a project it builds (its README, Usage): its Git repository
    # and Bundler's, which hold no game.
    LEFT_OUT = %w[.git .bundle vendor/bundle vendor/cache].freeze

    # The files of a game that an exclusion may not leave out.
    REQUIRED = %w[conf.rb main.rb].freeze

    # The flags with which Options#exclude patterns match.
    EXCLUDE_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH

    # The most paths that Fuse names when it says what it left out.
    NAMED_LEFT_OUT = 10

    # Prepares to fuse the game in the folder +path+.
    #
    # [path] String path of the game's folder.
    # [options] The Options <tt>lota fuse</tt> was given.
    # [platform] The String RubyGems platform to build for, which is this
    #   computer's (Fuse.this_platform), since Fledge builds for the
    #   computer it runs on.
    # [gem_file] String path of the Lota gem to ship, or +nil+ for the one
    #   RubyGems installed for this platform (Fuse.installed_gem).
    # [bundle] The command that runs Bundler, as an Array of Strings: by
    #   default this Ruby's own, so the app gets the Ruby that runs this.
    def initialize(path, options = Fuse.options, platform: Fuse.this_platform, gem_file: nil, bundle: nil)
      @directory = File.expand_path(path)
      @options = options
      @platform = platform
      @gem_file = gem_file
      @bundle = bundle
      @left_out = [] #: Array[String]
      @matched = [] #: Array[String]
    end

    # Writes the project and builds it with <tt>fledge build</tt>,
    # printing each path Fledge reports as it reports it, and returns
    # them. Raises Error when the game, this computer, or a step of the
    # build stands in the way, saying which.
    def call
      check_game
      check_exclude
      check_signing
      platform = lota_platform
      locked = read_lockfile(platform)
      gem = @gem_file || Fuse.installed_gem(@platform)
      bundle = @bundle || bundler
      check_git
      write_project(read_settings, gem, locked)
      report_left_out
      write_tools
      lock_commands(locked, platform).each do |command|
        run(bundle, *command, folder: project, step: "Locking the project's gems", why: LOCKING)
      end
      run(bundle, "install", folder: tools, step: "Installing Fledge", why: network)
      write_notices(File.join(project, "vendor", "cache", File.basename(gem)))
      build(bundle, why: locked ? COMPILER : nil)
    end

    # What Fuse says when Bundler cannot lock the project: Bundler says
    # why, and it reads each gem's checksum from the gem servers the
    # Gemfile names (Bundler::Definition#add_checksums).
    LOCKING = "Bundler says above why. It asks the gem servers the Gemfile names for each gem's checksum, which needs " \
      "the network."

    # What Fuse says when Fledge cannot build a game that has gems: Fledge
    # says why, and the usual reason is a gem with a C extension on a
    # computer with no compiler, which Fledge needs to compile the gem for
    # its runtime (its README, Lock your gems).
    COMPILER = "Fledge says above why. A gem with a C extension compiles on this computer, which needs a C compiler: on " \
      "macOS, Xcode's command line tools (xcode-select --install); on Linux, a C compiler and make (sudo apt install " \
      "build-essential on Debian and Ubuntu); on Windows, RubyInstaller's MSYS2 tools (ridk install)."

    # The folder Fledge writes the app to, as an absolute path.
    def out
      File.expand_path(@options.out)
    end

    # The folder of the project Fuse writes, as an absolute path.
    def project
      File.join(out, PROJECT_FOLDER)
    end

    # The folder of the Gemfile Fledge runs from, as an absolute path.
    def tools
      File.join(out, TOOLS_FOLDER)
    end

    # This computer's RubyGems platform, such as <tt>"arm64-darwin-24"</tt>.
    def self.this_platform
      Gem.platforms.last.to_s
    end

    # The path of the Lota gem of this version that RubyGems installed for
    # +platform+, from the cache in each of RubyGems' folders where it
    # keeps the gem files it installed. Raises Error when there is none, as
    # when Lota runs from its own source.
    def self.installed_gem(platform)
      name = "lota-#{VERSION}-#{platform_name(platform)}.gem"
      found = Gem.path.map { |folder| File.join(folder, "cache", name) }.find { |file| File.file?(file) }
      return found if found

      raise Error, "found no installed lota-#{VERSION} gem for #{platform}. Install Lota's gem for this platform " \
        "from its release (gem install lota-#{VERSION}-PLATFORM.gem) and run lota fuse from it."
    end

    # The folder name, in the project's GAME_FOLDER, for a game whose
    # identity is +identity+: the identity, with every character no
    # system's folder name may hold an underscore, without trailing dots
    # and spaces, which Windows drops, and with an underscore after a name
    # Windows reserves. A game that sets <tt>t.identity</tt> saves under it
    # whatever its folder is called, so only a game that does not, whose
    # identity is already its folder's name, depends on this name.
    #
    # === Example
    #
    #   Lota::Fuse.folder_name("Sample Game: Deluxe") # => "Sample Game_ Deluxe"
    def self.folder_name(identity)
      name = identity.gsub(UNSAFE, "_").sub(/[. ]+\z/, "")
      name = "#{name}_" if RESERVED.match?(name)
      name.empty? ? "lotagame" : name
    end

    # The placeholder identifier for a game whose identity is +identity+:
    # IDENTIFIER_PREFIX, then the identity's letters and digits with a
    # hyphen for each run of anything else, as an identifier allows.
    #
    # === Example
    #
    #   Lota::Fuse.placeholder_identifier("sample_game") # => "com.example.sample-game"
    def self.placeholder_identifier(identity)
      part = identity.gsub(/[^A-Za-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")[0, 100].to_s.delete_suffix("-")
      "#{IDENTIFIER_PREFIX}.#{part.empty? ? 'lotagame' : part}"
    end

    # The name of the platform in PLATFORMS that the RubyGems platform
    # +platform+ is, such as <tt>"arm64-darwin"</tt> for a Mac's
    # <tt>"arm64-darwin-24"</tt> and <tt>"x86_64-linux-gnu"</tt> for
    # <tt>"x86_64-linux"</tt>, as RubyGems matches a gem's platform, or
    # +nil+ when Lota has no gem for it.
    def self.platform_name(platform)
      PLATFORMS.find do |name|
        platform == name || platform.start_with?("#{name}-") || platform == name.delete_suffix("-gnu")
      end
    end

    # The Fledge ref the project's Gemfile names: FLEDGE_REF, or the one
    # FLEDGE_REF_VARIABLE names.
    def self.fledge_ref(env = ENV.to_h)
      ref = env[FLEDGE_REF_VARIABLE].to_s.strip
      ref.empty? ? FLEDGE_REF : ref
    end

    private def check_game
      raise Error, "found no game folder at #{@directory}." unless File.directory?(@directory)
      raise Error, "#{@directory} has no main.rb, so there is no game to fuse." unless File.file?(File.join(@directory, "main.rb"))
      return unless out == @directory || [project, tools].any? { |folder| "#{@directory}/".start_with?(File.join(folder, "")) }

      raise Error, "--out can't be the game's own folder, #{@options.out}; choose one beside or inside it."
    end

    # Raises Error when an exclusion would leave out a file of
    # REQUIRED.
    private def check_exclude
      @options.exclude.each do |pattern|
        file = REQUIRED.find { |name| excludes?(pattern, name, directory: false) }
        next unless file

        raise Error, "--exclude #{pattern} would leave out #{file}, which the game needs to start"
      end
    end

    # Raises Error for the signing options Fledge refuses together, with
    # the words Fledge refuses them with (its
    # lib/fledge/cli/build/options.rb, Options.check, at FLEDGE_REF), so
    # that the build stops before it locks and fetches for minutes, not
    # after.
    private def check_signing
      raise Error, "--sign and --sign-command each sign the app; give one of them" if @options.sign && @options.sign_command
      return unless @options.notarize && !@options.sign

      raise Error, "--notarize needs --sign IDENTITY, the Developer ID Application identity Apple notarizes"
    end

    # Whether +pattern+ matches the path +relative+, a folder's if
    # +directory+.
    private def excludes?(pattern, relative, directory:)
      return false if pattern.end_with?("/") && !directory

      File.fnmatch(pattern.delete_prefix("./").chomp("/"), relative, EXCLUDE_FLAGS)
    end

    # Says which paths of the game were left out by Options#exclude, and
    # warns of each pattern that matched none.
    private def report_left_out
      @options.exclude.each do |pattern|
        warn "lota fuse: --exclude #{pattern} matched nothing in the game's folder." unless @matched.include?(pattern)
      end
      return if @left_out.empty?

      named = @left_out.sort.first(NAMED_LEFT_OUT).join(", ")
      more = @left_out.size - NAMED_LEFT_OUT
      named += ", and #{more} more" if more.positive?
      puts "Left out #{@left_out.size} #{(@left_out.size == 1) ? 'path' : 'paths'} of the game: #{named}"
    end

    # The game's settings, as its conf.rb leaves them, read without
    # opening a window.
    private def read_settings
      Boot.new(@directory).read_settings
    rescue StandardError, ScriptError => e
      raise Error, "#{File.join(@directory, 'conf.rb')} raised #{e.class}: #{e.message}"
    end

    # The platform of PLATFORMS this computer is. Raises Error when Lota has
    # no gem for it.
    private def lota_platform
      name = Fuse.platform_name(@platform)
      return name if name

      raise Error, "Lota has no gem for #{@platform}, so it cannot fuse a game here. " \
        "It builds on #{PLATFORMS.join(', ')}."
    end

    # The game's Gemfile.lock, read, or +nil+ for a game without a Gemfile.
    # Raises Error when there is a Gemfile but no lockfile, or the lockfile
    # does not lock +platform+, or locks a Lota other than this one.
    private def read_lockfile(platform)
      gemfile = File.join(@directory, "Gemfile")
      return unless File.file?(gemfile)

      path = "#{gemfile}.lock"
      unless File.file?(path)
        raise Error, "#{gemfile} has no Gemfile.lock beside it, so lota fuse can't tell which versions of its gems the game " \
          "runs with. Run bundle install in #{@directory}, then fuse again."
      end
      Lockfile.read(path).tap { |locked| check_lockfile(locked, path, platform) }
    end

    private def check_lockfile(locked, path, platform)
      unless locked.covers?(platform)
        raise Error, "#{path} locks no gems for #{platform}, the platform this app is built for. Run bundle lock " \
          "--add-platform #{platform} in #{@directory}, with each gem that platform needs in its vendor/cache, then fuse again."
      end
      versions = locked.versions("lota")
      return if (versions - [VERSION]).empty?

      raise Error, "#{path} locks lota #{versions.join(', ')}, and this is lota fuse #{VERSION}. Fuse the game with the Lota it " \
        "locks, or move it to #{VERSION}: put lota-#{VERSION}-#{platform}.gem in its vendor/cache and run bundle update lota " \
        "in #{@directory}."
    end

    private def check_git
      return if executable("git")

      raise Error, "Fledge is not on RubyGems.org, so Bundler fetches it from #{FLEDGE_GIT} with Git, " \
        "and found no git on PATH. Install Git and try again."
    end

    # Writes the app's notices into the project (Lota::Notices), from the
    # Lota gem it ships, at +gem+: its manifest and license texts, with the
    # paths where Fledge puts that gem in the app. Raises Error when the
    # gem has no manifest.
    private def write_notices(gem)
      Dir.mktmpdir("lota-fuse-notices-") do |dir|
        package = Gem::Package.new(gem)
        package.extract_files(dir, Notices::MANIFEST)
        package.extract_files(dir, "#{Notices::LICENSES}/*")
        notices = Notices.read(dir, platform: lota_platform, gem_folder: gem_folder(File.basename(gem, ".gem")))
        File.write(File.join(project, Notices::FILE), notices.text)
      end
    rescue Notices::Error => e
      raise Error, "lota fuse writes the app's #{Notices::FILE} from the Lota gem it ships, and #{File.basename(gem)} cannot " \
        "give them: #{e.message}. Fuse with a Lota gem that carries its notices."
    end

    # Where Fledge puts the gem whose full name is +name+ in the app,
    # relative to the folder that holds its +app+ folder: in the runtime's
    # gem folder for this Ruby's ABI, which on Windows is inside the
    # runtime's +ruby+ folder (Fledge's doc/licensing.md, "Your gems").
    private def gem_folder(name)
      folders = ["lib", "ruby", "gems", RbConfig::CONFIG.fetch("ruby_version"), "gems", name]
      folders.unshift("ruby") if lota_platform.include?("mingw")
      folders.join("/")
    end

    # This Ruby's own Bundler.
    private def bundler
      [RbConfig.ruby, Gem.bin_path("bundler", "bundle")]
    rescue Gem::LoadError
      raise Error, "found no Bundler for #{RbConfig.ruby}; install it with gem install bundler."
    end

    # The path of the program +name+ on PATH, with Windows' extensions for
    # a program, or +nil+.
    private def executable(name)
      extensions = Gem.win_platform? ? ENV.fetch("PATHEXT", ".EXE;.BAT;.CMD").split(";") : [""]
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |folder|
        extensions.each do |extension|
          candidate = File.join(folder, "#{name}#{extension}")
          return candidate if File.file?(candidate) && File.executable?(candidate)
        end
      end
      nil
    end

    private def write_project(settings, gem, locked)
      identity = identity(settings)
      folder = Fuse.folder_name(identity)
      FileUtils.rm_rf(project)
      cache = File.join(project, "vendor", "cache")
      FileUtils.mkdir_p(cache)
      copy_cache(cache, locked) if locked
      lota = File.join(cache, File.basename(gem))
      FileUtils.cp(gem, lota) unless File.exist?(lota)
      copy_game(@directory, File.join(project, GAME_FOLDER, folder))
      FileUtils.cp(File.join(@directory, "Gemfile.lock"), File.join(project, "Gemfile.lock")) if locked
      File.write(File.join(project, "Gemfile"), gemfile(folder, locked))
      File.write(File.join(project, "fledge.yml"), fledge_yml(name(settings), identity, folder))
      File.write(File.join(project, "main.rb"), entry_script(folder))
    end

    # Copies the game's <tt>vendor/cache</tt> to +cache+, the project's,
    # but for the builds +locked+ locks for platforms other than this one,
    # which Bundler would keep in the project's lockfile without a
    # checksum, and which Fledge refuses (its README, "A gem that only
    # vendor/cache holds"). A build of Lota the game holds is the one the
    # project ships, since its lockfile may hold that build's checksum.
    private def copy_cache(cache, locked)
      from = File.join(@directory, "vendor", "cache")
      return unless File.directory?(from)

      others = locked.other_builds(lota_platform)
      Dir.each_child(from) do |child|
        FileUtils.cp_r(File.join(from, child), cache, preserve: true) unless others.include?(child)
      end
    end

    # The Bundler commands that lock the project, each as what follows
    # <tt>bundle</tt>. A game's lockfile, which the project starts from,
    # first loses its other platforms, whose builds the project does not
    # hold (#copy_cache), in a command of its own, since Bundler resolves
    # for every platform a lockfile names before it removes any when it is
    # also asked for checksums (Bundler::CLI::Lock#run); then it gains
    # +platform+, in the form Lota's gem names it, which Fledge's runtime
    # takes.
    private def lock_commands(locked, platform)
      return [%w[lock --add-checksums]] unless locked

      others = locked.other_platforms(platform)
      [*(others.empty? ? [] : [["lock", "--remove-platform", *others]]), ["lock", "--add-platform", platform, "--add-checksums"]]
    end

    # The game's identity: its <tt>t.identity</tt>, or the name
    # <tt>lota run</tt> gives a game that sets none (Boot.folder_identity).
    private def identity(settings)
      identity = settings.identity
      identity = identity.to_s if identity.is_a?(Symbol)
      return identity if identity.is_a?(String) && !identity.strip.empty?

      Boot.folder_identity(@directory)
    end

    # The app's name: the window's title, or the game's, or, when conf.rb
    # leaves the title LÖVE's default, the game folder's name.
    private def name(settings)
      window = settings.window
      title = window.title if window.is_a?(Settings::Window)
      title = (title || settings.title).to_s.strip
      (title.empty? || title == UNTITLED) ? File.basename(@directory) : title
    end

    # Copies the game's files, but not the folders of LEFT_OUT, the paths
    # that Options#exclude matches, or the folder this build writes to,
    # should it be inside the game's folder.
    private def copy_game(from, to)
      FileUtils.mkdir_p(to)
      Dir.each_child(from) do |child|
        source = File.join(from, child)
        next if source == out || LEFT_OUT.any? { |name| source == File.join(@directory, name) }
        next if excluded?(source)

        target = File.join(to, child)
        if File.directory?(source)
          copy_game(source, target)
        else
          FileUtils.cp(source, target, preserve: true)
        end
      end
    end

    # Whether Options#exclude leaves out the path +source+ in the game,
    # noting it and the patterns that matched it.
    private def excluded?(source)
      relative = source.delete_prefix("#{@directory}/")
      directory = File.directory?(source)
      hits = @options.exclude.select { |pattern| excludes?(pattern, relative, directory:) }
      return false if hits.empty?

      @matched.concat(hits)
      @left_out << relative
      true
    end

    # The project's Gemfile: the game's, evaluated where the game's copy
    # is, so that its paths are read from there, or else a source of
    # gems; then Lota, unless the game's asks for it.
    private def gemfile(folder, locked)
      game = locked ? "eval_gemfile #{"#{GAME_FOLDER}/#{folder}/Gemfile".inspect}" : 'source "https://rubygems.org"'
      lines = ["# frozen_string_literal: true", "", "# Written by lota fuse, which writes it again on every build.", game]
      lines.push("", %(gem "lota", "#{VERSION}")) unless locked&.depends_on?("lota")
      "#{lines.join("\n")}\n"
    end

    # Writes the Gemfile Fledge runs from, which holds Fledge alone, in a
    # folder of its own. Bundler writes its lockfile there as it installs
    # Fledge, on every build, so the build takes FLEDGE_REF as it is named
    # now.
    private def write_tools
      FileUtils.rm_rf(tools)
      FileUtils.mkdir_p(tools)
      File.write(File.join(tools, "Gemfile"), <<~RUBY)
        # frozen_string_literal: true

        # Written by lota fuse, which writes it again on every build. Fledge
        # runs from this bundle, apart from the project's, so that Bundler
        # installs none of the game's gems and Fledge is none of the app's.
        gem "fledge", git: "#{FLEDGE_GIT}", ref: "#{Fuse.fledge_ref}"
      RUBY
    end

    private def fledge_yml(name, identity, folder)
      config = {
        "name" => name,
        "kind" => "windowed",
        "identifier" => @options.identifier || Fuse.placeholder_identifier(identity),
      }
      version = @options.app_version
      config["version"] = version if version
      icon = @options.icon
      config["icon"] = File.join(GAME_FOLDER, folder, icon) if icon
      "# Written by lota fuse, which writes it again on every build.\n#{YAML.dump(config)}"
    end

    private def entry_script(folder)
      <<~RUBY
        # frozen_string_literal: true

        # Written by lota fuse, which writes it again on every build. Starts
        # the game in #{GAME_FOLDER}/#{folder} as a fused game, as a shipped game starts,
        # which starts again when it restarts, by running this app's program
        # again with the same arguments (Lota::Boot#call).
        RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
        require "lota"
        exit Lota::Boot.new(File.join(__dir__, #{GAME_FOLDER.inspect}, #{folder.inspect}), ARGV, fused: true).call
      RUBY
    end

    # Runs +arguments+ after the Bundler command in +folder+, with an
    # environment that names the Gemfile there and none of the bundle this
    # program may run in. Raises Error, naming +step+ and saying +why+ it
    # may have failed, if it fails.
    private def run(bundle, *arguments, folder:, step:, why:)
      return if system(environment(folder), *bundle, *arguments, chdir: folder)

      raise Error, "#{step} failed (bundle #{arguments.join(' ')} in #{folder}). #{why}"
    end

    # Why the step that fetches Fledge may fail.
    private def network
      "lota fuse needs the network, to fetch Fledge from #{FLEDGE_GIT} at #{Fuse.fledge_ref}."
    end

    # Runs <tt>fledge build</tt> in the project, from Fledge's own
    # Gemfile, with the signing options of Options that are given, as
    # Fledge's own options of the same names, printing each path it
    # reports, and returns them. Fledge reads FLEDGE_SIGN_COMMAND from
    # the environment, which it runs in as this program does. Raises
    # Error, saying +why+ it may have failed, if one is given, when it
    # fails.
    private def build(bundle, why: nil)
      command = [*bundle, "exec", "fledge", "build", "--out", out]
      { "--sign" => @options.sign, "--sign-command" => @options.sign_command, "--notarize" => @options.notarize }.each do |option, value|
        command.push(option, value) if value
      end
      reader, writer = IO.pipe
      pid = spawn(environment(tools), *command, chdir: project, out: writer)
      writer.close
      paths = reader.each_line.map do |line|
        $stdout.puts line
        line.chomp
      end
      reader.close
      _, status = Process.wait2(pid)
      raise Error, ["fledge build failed (exit status #{status.exitstatus}).", why].compact.join(" ") unless status.success?

      paths
    end

    # The environment of a Bundler command for the Gemfile in +folder+:
    # none of Bundler's settings from the environment, which Fledge would
    # read for the game's bundle as well as for its own, and none of the
    # bundle this program may run in, whose setup <tt>bundle exec</tt>
    # names in RUBYOPT by its full path.
    private def environment(folder)
      env = ENV.keys.grep(/\ABUNDLER?_/).to_h { |key| [key, nil] } #: Hash[String, String?]
      rubyopt = ENV["RUBYOPT"].to_s.gsub(%r{-r\s*\S*bundler/setup\S*}, "").squeeze(" ").strip
      env.merge("BUNDLE_GEMFILE" => File.join(folder, "Gemfile"), "RUBYOPT" => rubyopt.empty? ? nil : rubyopt)
    end
  end
end
