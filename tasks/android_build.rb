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
require "timeout"
require_relative "source_archive"
require_relative "windows_build"

# LÖVE's dependencies for an Android app, built from source with the NDK
# for each of the ABIs Fledge's Android runtime has (arm64-v8a and x86_64,
# its ADR 022), which Lota's Android extension links
# (ext/lota/engine/dependencies_android.cmake).
#
# LÖVE's own Android build (love2d/love-android) compiles its
# dependencies from megasource, with Gradle's CMake: zlib, libogg,
# libvorbis, libtheora, FreeType, HarfBuzz, and libmodplug as static
# libraries in liblove.so, and SDL3 and OpenAL Soft as shared libraries
# beside it (megasource's CMakeLists.txt, MEGA_3P, and love-android's
# GameActivity.getLibraries). Lota builds the releases WindowsBuild
# builds, the versions its other gems carry, from each release's own
# source archive, pinned by its SHA-256, the same way: every library
# static but OpenAL Soft, which is libopenal.so, so a player can replace
# it, as its license, the GNU Library General Public License, allows.
# Fledge copies a shared library the extension links into the app beside
# libfledgeext.so (its ADR 025, section 2).
#
# SDL is not built here: Fledge's Android host is SDL's Java side, whose
# classes must match the libSDL3.so the app loads, and Fledge builds both
# from one release (examples/sdl_phone/sdl3/build.sh, SDL 3.4.18, where
# LÖVE pins 3.4.10). `bundle config build.lota --with-lota-sdl3=DIR`
# points the extension at that build.
#
# Each library is built for API level 26, Fledge's minimum, with the NDK's
# own CMake toolchain file and its static C++ runtime, as Fledge's
# toolchain files build the extension (its ADR 027, section 2), or for the
# two built with Autotools, with the NDK's compilers named for the ABI's
# triple and API level.
#
# As WindowsBuild does, it keeps downloading apart from building: #fetch
# downloads each archive into SOURCES (vendor/sources/android, which git
# ignores), and #build builds from them without the network.
class AndroidBuild
  # Raised when a step fails; its output is in the log.
  class Failure < StandardError; end

  # A release's source archive, as WindowsBuild::Archive records one.
  class Archive < Data.define(:name, :directory, :url, :sha256, :checked)
    # Where #fetch keeps it, relative to the repository.
    def path
      File.join(AndroidBuild::SOURCES, File.basename(url.delete_suffix("/download")))
    end
  end

  # Where #fetch keeps the archives, relative to the repository.
  SOURCES = "vendor/sources/android"

  # WindowsBuild's archives, in its order, each after what it links, less
  # SDL.
  ARCHIVES = WindowsBuild::ARCHIVES.reject { |archive| archive.name == "SDL" }
    .map { |archive| Archive.new(**archive.to_h) }.freeze

  # The ABIs Fledge's Android runtime is built for (its ADR 022, section 1).
  ABIS = %w[arm64-v8a x86_64].freeze

  # The oldest Android Fledge's runtime runs on (its ADR 011).
  API_LEVEL = 26

  # The libraries that build with Autotools alone, as on Linux and Windows.
  AUTOTOOLS = %w[libtheora libmodplug].freeze

  # The triple the NDK names the compilers of +abi+ for, which Autotools
  # takes as --host.
  def self.triple(abi)
    { "arm64-v8a" => "aarch64-linux-android", "x86_64" => "x86_64-linux-android" }.fetch(abi)
  end

  # [root] Where the build goes, one installed tree for each ABI.
  # [ndk] The NDK, by default ANDROID_NDK_ROOT or ANDROID_NDK_HOME, as
  #       Fledge finds it.
  # [repository] The repository, which SOURCES is relative to.
  # [out] Where progress goes; +nil+ means wherever $stdout points.
  def initialize(root:, ndk: ENV["ANDROID_NDK_ROOT"] || ENV.fetch("ANDROID_NDK_HOME", nil), repository: Dir.pwd,
    out: nil
  )
    @root = File.expand_path(root, repository)
    @ndk = ndk && File.expand_path(ndk)
    @repository = File.expand_path(repository)
    @out = out
  end

  # The build's log.
  def log
    File.join(@root, "build.log")
  end

  # Where the libraries for +abi+ are installed: include/ and lib/.
  def prefix(abi)
    File.join(@root, abi)
  end

  # How many times #fetch tries each download, as WindowsBuild::ATTEMPTS.
  ATTEMPTS = WindowsBuild::ATTEMPTS

  # Downloads each archive into SOURCES, unless it is there with the
  # recorded SHA-256, trying each ATTEMPTS times: hosts fail now and then.
  def fetch
    ARCHIVES.each do |archive|
      attempt(archive) { SourceArchive.new(archive, root: @repository).fetch }
      say "✅ #{archive.path} is #{archive.url}, SHA-256 #{archive.sha256}"
    end
  end

  private def attempt(archive)
    tries = 0
    begin
      yield
    rescue SourceArchive::Failure, IOError, SystemCallError, OpenSSL::SSL::SSLError, Timeout::Error => e
      tries += 1
      raise Failure, "#{archive.url}: #{e.message}" if tries >= ATTEMPTS

      say "Retrying #{archive.url} (#{tries} of #{ATTEMPTS - 1}): #{e.message}"
      sleep(tries)
      retry
    end
  end

  # Builds every library for every ABI, from what #fetch downloaded, unless
  # what is there was built by this recipe with this NDK, and returns
  # #root. Raises Failure if a step fails, if there is no NDK, or if #fetch
  # has not run.
  def build
    current = stamp
    if File.exist?(stamp_path) && File.read(stamp_path) == current
      say "✅ LÖVE's Android dependencies are current: #{@root}"
      return @root
    end

    ARCHIVES.each { |archive| verify!(archive) }
    FileUtils.rm_rf(@root)
    FileUtils.mkdir_p(@root)
    ABIS.each { |abi| ARCHIVES.each { |archive| build_archive(archive, abi) } }
    File.write(stamp_path, current)
    say "✅ Built LÖVE's Android dependencies for #{ABIS.join(' and ')}: #{@root}"
    @root
  end

  # The CMake options every library is configured with for +abi+: the
  # NDK's toolchain file, the ABI, Fledge's API level, the NDK's static
  # C++ runtime (the toolchain file's default, named), and the ABI's
  # installed tree, where each library finds those built before it.
  def cmake_options(abi)
    %W[
      -G
      Ninja
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_TOOLCHAIN_FILE=#{toolchain}
      -DANDROID_ABI=#{abi}
      -DANDROID_PLATFORM=android-#{API_LEVEL}
      -DANDROID_STL=c++_static
      -DCMAKE_INSTALL_PREFIX=#{prefix(abi)}
      -DCMAKE_INSTALL_LIBDIR=lib
      -DCMAKE_PREFIX_PATH=#{prefix(abi)}
      -DCMAKE_FIND_ROOT_PATH=#{prefix(abi)}
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    ]
  end

  # The options each library is configured with, beyond #cmake_options, by
  # its name, for the tree at +prefix+: WindowsBuild's, for Android.
  def options(name, prefix = "")
    case name
    # zlib 1.3's CMake links a shared libz.so beside the static one, which
    # nothing here uses, with a version script (zlib.map) that names
    # gz_intmax, which 1.3 no longer defines; the NDK's lld refuses such a
    # script unless told to allow it.
    when "zlib" then %w[-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--undefined-version]
    when "libogg" then %w[-DBUILD_SHARED_LIBS=OFF -DINSTALL_DOCS=OFF]
    when "libvorbis" then %w[-DBUILD_SHARED_LIBS=OFF]
    when "libtheora" then %W[--with-ogg=#{prefix} --disable-examples --disable-encode]
    # libmodplug 0.8.8.5 is C++ from before C++17, as WindowsBuild says.
    when "libmodplug" then ["CXXFLAGS=-O2 -fPIC -std=gnu++14"]
    when "FreeType"
      %W[
        -DBUILD_SHARED_LIBS=OFF
        -DFT_DISABLE_BZIP2=ON
        -DFT_DISABLE_PNG=ON
        -DFT_DISABLE_BROTLI=ON
        -DFT_DISABLE_HARFBUZZ=ON
        -DFT_REQUIRE_ZLIB=ON
        -DZLIB_INCLUDE_DIR=#{prefix}/include
        -DZLIB_LIBRARY=#{prefix}/lib/libz.a
      ]
    when "HarfBuzz" then %w[-DBUILD_SHARED_LIBS=OFF -DHB_HAVE_FREETYPE=ON -DHB_BUILD_SUBSET=OFF]
    when "OpenAL Soft" then openal_options
    else raise ArgumentError, "no options for #{name}"
    end
  end

  # OpenAL Soft as the shared library LÖVE's Android build ships,
  # libopenal.so, with megasource's options (no utilities, examples, or
  # installed data) and its OpenSL ES backend required, as megasource
  # requires it on Android. megasource also requires the Oboe backend,
  # which love-android takes from Gradle's prefab packages
  # (com.google.oboe:oboe, app/build.gradle); Fledge's Gradle project has
  # no such dependency, so Oboe, and with it AAudio, is off, and OpenSL ES,
  # which every Android since 2.3 has, plays the sound. The backends of
  # desktop systems are off, so a library found on the build machine
  # changes nothing. The {fmt} it bundles calls malloc and free without
  # including <cstdlib> (fmt-11.1.1/include/fmt/format.h:745-750), which
  # the NDK's libc++ does not include through other headers, as MSYS2's
  # does not on ARM64 (WindowsBuild), so it is included first, changing no
  # file of OpenAL Soft's.
  private def openal_options
    %w[
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
      -DALSOFT_BACKEND_OBOE=OFF
      -DALSOFT_BACKEND_PIPEWIRE=OFF
      -DALSOFT_BACKEND_PULSEAUDIO=OFF
      -DALSOFT_BACKEND_ALSA=OFF
      -DALSOFT_BACKEND_OSS=OFF
      -DALSOFT_BACKEND_JACK=OFF
      -DALSOFT_BACKEND_PORTAUDIO=OFF
      -DALSOFT_BACKEND_SDL2=OFF
      -DALSOFT_BACKEND_SDL3=OFF
      -DALSOFT_REQUIRE_OPENSL=ON
      -DCMAKE_CXX_FLAGS=-include\ cstdlib
    ]
  end

  # The NDK's CMake toolchain file.
  private def toolchain
    File.join(ndk, "build/cmake/android.toolchain.cmake")
  end

  private def ndk
    @ndk or raise Failure, "Lota's Android build needs the NDK: set ANDROID_NDK_ROOT (sdkmanager \"ndk;30.0.16248370\")"
  end

  # The NDK's compilers and tools, for Autotools.
  private def ndk_bin
    Dir[File.join(ndk, "toolchains/llvm/prebuilt/*/bin")].first or raise Failure, "#{ndk} has no LLVM toolchain"
  end

  private def stamp_path
    File.join(@root, "dependencies.stamp")
  end

  # What the build depends on: this recipe and the NDK's revision.
  private def stamp
    revision = File.read(File.join(ndk, "source.properties"))[/^Pkg\.Revision\s*=\s*(\S+)/, 1] if
      File.exist?(File.join(ndk, "source.properties"))
    raise Failure, "#{toolchain} is missing; ANDROID_NDK_ROOT names no NDK" unless File.file?(toolchain)

    "recipe #{Digest::SHA256.file(__FILE__).hexdigest}\nndk #{revision}"
  end

  private def verify!(archive)
    SourceArchive.new(archive, root: @repository).verify!
  rescue SourceArchive::Failure => e
    raise Failure, e.message
  end

  # Extracts +archive+ for +abi+ and builds it into that ABI's tree.
  private def build_archive(archive, abi)
    parent = File.join(@root, "src", abi)
    FileUtils.mkdir_p(parent)
    run(parent, {}, "cmake", "-E", "tar", "xf", File.join(@repository, archive.path))
    source = File.join(parent, archive.directory)
    AUTOTOOLS.include?(archive.name) ? autotools(archive, source, abi) : cmake(archive, source, abi)
    # zlib's CMake builds a shared library beside its static one; removed,
    # so nothing links it.
    FileUtils.rm_f(Dir[File.join(prefix(abi), "lib", "libz.so*")]) if archive.name == "zlib"
    say "✅ Built #{archive.name} for #{abi}"
  end

  private def cmake(archive, source, abi)
    build = File.join(@root, "build", abi, archive.directory)
    run(@root, {}, "cmake", "-S", source, "-B", build, *cmake_options(abi), *options(archive.name, prefix(abi)))
    run(@root, {}, "cmake", "--build", build)
    run(@root, {}, "cmake", "--install", build)
  end

  # Runs the release's configure for the ABI's triple, with the NDK's
  # compilers for it at API_LEVEL, position-independent, as everything
  # linked into libfledgeext.so must be.
  private def autotools(archive, source, abi)
    triple = self.class.triple(abi)
    bin = ndk_bin
    environment = {
      "CC" => File.join(bin, "#{triple}#{API_LEVEL}-clang"),
      "CXX" => File.join(bin, "#{triple}#{API_LEVEL}-clang++"),
      "AR" => File.join(bin, "llvm-ar"),
      "RANLIB" => File.join(bin, "llvm-ranlib"),
      "STRIP" => File.join(bin, "llvm-strip"),
      "CFLAGS" => "-O2 -fPIC",
      "CXXFLAGS" => "-O2 -fPIC",
    }
    build = File.join(source, "build")
    FileUtils.mkdir_p(build)
    run(build, environment, "sh", "../configure", "--prefix=#{prefix(abi)}", "--host=#{triple}", "--enable-static",
      "--disable-shared", *options(archive.name, prefix(abi)))
    run(build, environment, "make", "-j#{Etc.nprocessors}", "install")
  end

  private def run(dir, environment, *command)
    FileUtils.mkdir_p(@root)
    File.open(log, "a") do |file|
      file.puts("$ #{command.join(' ')}")
      Open3.popen2e(environment, *command, chdir: dir) do |stdin, output, wait|
        stdin.close
        IO.copy_stream(output, file)
        next if wait.value.success?

        file.flush
        raise Failure, "#{command.first(3).join(' ')} failed; the end of #{log}:\n#{File.readlines(log).last(40).join}"
      end
    end
  end

  private def say(message)
    (@out || $stdout).puts(message)
  end
end
