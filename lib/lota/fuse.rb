# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "rbconfig"
require "yaml"
require_relative "fuse/lockfile"

module Lota
  # Turns a game folder into an app a player runs without Ruby, as LÖVE
  # fuses a game into its own executable (ADR 002, section 5).
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
  # (ADR 003, section 8), writes a Gemfile that pins Lota to this version
  # and Fledge to FLEDGE_REF, puts the installed Lota gem in the project's
  # <tt>vendor/cache</tt>, since Lota is not on RubyGems.org, writes
  # <tt>fledge.yml</tt> and an entry script that turns YJIT on where the
  # runtime has it and boots the game fused, locks the bundle, and runs
  # <tt>fledge build</tt>. Fledge builds for the computer it runs on, so
  # each platform's app is built on that platform.
  #
  # A game with a Gemfile ships the gems it locks. Its Gemfile.lock must
  # lock this platform and, if it locks Lota, this version of it
  # (Lockfile). The project's Gemfile evaluates the game's, and adds Lota
  # if the game's does not ask for it, and Fledge; the project starts from
  # the game's lockfile, locked for this platform alone, and from the
  # gems in the game's <tt>vendor/cache</tt> but those built for other
  # platforms, so Bundler keeps the versions the game was made with and
  # Fledge ships them, compiling those with extensions for its runtime.
  #
  # Use it through <tt>lota fuse</tt>.
  #
  # === Example
  #
  #   options = Lota::Fuse.options(identifier: "com.example.MoonPong")
  #   Lota::Fuse.new("games/moon_pong", options).call
  #   # => ["/home/me/dist/Moon Pong-x86_64-linux.tar.gz", ...]
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
    # [identifier] String reverse-DNS name the system knows the app by, or
    #   +nil+ for a placeholder under IDENTIFIER_PREFIX.
    # [app_version] String version of the app, or +nil+ for Fledge's
    #   default. A game's <tt>t.version</tt> names the version of LÖVE it
    #   was written for, so it never becomes the app's (ADR 002, section 5).
    # [icon] String path of the app's icon files in the game's folder,
    #   without their extension, as Fledge names them (<tt>icons/icon</tt>
    #   for <tt>icons/icon.icns</tt>, <tt>icons/icon.ico</tt>, and
    #   <tt>icons/icon-16.png</tt> and the other sizes), or +nil+ for none.
    #
    # Make one with Fuse.options, which fills in DEFAULT_OPTIONS.
    class Options < ::Data.define(:out, :sign, :identifier, :app_version, :icon)
    end

    # What each of Options is when <tt>lota fuse</tt> is not given it.
    DEFAULT_OPTIONS = { out: "dist", sign: nil, identifier: nil, app_version: nil, icon: nil }.freeze

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
    # libraries Lota's Windows engine imports; 0.5.1 changes only phones.
    FLEDGE_REF = "v0.5.1"

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
    end

    # Writes the project and builds it with <tt>fledge build</tt>,
    # printing each path Fledge reports as it reports it, and returns
    # them. Raises Error when the game, this computer, or a step of the
    # build stands in the way, saying which.
    def call
      check_game
      platform = lota_platform
      locked = read_lockfile(platform)
      gem = @gem_file || Fuse.installed_gem(@platform)
      bundle = @bundle || bundler
      check_git
      write_project(read_settings, gem, locked)
      run(bundle, *lock_arguments(locked, platform), step: "Locking the project's gems", why: network)
      if locked
        run(bundle, "install", step: "Installing the game's gems and Fledge", why: "#{COMPILER} #{network('lota fuse also')}")
      else
        run(bundle, "install", step: "Installing Fledge", why: network)
      end
      build(bundle)
    end

    # What Fuse says when the game's gems do not install: Bundler names
    # the gem that failed, and the usual reason is a gem with a C
    # extension on a computer with no compiler, which Fledge needs too, to
    # compile the gem for its runtime (its README, Gems).
    COMPILER = "Bundler says above which gem and why. A gem with a C extension compiles on this computer, which needs a " \
      "C compiler: on macOS, Xcode's command line tools (xcode-select --install); on Linux, a C compiler and make " \
      "(sudo apt install build-essential on Debian and Ubuntu); on Windows, RubyInstaller's MSYS2 tools (ridk install)."

    # The folder Fledge writes the app to, as an absolute path.
    def out
      File.expand_path(@options.out)
    end

    # The folder of the project Fuse writes, as an absolute path.
    def project
      File.join(out, PROJECT_FOLDER)
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
    #   Lota::Fuse.folder_name("Moon Pong: Deluxe") # => "Moon Pong_ Deluxe"
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
    #   Lota::Fuse.placeholder_identifier("moon_pong") # => "com.example.moon-pong"
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
      return unless out == @directory || "#{@directory}/".start_with?(File.join(project, ""))

      raise Error, "--out can't be the game's own folder, #{@options.out}; choose one beside or inside it."
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

    # What follows <tt>bundle</tt> to lock the project: for a game with a
    # lockfile, which the project starts from, it adds +platform+, which
    # Fledge's runtime takes in the form Lota's gem names it, and removes
    # the lockfile's other platforms, whose builds the project does not
    # hold (#copy_cache).
    private def lock_arguments(locked, platform)
      return ["lock", "--add-checksums"] unless locked

      others = locked.other_platforms(platform)
      ["lock", "--add-platform", platform, *(others.empty? ? [] : ["--remove-platform", *others]), "--add-checksums"]
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

    # Copies the game's files, but not the folders of LEFT_OUT or the
    # folder this build writes to, should it be inside the game's folder.
    private def copy_game(from, to)
      FileUtils.mkdir_p(to)
      Dir.each_child(from) do |child|
        source = File.join(from, child)
        next if source == out || LEFT_OUT.any? { |name| source == File.join(@directory, name) }

        target = File.join(to, child)
        if File.directory?(source)
          copy_game(source, target)
        else
          FileUtils.cp(source, target, preserve: true)
        end
      end
    end

    # The project's Gemfile: the game's, evaluated where the game's copy
    # is, so that its paths are read from there, or else a source of
    # gems; then Lota, unless the game's asks for it; then Fledge.
    private def gemfile(folder, locked)
      game = locked ? "eval_gemfile #{"#{GAME_FOLDER}/#{folder}/Gemfile".inspect}" : 'source "https://rubygems.org"'
      lota = locked&.depends_on?("lota") ? "" : %(gem "lota", "#{VERSION}"\n\n)
      <<~RUBY
        # frozen_string_literal: true

        # Written by lota fuse, which writes it again on every build.
        #{game}

        #{lota}group :development do
          gem "fledge", git: "#{FLEDGE_GIT}", ref: "#{Fuse.fledge_ref}"
        end
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
        # the game in #{GAME_FOLDER}/#{folder} as a fused game, as a shipped game starts.
        RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
        require "lota"
        exit Lota::Boot.new(File.join(__dir__, #{GAME_FOLDER.inspect}, #{folder.inspect}), ARGV, fused: true).call
      RUBY
    end

    # Runs +arguments+ after the Bundler command in the project, with an
    # environment that names the project's Gemfile and none of the bundle
    # this program may run in. Raises Error, naming +step+ and saying +why+
    # it may have failed, if it fails.
    private def run(bundle, *arguments, step:, why:)
      return if system(environment, *bundle, *arguments, chdir: project)

      raise Error, "#{step} failed (bundle #{arguments.join(' ')} in #{project}). #{why}"
    end

    # Why a step that fetches Fledge may fail, said of +subject+.
    private def network(subject = "lota fuse")
      "#{subject} needs the network, to fetch Fledge from #{FLEDGE_GIT} at #{Fuse.fledge_ref}."
    end

    # Runs <tt>fledge build</tt> in the project, printing each path it
    # reports, and returns them.
    private def build(bundle)
      command = [*bundle, "exec", "fledge", "build", "--out", out]
      sign = @options.sign
      command.push("--sign", sign) if sign
      reader, writer = IO.pipe
      pid = spawn(environment, *command, chdir: project, out: writer)
      writer.close
      paths = reader.each_line.map do |line|
        $stdout.puts line
        line.chomp
      end
      reader.close
      _, status = Process.wait2(pid)
      raise Error, "fledge build failed (exit status #{status.exitstatus})." unless status.success?

      paths
    end

    private def environment
      env = ENV.keys.grep(/\ABUNDLER?_/).to_h { |key| [key, nil] } #: Hash[String, String?]
      rubyopt = ENV["RUBYOPT"].to_s.gsub(%r{-r\s*bundler/setup\S*}, "").strip
      env.merge("BUNDLE_GEMFILE" => File.join(project, "Gemfile"), "RUBYOPT" => rubyopt.empty? ? nil : rubyopt)
    end
  end
end
