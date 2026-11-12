# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "json"
require "open3"
require "shellwords"
require "zlib"
require_relative "android_build"
require_relative "ios_build"
require_relative "licensing"
require_relative "phone_notices"
require_relative "../ext/lota/phone/engine"
require_relative "../lib/lota/version"

# Builds a phone's engine for one target (Lota::PhoneEngine::TARGETS) and
# packs it as the bundle a release publishes and phone/engine.rb fetches
# (rake phone:engine).
#
# It configures Lota's own CMake project (ext/lota/CMakeLists.txt) as
# phone/ios.rb and phone/android.rb do inside `fledge build`, with the
# same options and a toolchain file of the same text as Fledge's (its
# lib/fledge/mobile_extensions/cmake.rb, read as a reference: CMake's iOS
# variables for the slice's SDK and Xcode's clang, or the NDK's
# android.toolchain.cmake for the ABI at API level 26), but with
# LOTA_EXTENSION off, so it builds the engine alone, which needs no Ruby.
# So the engine is the one a from-source phone build compiles. Lota's
# extension is built against Ruby's ABI, so it stays in the app's build.
#
# The bundle holds the engine, the libraries it links, its include
# folders, an engine.cmake that makes lota_engine an imported target, a
# manifest, and the phone's notices with, for Android, OpenAL Soft's
# source (Lota::PhoneEngine says what each is). It carries no dates:
# Apple's archivers are told to write none (ZERO_AR_DATE), the NDK's
# llvm-ar writes none, and Lota::PhoneEngine::Tar and the gzip header carry
# none. So one commit built twice in the same folder, as on CI's runners,
# gives the same bytes. Built in another folder it does not: the NDK's
# toolchain compiles with -g, so the Android libraries' debug information
# names the folder they were built in (fledge build strips it from the
# app's libraries).
class PhoneEngineBuild
  # Raised when a step fails; its output is in the log.
  class Failure < StandardError; end

  # The file name endings of a header, which the bundle carries from each
  # include folder; LÖVE's sources hold one .hpp11 (glm-free GLAD's).
  HEADERS = %w[.h .hh .hpp .hxx .hpp11 .inl .inc .ipp .tcc].freeze

  # The API level Fledge's Android runtime is built for, which its
  # toolchain files name (AndroidBuild::API_LEVEL).
  API_LEVEL = AndroidBuild::API_LEVEL

  # [target] One of Lota::PhoneEngine::TARGETS.
  # [repository] Lota's clone, with its submodules.
  # [work] Where the build goes.
  # [ios_sdl3] SDL3 built for each iOS slice (rake ios:sdl3).
  # [android_deps] LÖVE's dependencies for each ABI (rake android:deps).
  # [ndk] The NDK, for Android.
  # [out] Where progress goes.
  def initialize(target, repository: Dir.pwd, work: nil, ios_sdl3: "tmp/ios/sdl3",
    android_deps: "tmp/android/deps", ndk: ENV["ANDROID_NDK_ROOT"] || ENV.fetch("ANDROID_NDK_HOME", nil), out: $stdout
  )
    raise Failure, "Lota builds no phone engine for #{target}" unless Lota::PhoneEngine::TARGETS.include?(target)

    @target = target
    @repository = File.expand_path(repository)
    @work = File.expand_path(work || "tmp/phone-engine/#{target}", @repository)
    @ios_sdl3 = File.expand_path(ios_sdl3, @repository)
    @android_deps = File.expand_path(android_deps, @repository)
    @ndk = ndk && File.expand_path(ndk)
    @out = out
  end

  # Whether the target is an iOS slice.
  def ios?
    @target.start_with?("ios-")
  end

  # The slice or ABI, as Fledge names it.
  def name
    @target.delete_prefix("android-")
  end

  # The build's log.
  def log
    File.join(@work, "build.log")
  end

  # The CMake build folder.
  def build_dir
    File.join(@work, "build")
  end

  # The clang target triple of Fledge's runtime for the slice or ABI.
  def triple
    return "arm64-apple-ios#{IosBuild::DEPLOYMENT_TARGET}#{'-simulator' if @target.end_with?('-simulator')}" if ios?

    "#{AndroidBuild.triple(name)}#{API_LEVEL}"
  end

  # The text of the toolchain file, as Fledge writes it for the target:
  # for iOS, given the SDK's +sysroot+ and Xcode's +cc+ and +cxx+.
  def toolchain(sysroot: nil, cc: nil, cxx: nil)
    header = "# The toolchain file fledge build writes for #{@target} (Fledge's ADR 027), written by " \
      "rake phone:engine.\n"
    return header + android_toolchain unless ios?

    header + <<~CMAKE
      set(CMAKE_SYSTEM_NAME iOS)
      set(CMAKE_OSX_SYSROOT #{quote(sysroot)})
      set(CMAKE_OSX_ARCHITECTURES arm64)
      set(CMAKE_OSX_DEPLOYMENT_TARGET #{IosBuild::DEPLOYMENT_TARGET})
      set(CMAKE_C_COMPILER #{quote(cc)})
      set(CMAKE_CXX_COMPILER #{quote(cxx)})
      set(CMAKE_OBJC_COMPILER #{quote(cc)})
      set(CMAKE_OBJCXX_COMPILER #{quote(cxx)})
    CMAKE
  end

  # The CMake options, phone/ios.rb's or phone/android.rb's but for the
  # extension's.
  def options
    common = %W[
      -DCMAKE_BUILD_TYPE=Release
      -DENGINE_SOURCE_DIR:PATH=#{File.join(@repository, 'vendor/love')}
      -DLOTA_EXTENSION=OFF
      -DLOTA_NATIVE_TEST=OFF
      -DLOTA_SANITIZE=OFF
    ]
    if ios?
      common + %W[
        -DENGINE_DEPS_DIR:PATH=#{File.join(@repository, 'vendor/love-apple-dependencies')}
        -DLOTA_IOS_SDL3_DIR:PATH=#{File.join(@ios_sdl3, name)}
      ]
    else
      common + %W[
        -DLOTA_ANDROID_SDL3_DIR:PATH=#{File.join(@android_deps, name)}
        -DLOTA_ANDROID_DEPS_DIR:PATH=#{File.join(@android_deps, name)}
      ]
    end
  end

  # Builds the engine and returns the build folder.
  def build
    FileUtils.rm_rf(@work)
    FileUtils.mkdir_p(@work)
    toolchain_file = File.join(@work, "toolchain.cmake")
    File.write(toolchain_file, ios? ? toolchain(**xcode) : toolchain)
    environment = { "CMAKE_TOOLCHAIN_FILE" => toolchain_file, "ZERO_AR_DATE" => "1" }
    run(environment, "cmake", "-S", File.join(@repository, "ext/lota"), "-B", build_dir, "-G", "Ninja", *options)
    run(environment, "cmake", "--build", build_dir, "--target", "lota_engine")
    say "✅ Built Lota's engine for #{@target}: #{build_dir}"
    build_dir
  end

  # The bundle's files, by their paths in it, each a path to copy or the
  # String to write, from the build in +build+. +interface+ and +link+ are
  # engine_interface.txt's and phone_link.txt's text.
  def files(build:, interface:, link:, digest:, love:, toolchain_version:)
    sections = self.class.sections(interface)
    files = { "lib/liblota_engine.a" => File.join(build, "engine/liblota_engine.a") }
    includes = self.class.include_layout(sections.fetch("includes", []))
    includes.each do |folder, path|
      next if path.include?("/")

      Dir.glob("**/*", base: folder).sort.each do |file|
        source = File.join(folder, file)
        files["include/#{path}/#{file}"] = source if File.file?(source) && HEADERS.include?(File.extname(file))
      end
    end
    libraries, flags = self.class.relink(link)
    libraries.each do |library|
      destination = "lib/#{File.basename(library)}"
      raise Failure, "two libraries are named #{File.basename(library)}" if files.key?(destination)

      files[destination] = library
    end
    files["engine.cmake"] = Contents.new(text: self.class.engine_cmake(
      includes: includes.values.map { |path| "include/#{path}" },
      definitions: sections.fetch("definitions", []), options: sections.fetch("options", []),
      archives: libraries.select { |library| library.end_with?(".a") }.map { |library| "lib/#{File.basename(library)}" },
      flags:
    ))
    manifest = {
"target" => @target,
"lota" => Lota::VERSION,
"love" => love,
"engine_digest" => digest,
"toolchain" => toolchain_version,
}
    files["manifest.json"] = Contents.new(text: "#{JSON.pretty_generate(manifest)}\n")
    files
  end

  # Packs the build into the bundle at +archive+, with the phone's
  # notices, and returns its SHA-256.
  def pack(archive)
    files = files(
      build: build_dir, interface: File.read(File.join(build_dir, "engine_interface.txt")),
      link: File.read(File.join(build_dir, "phone_link.txt")),
      digest: Lota::PhoneEngine.digest(File.join(@repository, "ext/lota")),
      love: git("-C", File.join(@repository, "vendor/love"), "rev-parse", "HEAD"), toolchain_version:
    )
    notices = File.join(@work, "notices")
    FileUtils.rm_rf(notices)
    FileUtils.mkdir_p(notices)
    phone = PhoneNotices.new(licensing: Licensing.load(File.join(@repository, "ext/lota/licenses.rb")),
      phone: ios? ? "iOS" : "Android", root: @repository)
    phone.fetch
    phone.write(notices)
    Dir.glob("**/*", base: notices).each do |file|
      files[file] = File.join(notices, file) if File.file?(File.join(notices, file))
    end
    write(archive, files)
  end

  # Writes +files+ (as #files gives them) to the gzipped archive at
  # +archive+ and returns its SHA-256.
  def self.write(archive, files)
    FileUtils.mkdir_p(File.dirname(archive))
    contents = files.transform_values do |value|
      value.is_a?(Contents) ? value.text : File.binread(value)
    end
    File.open("#{archive}.part", "wb") do |io|
      gzip = Zlib::GzipWriter.new(io, Zlib::BEST_COMPRESSION)
      # Zlib writes the time now for a time of 0 (zlib.c, gzfile_make_header).
      gzip.mtime = 1
      Lota::PhoneEngine::Tar.write(gzip, contents)
      gzip.finish
    end
    File.rename("#{archive}.part", archive)
    Digest::SHA256.file(archive).hexdigest
  end

  # A file's text, as opposed to a path to copy.
  class Contents < Data.define(:text); end

  # Each [heading] of engine_interface.txt, with its lines.
  def self.sections(text)
    sections = {}
    heading = nil
    text.each_line(chomp: true).map(&:strip).each do |line|
      if line.match?(/\A\[\w+\]\z/)
        heading = line[1...-1]
        sections[heading] = []
      elsif heading && !line.empty?
        sections.fetch(heading) << line
      end
    end
    sections
  end

  # Where each include folder goes under include/, in the order given: a
  # folder of its own, numbered, or, for a folder inside one before it,
  # that folder's place with the rest of its path, so no header is
  # carried twice.
  def self.include_layout(folders)
    layout = {}
    folders.uniq.each do |folder|
      parent = layout.keys.find { |earlier| folder.start_with?("#{earlier}/") }
      layout[folder] = parent ? "#{layout.fetch(parent)}#{folder.delete_prefix(parent)}" :
        layout.values.count { |path| !path.include?("/") }.to_s
    end
    layout
  end

  # phone_link.txt's archives and flags, rewritten for the bundle: the
  # libraries it carries, each archive and each shared library a -l flag
  # finds in a -L folder, and the flags, with every -L folder made the
  # bundle's lib folder.
  def self.relink(text)
    lines = text.each_line(chomp: true).map(&:strip).reject(&:empty?)
    libraries = lines.select { |line| line.end_with?(".a") }
    folders = []
    flags = []
    lines.reject { |line| line.end_with?(".a") }.each do |flag|
      if flag.start_with?("-L")
        folders << flag.delete_prefix("-L")
        flags << "-L${LOTA_ENGINE_LIB}" unless flags.include?("-L${LOTA_ENGINE_LIB}")
        next
      end
      if (library = flag[/\A-l(.+)\z/, 1])
        shared = folders.map { |folder| File.join(folder, "lib#{library}.so") }.find { |path| File.file?(path) }
        libraries << shared if shared
      end
      flags << flag
    end
    [libraries, flags]
  end

  # engine.cmake: lota_engine as an imported target, with the bundle's
  # paths, and phone_link.txt for phone/ios.rb and phone/android.rb.
  def self.engine_cmake(includes:, definitions:, options:, archives:, flags:)
    here = "${CMAKE_CURRENT_LIST_DIR}"
    link = archives.map { |path| "#{here}/#{path}" } + flags.map { |flag| flag.sub("${LOTA_ENGINE_LIB}", "#{here}/lib") }
    <<~CMAKE
      # LÖVE's engine, prebuilt for one phone target by rake phone:engine
      # (tasks/phone_engine.rb); generated, so do not edit it. Lota's CMake
      # project includes it in place of ext/lota/engine when LOTA_ENGINE_DIR
      # names this folder.
      add_library(lota_engine STATIC IMPORTED GLOBAL)
      set_target_properties(lota_engine PROPERTIES
      \tIMPORTED_LOCATION "#{here}/lib/liblota_engine.a"
      \tINTERFACE_INCLUDE_DIRECTORIES "#{includes.map { |path| "#{here}/#{path}" }.join(';')}"
      \tINTERFACE_COMPILE_DEFINITIONS "#{definitions.join(';')}"
      \tINTERFACE_COMPILE_OPTIONS "#{options.join(';')}"
      \tINTERFACE_LINK_LIBRARIES "#{link.join(';')}")
      file(WRITE ${CMAKE_BINARY_DIR}/phone_link.txt "#{link.join('\\n')}\\n")
    CMAKE
  end

  private def android_toolchain
    raise Failure, "Lota's Android engine needs the NDK: set ANDROID_NDK_ROOT" unless @ndk

    <<~CMAKE
      set(ANDROID_ABI #{name})
      set(ANDROID_PLATFORM android-#{API_LEVEL})
      include(#{quote(File.join(@ndk, 'build', 'cmake', 'android.toolchain.cmake'))})
    CMAKE
  end

  # Xcode's SDK and clang for the slice, as Fledge asks xcrun for them.
  private def xcode
    sdk = @target.end_with?("-simulator") ? "iphonesimulator" : "iphoneos"
    {
      sysroot: capture("xcrun", "--sdk", sdk, "--show-sdk-path"),
      cc: capture("xcrun", "--sdk", sdk, "--find", "clang"),
      cxx: capture("xcrun", "--sdk", sdk, "--find", "clang++"),
    }
  end

  # What built it: Xcode's version, or the NDK's revision.
  private def toolchain_version
    if ios?
      capture("xcodebuild", "-version").lines.map(&:strip).join(", ")
    else
      properties = File.read(File.join(@ndk, "source.properties"))
      "NDK #{properties[/^Pkg\.Revision\s*=\s*(\S+)/, 1]}"
    end
  end

  # CMake's quoted argument, as Fledge writes one.
  private def quote(text)
    "\"#{text.to_s.gsub(/[\\"$]/) { |character| "\\#{character}" }}\""
  end

  private def write(archive, files)
    sha256 = self.class.write(archive, files)
    say "✅ #{archive}: SHA-256 #{sha256}"
    sha256
  end

  private def git(*)
    capture("git", *)
  end

  private def capture(*command)
    output, status = Open3.capture2e(*command)
    raise Failure, "#{command.join(' ')} failed: #{output}" unless status.success?

    output.strip
  end

  private def run(environment, *command)
    File.open(log, "a") do |file|
      file.puts("$ #{command.shelljoin}")
      Open3.popen2e(environment, *command, chdir: @repository) do |stdin, output, wait|
        stdin.close
        IO.copy_stream(output, file)
        next if wait.value.success?

        file.flush
        raise Failure, "#{command.first(3).join(' ')} failed; the end of #{log}:\n#{File.readlines(log).last(40).join}"
      end
    end
  end

  private def say(message)
    @out.puts(message)
  end
end
