# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "rbconfig"
require "yaml"

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
  # Use it through <tt>lota fuse</tt>.
  #
  # === Example
  #
  #   options = Lota::Fuse::Options.given(identifier: "com.example.DotPopper")
  #   Lota::Fuse.new("games/dot_popper", options).call
  #   # => ["/home/me/dist/Dot Popper-x86_64-linux.tar.gz", ...]
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
    class Options < ::Data.define(:out, :sign, :identifier, :app_version, :icon)
      # What each option is when <tt>lota fuse</tt> is not given it.
      DEFAULTS = { out: "dist", sign: nil, identifier: nil, app_version: nil, icon: nil }.freeze

      # Options with DEFAULTS for each that +given+ leaves out.
      #
      # === Example
      #
      #   Lota::Fuse::Options.given(identifier: "com.example.Pong").out # => "dist"
      def self.given(**given)
        new(**DEFAULTS, **given)
      end
    end

    # Where Bundler fetches Fledge from, which is not on RubyGems.org.
    FLEDGE_GIT = "https://github.com/setdef/Fledge"

    # The Git commit or tag of Fledge the project builds with: the first
    # commit whose check of a gem's DLLs takes the System32 libraries
    # Lota's Windows engine imports. No tag holds it yet.
    FLEDGE_REF = "c20a6293091bef9ef19a18c7fd2c0cb7042b2fd0"

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
    # [platform] The Gem::Platform to build for, which is this computer's,
    #   since Fledge builds for the computer it runs on.
    # [gem_file] String path of the Lota gem to ship, or +nil+ for the one
    #   RubyGems installed for this platform (Fuse.installed_gem).
    # [bundle] The command that runs Bundler, as an Array of Strings: by
    #   default this Ruby's own, so the app gets the Ruby that runs this.
    def initialize(path, options = Options.given, platform: Gem::Platform.local, gem_file: nil, bundle: nil)
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
      check_platform
      gem = @gem_file || Fuse.installed_gem(@platform)
      bundle = @bundle || bundler
      check_git
      write_project(read_settings, gem)
      run(bundle, "lock", "--add-checksums", step: "Locking the project's gems")
      run(bundle, "install", step: "Installing Fledge")
      build(bundle)
    end

    # The folder Fledge writes the app to, as an absolute path.
    def out
      File.expand_path(@options.out)
    end

    # The folder of the project Fuse writes, as an absolute path.
    def project
      File.join(out, PROJECT_FOLDER)
    end

    # The path of the Lota gem of this version that RubyGems installed for
    # +platform+, as RubyGems keeps it in its cache. Raises Error when
    # there is none, as when Lota runs from its own source.
    def self.installed_gem(platform)
      spec = Gem::Specification.find_all_by_name("lota", VERSION).find do |candidate|
        gem_platform = candidate.platform
        gem_platform.is_a?(Gem::Platform) && gem_platform === platform && File.file?(candidate.cache_file)
      end
      return spec.cache_file if spec

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
    #   Lota::Fuse.folder_name("Dot Popper: Deluxe") # => "Dot Popper_ Deluxe"
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
    #   Lota::Fuse.placeholder_identifier("dot_popper") # => "com.example.dot-popper"
    def self.placeholder_identifier(identity)
      part = identity.gsub(/[^A-Za-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")[0, 100].to_s.delete_suffix("-")
      "#{IDENTIFIER_PREFIX}.#{part.empty? ? 'lotagame' : part}"
    end

    # The name of the platform in PLATFORMS that +platform+ is, such as
    # <tt>"arm64-darwin"</tt> for this Mac's <tt>arm64-darwin-24</tt>, or
    # +nil+ when Lota has no gem for it.
    def self.platform_name(platform)
      PLATFORMS.find { |name| Gem::Platform.new(name) === platform }
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

    private def check_platform
      return if Fuse.platform_name(@platform)

      raise Error, "Lota has no gem for #{@platform}, so it cannot fuse a game here. " \
        "It builds on #{PLATFORMS.join(', ')}."
    end

    private def check_git
      return if executable("git")

      raise Error, "Fledge is not on RubyGems.org, so Bundler fetches it from #{FLEDGE_GIT} with Git, " \
        "and found no git on PATH. Install Git and try again."
    end

    # This Ruby's own Bundler.
    private def bundler
      [RbConfig.ruby, Gem.bin_path("bundler", "bundle")]
    rescue Gem::GemNotFoundException
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

    private def write_project(settings, gem)
      identity = identity(settings)
      folder = Fuse.folder_name(identity)
      FileUtils.rm_rf(project)
      FileUtils.mkdir_p(File.join(project, "vendor", "cache"))
      FileUtils.cp(gem, File.join(project, "vendor", "cache", File.basename(gem)))
      copy_game(@directory, File.join(project, GAME_FOLDER, folder))
      warn_of_gemfile
      File.write(File.join(project, "Gemfile"), gemfile)
      File.write(File.join(project, "fledge.yml"), fledge_yml(name(settings), identity, folder))
      File.write(File.join(project, "main.rb"), entry_script(folder))
    end

    # Says that a game's own Gemfile does not reach its app: the project
    # Fuse writes has a Gemfile of its own, which asks for Lota and Fledge
    # alone.
    private def warn_of_gemfile
      return unless File.file?(File.join(@directory, "Gemfile"))

      warn "lota fuse: the app ships Lota's gem alone; the gems #{File.join(@directory, 'Gemfile')} asks for do not reach it."
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

    private def gemfile
      <<~RUBY
        # frozen_string_literal: true

        # Written by lota fuse, which writes it again on every build.
        source "https://rubygems.org"

        gem "lota", "#{VERSION}"

        group :development do
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
      config["version"] = @options.app_version if @options.app_version
      config["icon"] = File.join(GAME_FOLDER, folder, @options.icon) if @options.icon
      "# Written by lota fuse, which writes it again on every build.\n#{config.to_yaml}"
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
    # this program may run in. Raises Error, naming +step+, if it fails.
    private def run(bundle, *arguments, step:)
      return if system(environment, *bundle, *arguments, chdir: project)

      raise Error, "#{step} failed (bundle #{arguments.join(' ')} in #{project}). " \
        "lota fuse needs the network, to fetch Fledge from #{FLEDGE_GIT} at #{Fuse.fledge_ref}."
    end

    # Runs <tt>fledge build</tt> in the project, printing each path it
    # reports, and returns them.
    private def build(bundle)
      command = [*bundle, "exec", "fledge", "build", "--out", out]
      command.push("--sign", @options.sign) if @options.sign
      paths = IO.popen(environment, command, chdir: project) do |io|
        io.each_line.map do |line|
          $stdout.puts line
          line.chomp
        end
      end
      status = Process.last_status
      raise Error, "fledge build failed (exit status #{status&.exitstatus})." unless status&.success?

      paths
    end

    private def environment
      env = ENV.keys.grep(/\ABUNDLER?_/).to_h { |key| [key, nil] } #: Hash[String, String?]
      rubyopt = ENV["RUBYOPT"].to_s.gsub(%r{-r\s*bundler/setup\S*}, "").strip
      env.merge("BUNDLE_GEMFILE" => File.join(project, "Gemfile"), "RUBYOPT" => rubyopt.empty? ? nil : rubyopt)
    end
  end
end
