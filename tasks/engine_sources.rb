# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"

# Derives the engine's source list from LÖVE's own CMakeLists.txt.
#
# LÖVE's CMakeLists.txt chooses sources per platform with if(APPLE),
# if(MSVC), and the like, so a parser of its text would have to re-implement
# CMake. This class lets CMake evaluate it instead, for the host platform,
# and reads each target's sources back through the CMake file API
# (codemodel-v2). Nothing is built in that tree, and the LÖVE checkout is
# never written to.
#
# LÖVE's module targets list their wrap_*.cpp files and other Lua glue, so
# their sources cannot be used as they are. #generate drops what RULES name
# (doc/contributors/design/engine.md) and renders the rest as a CMake file, with
# every dropped file and its reason listed as a comment so a submodule bump
# shows up in review. #problems compares that rendering with the committed file.
class EngineSources
  # A rule that leaves a LÖVE source out of the engine.
  #
  # [pattern] Matches a path relative to the LÖVE checkout.
  # [reason] Why the engine leaves it out, as the generated file says.
  class Rule < Data.define(:pattern, :reason)
    # Whether this rule leaves +path+ out.
    def match?(path)
      pattern.match?(path)
    end
  end

  # What the engine leaves out of LÖVE's sources. The first matching rule
  # names the reason.
  RULES = [
    Rule.new(%r{(\A|/)wrap_[^/]*\z}, "Lua binding (wrap_*), doc/contributors/design/engine.md"),
    Rule.new(%r{\Asrc/common/(runtime|Reference)\.}, "Lua glue, doc/contributors/design/engine.md"),
    Rule.new(%r{\Asrc/modules/love/}, "Lua boot sequence, doc/contributors/design/engine.md"),
    Rule.new(%r{\Asrc/modules/thread/(LuaThread|ThreadModule|Channel)\.},
      "Lua threads and channels, doc/contributors/design/engine.md"),
    Rule.new(%r{\Asrc/libraries/enet/enet\.cpp\z}, "lua-enet binding, doc/contributors/design/engine.md"),
    Rule.new(%r{\Asrc/love\.cpp\z}, "main() of the love executable, which boots Lua"),
    Rule.new(%r{\Aextra/windows/}, "the love executable's Windows resources"),
    Rule.new(%r{\Asrc/libraries/(lua53|luasocket|luahttps)/}, "Lua, or a library only Lua calls"),
  ].freeze

  # Target types whose sources get compiled.
  COMPILED = %w[STATIC_LIBRARY SHARED_LIBRARY MODULE_LIBRARY OBJECT_LIBRARY EXECUTABLE].freeze

  # The variable the generated file prefixes every path with.
  ROOT_VARIABLE = "ENGINE_SOURCE_DIR"

  # Raised when CMake cannot evaluate the source tree.
  class Failure < StandardError; end

  # The platform name a source list is generated for, from Ruby's
  # <tt>host_os</tt>: macOS, Linux, or Windows with MinGW, the platforms
  # Lota builds on.
  def self.platform(host_os)
    return "macos" if host_os.include?("darwin")
    return "linux" if host_os.include?("linux")
    return "windows" if host_os.include?("mingw")

    raise Failure, "Lota builds its engine on macOS, Linux, and Windows with MinGW only, not #{host_os}"
  end

  # What aims CMake at iOS: its own cross-compiling (cmake-toolchains(7),
  # "Cross Compiling for iOS"), for the arm64 Simulator.
  IOS_ARGS = %w[-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_ARCHITECTURES=arm64].freeze

  # The platforms whose lists are generated on a host of +platform+: its
  # own, and on macOS also iOS, whose SDKs come with Xcode.
  def self.generated_on(platform)
    (platform == "macos") ? %w[macos ios] : [platform]
  end

  # What CMake is told when it evaluates LÖVE's tree for +platform+.
  # MEGA=ON takes LÖVE's dependencies as given rather than looking for
  # them (vendor/love/CMakeLists.txt:115-166), since the evaluation builds
  # nothing. On Linux, where LÖVE defaults to LuaJIT (lines 85-91), MEGA
  # expects megasource's luajit target, which does not exist here, so
  # LuaJIT is turned off; it chooses only which Lua LÖVE links, never which
  # of LÖVE's sources compile, and the engine leaves Lua out anyway.
  # For iOS, CMake's own cross-compiling for iOS aims it at the arm64
  # Simulator, whose sources are a device's too: LÖVE's CMakeLists.txt
  # chooses them by CMAKE_SYSTEM_NAME alone (lines 298-318).
  #
  # For Android, the NDK's own toolchain file at +ndk+ aims it at
  # arm64-v8a and Fledge's API level, 26, as Fledge's toolchain files aim
  # an extension's CMake (its ADR 027); LÖVE's CMakeLists.txt chooses no
  # source by processor, so they are x86_64's too. LÖVE's Android build is
  # megasource's, whose
  # LuaJIT is prebuilt, so LuaJIT is off, as on Linux.
  def self.cmake_args(platform, ndk: nil)
    return %w[-G Ninja -DMEGA=ON -DLOVE_JIT=OFF] if platform == "linux"
    if platform == "android"
      return %W[
        -G
        Ninja
        -DMEGA=ON
        -DLOVE_JIT=OFF
        -DCMAKE_TOOLCHAIN_FILE=#{ndk}/build/cmake/android.toolchain.cmake
        -DANDROID_ABI=arm64-v8a
        -DANDROID_PLATFORM=android-26
      ]
    end
    return %w[-G Ninja -DMEGA=ON] + IOS_ARGS if platform == "ios"
    # On Windows LÖVE's install rules name megasource's SDL3 target
    # (vendor/love/CMakeLists.txt:2053), so the evaluation defines a
    # stand-in for it (engine_sources_windows.cmake).
    if platform == "windows"
      return %W[
        -G
        Ninja
        -DMEGA=ON
        -DLOVE_JIT=OFF
        -DMEGA_SDL3=lota_sdl3_stand_in
        -DCMAKE_PROJECT_INCLUDE=#{File.expand_path('engine_sources_windows.cmake', __dir__)}
      ]
    end

    %w[-G Ninja -DMEGA=ON]
  end

  # The label of the list generated for +platform+ from vendor/love's
  # +commit+: what CMake is told, less the file the Windows evaluation
  # includes and the Android one's toolchain file, whose paths are the
  # machine's, not the tree's.
  def self.label(commit, platform)
    definitions = cmake_args(platform).grep(/\A-D/).grep_v(/\A-DCMAKE_(PROJECT_INCLUDE|TOOLCHAIN_FILE)=/)
    "vendor/love #{commit} on #{platform} with #{definitions.join(' ')}"
  end

  # [source] The CMake source tree to evaluate (vendor/love).
  # [build] A scratch directory for CMake's evaluation.
  # [cmake_args] Extra arguments to the configure step.
  # [label] Names the evaluated tree and platform in the generated header.
  def initialize(source:, build:, cmake_args: [], label: "")
    @source = File.expand_path(source)
    @build = File.expand_path(build)
    @cmake_args = cmake_args
    @label = label
  end

  # The generated CMake file, as a String.
  def generate
    kept, dropped = evaluate.partition { |path| reason(path).nil? }
    [header, sources_block(kept), excluded_block(dropped)].join("\n")
  end

  # Writes the generated file to +path+, byte for byte, so Windows writes
  # the same lines macOS and Linux do, not a CRLF at the end of each.
  def write(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, generate)
  end

  # Why the committed file at +path+ does not match LÖVE's tree, as lines
  # for a person to read; empty when it matches.
  def problems(path)
    return ["#{path} does not exist; generate it"] unless File.exist?(path)

    committed = File.read(path)
    missing = self.class.listed(committed).reject { |file| File.exist?(File.join(@source, file)) }
    return missing.map { |file| "#{path} lists #{file}, which no longer exists" } if missing.any?

    self.class.difference(committed, generate)
  end

  # Checks each committed list of +lists+, a Hash of its path to the
  # EngineSources that generates it (rake engine:sources:check): prints
  # that each matches, or aborts with the first one's problems.
  def self.check(lists)
    lists.each do |file, sources|
      problems = sources.problems(file)
      abort <<~ERROR if problems.any?
        ❌ #{file} does not match vendor/love:
        #{problems.map { |line| "  #{line}" }.join("\n")}

        Review the change, then run `bundle exec rake engine:sources` to regenerate it.
      ERROR

      puts "✅ #{file} matches vendor/love"
    end
  end

  # The source paths a generated file lists, relative to the source tree.
  def self.listed(content)
    content.lines.filter_map { |line| line[%r{\A\t\$\{#{ROOT_VARIABLE}\}/(\S+)\n?\z}, 1] }
  end

  # The lines one file has and the other lacks, marked - and +.
  def self.difference(committed, generated)
    old = committed.lines(chomp: true)
    new = generated.lines(chomp: true)
    (old - new).map { |line| "- #{line}" } + (new - old).map { |line| "+ #{line}" }
  end

  # The reason RULES leave +path+ out, or +nil+ when the engine builds it.
  def reason(path)
    RULES.find { |rule| rule.match?(path) }&.reason
  end

  private def header
    <<~CMAKE
      # GENERATED by `rake engine:sources` (tasks/engine_sources.rb). Do not edit.
      #
      # LÖVE's compiled sources, as CMake evaluates them for
      #   #{@label},
      # less the files tasks/engine_sources.rb leaves out (listed at the end).
    CMAKE
  end

  private def sources_block(kept)
    lines = kept.sort.map { |path| "\t${#{ROOT_VARIABLE}}/#{path}\n" }
    "set(ENGINE_SOURCES\n#{lines.join})\n"
  end

  private def excluded_block(dropped)
    lines = dropped.sort.map { |path| "#   #{path}: #{reason(path)}\n" }
    "# Excluded:\n#{lines.join}"
  end

  # Every compiled source of every target, relative to the source tree.
  private def evaluate
    configure
    targets.select { |target| COMPILED.include?(target.fetch("type")) }.flat_map do |target|
      target.fetch("sources").select { |source| source.key?("compileGroupIndex") }.map { |source| source.fetch("path") }
    end.uniq
  end

  private def configure
    FileUtils.rm_rf(reply_dir)
    query = File.join(@build, ".cmake/api/v1/query/codemodel-v2")
    FileUtils.mkdir_p(File.dirname(query))
    FileUtils.touch(query)
    output, status = Open3.capture2e("cmake", "-S", @source, "-B", @build, *@cmake_args)
    raise Failure, "cmake could not evaluate #{@source}:\n#{output}" unless status.success?
  end

  private def reply_dir
    File.join(@build, ".cmake/api/v1/reply")
  end

  private def targets
    index = Dir[File.join(reply_dir, "index-*.json")].max
    codemodel = read_reply(JSON.parse(File.read(index)).dig("reply", "codemodel-v2", "jsonFile"))
    codemodel.fetch("configurations").first.fetch("targets").map { |target| read_reply(target.fetch("jsonFile")) }
  end

  private def read_reply(name)
    JSON.parse(File.read(File.join(reply_dir, name)))
  end
end
