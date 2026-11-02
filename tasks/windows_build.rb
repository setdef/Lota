# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "etc"
require "fileutils"
require "open3"
require "openssl"
require "rbconfig"
require "timeout"
require_relative "source_archive"

# LÖVE's dependencies on Windows, built from source with MinGW, in MSYS2's
# UCRT64 environment (GCC) on x64 and its CLANGARM64 environment (clang) on
# ARM64, the toolchains RubyInstaller builds its Ruby with (ADR 002,
# section 4).
#
# LÖVE's own Windows build compiles its dependencies from megasource
# (love2d/megasource), with Microsoft's compiler, which Lota cannot use
# with RubyInstaller's Ruby. Lota builds the release of each library that
# love-appimage-source's Makefile names (vendor/love-appimage-source/
# Makefile:18-30), the versions the Linux gem carries, from each release's
# own source archive, pinned by its SHA-256, and links each as megasource
# links it into LÖVE's Windows build: statically, every library but SDL
# and OpenAL Soft (megasource's CMakeLists.txt, MEGA_3P). SDL is static
# here too, since its license (Zlib) asks for nothing a shared library
# would give; OpenAL Soft is a DLL, as LÖVE's own, so a player can replace
# it, as its license, the GNU Library General Public License, allows.
#
# Each library is configured to need nothing but Windows itself, so the
# extension's closure of DLLs is OpenAL32.dll and Windows' own: FreeType
# without bzip2, libpng, Brotli, or HarfBuzz, as megasource builds it (no
# bzip2 there either); HarfBuzz with FreeType alone, no GLib, Graphite,
# ICU, or Uniscribe; SDL without iconv; OpenAL Soft with its Windows
# backends alone, linking the compiler's runtime statically. Theora's
# decoder is built for the engine's video module, which compiles against
# it, but love.video is not bound, so the extension takes no object of
# LÖVE's that calls it, as on Linux, where the gem carries no libtheora.
#
# As LinuxBuild does, it keeps downloading apart from building, so the
# gate never needs the network:
#
# - #fetch downloads each archive into +sources+ (vendor/sources/windows,
#   which git ignores), and keeps it only when its SHA-256 is the one
#   recorded here.
# - #dependencies extracts each into +root+ (tmp/dependencies), and
#   builds and installs it into the installdir, which
#   ext/lota/engine/dependencies_windows.cmake links.
#
# A build is skipped when what it made was made from the same recipe (this
# file) and compiler.
class WindowsBuild
  # Raised when a step fails; its output is in the log.
  class Failure < StandardError; end

  # A release's source archive: the library's +name+, the +directory+ its
  # archive unpacks to, where it is published (+url+), its SHA-256, and
  # where that SHA-256 was confirmed besides this download (+checked+).
  class Archive < Data.define(:name, :directory, :url, :sha256, :checked)
    # Where #fetch keeps it, relative to the repository, which SourceArchive
    # reads.
    def path
      File.join(WindowsBuild::SOURCES, File.basename(url.delete_suffix("/download")))
    end
  end

  # Where #fetch keeps the archives, relative to the repository.
  SOURCES = "vendor/sources/windows"

  # The archives, in the order #dependencies builds them, each after what
  # it links.
  ARCHIVES = [
    Archive.new(
      name: "zlib", directory: "zlib-1.3",
      url: "https://github.com/madler/zlib/releases/download/v1.3/zlib-1.3.tar.gz",
      sha256: "ff0ba4c292013dbc27530b3a81e1f9a813cd39de01ca5e0f8bf355702efa593e",
      checked: "Mark Adler's signature, zlib-1.3.tar.gz.asc, and zlib.net/fossils' copy"
    ),
    Archive.new(
      name: "libogg", directory: "libogg-1.3.5",
      url: "https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.gz",
      sha256: "0eb4b4b9420a0f51db142ba3f9c64b333f826532dc0f48c6410ae51f4799b664",
      checked: "downloads.xiph.org/releases/ogg/SHA256SUMS"
    ),
    Archive.new(
      name: "libvorbis", directory: "libvorbis-1.3.7",
      url: "https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.gz",
      sha256: "0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab",
      checked: "downloads.xiph.org/releases/vorbis/SHA256SUMS"
    ),
    Archive.new(
      name: "libtheora", directory: "libtheora-1.2.0",
      url: "https://downloads.xiph.org/releases/theora/libtheora-1.2.0.tar.gz",
      sha256: "279327339903b544c28a92aeada7d0dcfd0397b59c2f368cc698ac56f515906e",
      checked: "downloads.xiph.org/releases/theora/SHA256SUMS"
    ),
    Archive.new(
      name: "libmodplug", directory: "libmodplug-0.8.8.5",
      url: "https://sourceforge.net/projects/modplug-xmms/files/libmodplug/0.8.8.5/libmodplug-0.8.8.5.tar.gz/download",
      sha256: "77462d12ee99476c8645cb5511363e3906b88b33a6b54362b4dbc0f39aa2daad",
      checked: "SourceForge's MD5 and Debian's libmodplug_0.8.8.5.orig.tar.gz SHA-1"
    ),
    Archive.new(
      name: "FreeType", directory: "freetype-2.13.3",
      url: "https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.gz",
      sha256: "5c3a8e78f7b24c20b25b54ee575d6daa40007a5f4eea2845861c3409b3021747",
      checked: "Werner Lemberg's signature, freetype-2.13.3.tar.gz.sig"
    ),
    Archive.new(
      name: "HarfBuzz", directory: "harfbuzz-10.1.0",
      url: "https://github.com/harfbuzz/harfbuzz/releases/download/10.1.0/harfbuzz-10.1.0.tar.xz",
      sha256: "6ce3520f2d089a33cef0fc48321334b8e0b72141f6a763719aaaecd2779ecb82",
      checked: "Debian's harfbuzz_10.1.0.orig.tar.xz SHA-1"
    ),
    Archive.new(
      name: "SDL", directory: "SDL3-3.4.10",
      url: "https://github.com/libsdl-org/SDL/releases/download/release-3.4.10/SDL3-3.4.10.tar.gz",
      sha256: "12b34280415ec8418c864408b93d008a20a6530687ee613d60bfbd20411f2785",
      checked: "the GitHub release asset's digest"
    ),
    Archive.new(
      name: "OpenAL Soft", directory: "openal-soft-1.24.3",
      url: "https://openal-soft.org/openal-releases/openal-soft-1.24.3.tar.bz2",
      sha256: "cb5e6197a1c0da0edcf2a81024953cc8fa8545c3b9474e48c852af709d587892",
      checked: "the GitHub release asset's digest, and ext/lota/licenses.rb"
    ),
  ].freeze

  # [sources] Where #fetch downloads (vendor/sources/windows).
  # [root] Where the build goes (tmp/dependencies).
  # [repository] The repository, which +sources+ is relative to.
  # [arm64] Whether the build is for ARM64, as on windows-11-arm.
  # [archives] What it builds, ARCHIVES unless a test says otherwise.
  # [out] Where progress goes; +nil+ means wherever $stdout points.
  def initialize(sources:, root:, repository: Dir.pwd, arm64: RbConfig::CONFIG["host_cpu"] == "aarch64",
    archives: ARCHIVES, out: nil
  )
    @sources = File.expand_path(sources, repository)
    @root = File.expand_path(root, repository)
    @repository = File.expand_path(repository)
    @arm64 = arm64
    @archives = archives
    @out = out
  end

  # The installdir, which holds every library.
  def installdir
    File.join(@root, "installdir")
  end

  # The build's log.
  def log
    File.join(@root, "build.log")
  end

  # The stamp #dependencies writes, whose time is when they were built.
  def dependencies_stamp
    File.join(@root, "dependencies.stamp")
  end

  # How many times #fetch tries each download: hosts fail now and then, as
  # LinuxBuild::ATTEMPTS rides out.
  ATTEMPTS = 5

  # Downloads each archive into +sources+, unless it is there with the
  # recorded SHA-256, trying each ATTEMPTS times.
  def fetch
    @archives.each do |archive|
      attempt(archive) { SourceArchive.new(archive, root: @repository).fetch }
      say "✅ #{archive.path} is #{archive.url}, SHA-256 #{archive.sha256}"
    end
  end

  # Builds every library into installdir, from what #fetch downloaded,
  # unless it is current, and returns installdir. Raises Failure if a step
  # fails, or if #fetch has not run.
  def dependencies
    if File.exist?(dependencies_stamp) && File.read(dependencies_stamp) == stamp
      say "✅ LÖVE's Windows dependencies are current: #{installdir}"
      return installdir
    end

    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root)
    @archives.each { |archive| build(archive) }
    File.write(dependencies_stamp, stamp)
    say "✅ Built LÖVE's Windows dependencies: #{installdir}"
    installdir
  end

  # What the build depends on: this recipe and the compiler.
  def stamp
    "recipe #{Digest::SHA256.file(__FILE__).hexdigest}\ncompiler #{capture(compiler('CC', 'cc'), '--version').lines.first&.strip}"
  end

  # The CMake options each library is configured with, beyond where it
  # installs, by its name.
  def options(name)
    case name
    when "zlib", "libmodplug" then []
    # The Makefile's options for libtheora, which builds with Autotools.
    when "libtheora" then %W[--with-ogg=#{installdir} --disable-examples --disable-encode]
    when "libogg" then %w[-DBUILD_SHARED_LIBS=OFF -DINSTALL_DOCS=OFF]
    when "libvorbis" then %w[-DBUILD_SHARED_LIBS=OFF]
    # As love-appimage-source's Makefile configures it (--without-png
    # --without-harfbuzz --without-brotli), less bzip2, which megasource's
    # FreeType goes without, linking zlib, which the engine links too.
    when "FreeType"
      %W[
        -DBUILD_SHARED_LIBS=OFF
        -DFT_DISABLE_BZIP2=ON
        -DFT_DISABLE_PNG=ON
        -DFT_DISABLE_BROTLI=ON
        -DFT_DISABLE_HARFBUZZ=ON
        -DFT_REQUIRE_ZLIB=ON
        -DZLIB_INCLUDE_DIR=#{installdir}/include
        -DZLIB_LIBRARY=#{installdir}/lib/libzlibstatic.a
      ]
    # The Makefile's -DHB_HAVE_FREETYPE=1 -DHB_BUILD_SUBSET=0; GLib,
    # Graphite, ICU, and Windows' shapers are off by default.
    when "HarfBuzz" then %w[-DBUILD_SHARED_LIBS=OFF -DHB_HAVE_FREETYPE=ON -DHB_BUILD_SUBSET=OFF]
    when "SDL" then sdl_options
    when "OpenAL Soft" then openal_options
    else raise ArgumentError, "no options for #{name}"
    end
  end

  # SDL as a static library, with iconv from SDL itself. Windows on ARM64
  # has no opengl32.dll, which SDL always tries to open, so megasource
  # turns SDL's OpenGL off there (its CMakeLists.txt, "In Windows, SDL
  # always tries to open OpenGL32.dll"), and so does Lota.
  private def sdl_options
    options = %w[
      -DSDL_SHARED=OFF
      -DSDL_STATIC=ON
      -DSDL_TEST_LIBRARY=OFF
      -DSDL_TESTS=OFF
      -DSDL_EXAMPLES=OFF
      -DSDL_SYSTEM_ICONV=OFF
      -DSDL_LIBICONV=OFF
    ]
    @arm64 ? [*options, "-DSDL_OPENGL=OFF"] : options
  end

  # OpenAL Soft as the DLL LÖVE's Windows build ships, OpenAL32.dll, with
  # megasource's options (no utilities, examples, or installed data) and
  # only Windows' own backends, so a library found on the build machine
  # changes nothing. It links GCC's runtime statically, by its own
  # options, so the DLL needs no libgcc, libstdc++, or libwinpthread DLL;
  # clang's libc++ has no winpthread to link.
  private def openal_options
    options = %w[
      -DLIBTYPE=SHARED
      -DALSOFT_UTILS=OFF
      -DALSOFT_NO_CONFIG_UTIL=ON
      -DALSOFT_EXAMPLES=OFF
      -DALSOFT_TESTS=OFF
      -DALSOFT_INSTALL_CONFIG=OFF
      -DALSOFT_INSTALL_HRTF_DATA=OFF
      -DALSOFT_INSTALL_AMBDEC_PRESETS=OFF
      -DALSOFT_INSTALL_EXAMPLES=OFF
      -DALSOFT_INSTALL_UTILS=OFF
      -DALSOFT_UPDATE_BUILD_VERSION=OFF
      -DALSOFT_BACKEND_PIPEWIRE=OFF
      -DALSOFT_BACKEND_PULSEAUDIO=OFF
      -DALSOFT_BACKEND_JACK=OFF
      -DALSOFT_BACKEND_PORTAUDIO=OFF
      -DALSOFT_BACKEND_SDL2=OFF
      -DALSOFT_BACKEND_SDL3=OFF
      -DALSOFT_REQUIRE_WASAPI=ON
      -DALSOFT_STATIC_LIBGCC=ON
      -DALSOFT_STATIC_STDCXX=ON
    ]
    @arm64 ? options : [*options, "-DALSOFT_STATIC_WINPTHREAD=ON"]
  end

  # Runs the block until it does not fail, ATTEMPTS times at most: a
  # connection dropped, a host that answered with an error, or an archive
  # other than the one recorded.
  private def attempt(archive)
    tries = 0
    begin
      yield
    rescue SourceArchive::Failure, IOError, SystemCallError, OpenSSL::SSL::SSLError, Timeout::Error => e
      tries += 1
      raise Failure, "#{archive.url}: #{e.message}" if tries >= ATTEMPTS

      say "Retrying #{archive.url} (#{tries} of #{ATTEMPTS - 1}): #{e.message}"
      retry
    end
  end

  # Extracts +archive+, once it is the one recorded, and builds it into
  # installdir.
  private def build(archive)
    source = File.join(@root, "src", archive.directory)
    FileUtils.mkdir_p(File.dirname(source))
    begin
      SourceArchive.new(archive, root: @repository).verify!
    rescue SourceArchive::Failure => e
      raise Failure, e.message
    end
    run(File.dirname(source), "cmake", "-E", "tar", "xf", File.join(@repository, archive.path))
    AUTOTOOLS.include?(archive.name) ? autotools(archive, source) : cmake(archive, source)
    remove_shared_zlib if archive.name == "zlib"
    say "✅ Built #{archive.name}"
  end

  private def cmake(archive, source)
    build = File.join(@root, "build", archive.directory)
    run(@root, "cmake", "-S", source, "-B", build, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
      "-DCMAKE_INSTALL_PREFIX=#{installdir}", "-DCMAKE_PREFIX_PATH=#{installdir}",
      # CMake 4 configures no project that asks for compatibility with
      # CMake older than 3.5, as libogg's and libvorbis's do.
      "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", *options(archive.name))
    run(@root, "cmake", "--build", build)
    run(@root, "cmake", "--install", build)
  end

  # The libraries that build with Autotools alone, as on Linux: libtheora
  # 1.2.0 and libmodplug 0.8.8.5.
  AUTOTOOLS = %w[libtheora libmodplug].freeze

  # Runs the release's configure with MSYS2's sh, for the machine the
  # compiler targets, named for Autotools (clang says
  # aarch64-w64-windows-gnu, which these config.sub files predate), and as
  # built on that machine too, since their config.guess does not know MSYS2.
  private def autotools(archive, source)
    host = capture(compiler("CC", "cc"), "-dumpmachine").sub(/windows-gnu\z/, "mingw32")
    build = File.join(source, "build")
    FileUtils.mkdir_p(build)
    run(build, "sh", "../configure", "--prefix=#{installdir}", "--build=#{host}", "--host=#{host}", "--enable-static",
      "--disable-shared", *options(archive.name))
    run(build, "make", "-j#{Etc.nprocessors}", "install")
  end

  # zlib 1.3's CMake builds a DLL beside its static library, whatever it
  # is told; removed, so nothing links it.
  private def remove_shared_zlib
    FileUtils.rm_f(Dir[File.join(installdir, "{bin,lib}", "*zlib*.dll{,.a}")])
  end

  private def compiler(variable, fallback)
    ENV.fetch(variable, fallback)
  end

  private def run(dir, *command)
    File.open(log, "a") do |file|
      file.puts("$ #{command.join(' ')}")
      Open3.popen2e(*command, chdir: dir) do |stdin, output, wait|
        stdin.close
        IO.copy_stream(output, file)
        next if wait.value.success?

        file.flush
        raise Failure, "#{command.first(3).join(' ')} failed; the end of #{log}:\n#{File.readlines(log).last(40).join}"
      end
    end
  end

  private def capture(*command)
    output, status = Open3.capture2(*command)
    raise Failure, "#{command.join(' ')} failed" unless status.success?

    output.strip
  end

  private def say(message)
    (@out || $stdout).puts(message)
  end
end
