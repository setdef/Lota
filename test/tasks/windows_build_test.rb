# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/licensing"
require_relative "../../tasks/linux_build"
require_relative "../../tasks/windows_build"
require "digest"
require "stringio"

# WindowsBuild builds LÖVE's dependencies on Windows from each release's
# source archive. The real archives are checked against what
# love-appimage-source's Makefile names; for building, small archives of
# the same names, whose CMake projects and configure script only install
# files recording what they were told, stand in, built with the real CMake,
# Ninja, make, and sh, so the tests run in moments, on macOS too.
class WindowsBuildTest < Minitest::Test
  include TreeHelper

  MAKEFILE = File.join(ROOT, "vendor/love-appimage-source/Makefile")

  # The directory each archive unpacks to, from the Makefile's variables:
  # the versions Lota's Linux gem carries.
  def test_the_archives_are_the_releases_love_appimage_sources_makefile_names
    values = LinuxBuild.new(makefile: MAKEFILE, sources: "/s", root: "/r").variables(
      "SDL3_BRANCH", "OPENAL_BRANCH", "ZLIB_BRANCH", "HARFBUZZ_BRANCH", "LIBOGG_VERSION", "LIBVORBIS_VERSION",
      "FT_VERSION", "LIBMODPLUG_VERSION", "LIBTHEORA_VERSION"
    )
    expected = {
      "zlib" => "zlib-#{values.fetch('ZLIB_BRANCH').delete_prefix('v')}",
      "libogg" => "libogg-#{values.fetch('LIBOGG_VERSION')}",
      "libvorbis" => "libvorbis-#{values.fetch('LIBVORBIS_VERSION')}",
      "libtheora" => "libtheora-#{values.fetch('LIBTHEORA_VERSION')}",
      "libmodplug" => "libmodplug-#{values.fetch('LIBMODPLUG_VERSION')}",
      "FreeType" => "freetype-#{values.fetch('FT_VERSION')}",
      "HarfBuzz" => "harfbuzz-#{values.fetch('HARFBUZZ_BRANCH')}",
      "SDL" => "SDL3-#{values.fetch('SDL3_BRANCH').delete_prefix('release-')}",
      "OpenAL Soft" => "openal-soft-#{values.fetch('OPENAL_BRANCH')}",
    }

    assert_equal expected, WindowsBuild::ARCHIVES.to_h { |archive| [archive.name, archive.directory] }
  end

  # Each archive is a release's own, kept under its own name, which starts
  # with the directory it unpacks to.
  def test_each_archive_is_kept_by_its_release_name_with_its_sha256
    WindowsBuild::ARCHIVES.each do |archive|
      name = File.basename(archive.path)

      assert_equal File.join(WindowsBuild::SOURCES, name), archive.path
      assert name.start_with?("#{archive.directory}.tar."), name
      assert_match(/\A\h{64}\z/, archive.sha256)
      refute_empty archive.checked
    end
  end

  # OpenAL Soft's DLL is built from the archive the gem carries as its
  # source.
  def test_openal_soft_builds_from_the_archive_the_gem_carries
    source = Licensing.load(File.join(ROOT, "ext/lota/licenses.rb")).frameworks.each_value.filter_map(&:source).uniq
    openal = WindowsBuild::ARCHIVES.find { |archive| archive.name == "OpenAL Soft" }

    assert_equal [[openal.url, openal.sha256]], source.map { |archive| [archive.url, archive.sha256] }
  end

  # Windows on ARM64 has opengl32.dll, as x64 does, so SDL is built the
  # same for both, with OpenGL.
  def test_arm64_builds_sdl_as_x64_does_and_leaves_out_the_winpthread_clang_does_not_have
    x64 = WindowsBuild.new(sources: "s", root: "r", arm64: false)
    arm64 = WindowsBuild.new(sources: "s", root: "r", arm64: true)

    assert_equal x64.options("SDL"), arm64.options("SDL")
    refute(arm64.options("SDL").any? { |option| option.start_with?("-DSDL_OPENGL") })
    assert_includes x64.options("OpenAL Soft"), "-DALSOFT_STATIC_WINPTHREAD=ON"
    refute_includes arm64.options("OpenAL Soft"), "-DALSOFT_STATIC_WINPTHREAD=ON"
  end

  # A CMake project that installs share/<name>.txt, holding each cache
  # entry it was given that the recipe sets, and +files+, empty.
  def fake_cmake_project(name, files: [])
    <<~CMAKE
      cmake_minimum_required(VERSION 3.20)
      project(fake NONE)
      get_cmake_property(entries CACHE_VARIABLES)
      set(given "")
      foreach(entry IN LISTS entries)
        if(entry MATCHES "^(BUILD_SHARED_LIBS|FT_|ZLIB_|SDL_|ALSOFT_|HB_|CMAKE_PREFIX_PATH)")
          string(APPEND given "${entry}=${${entry}}\\n")
        endif()
      endforeach()
      file(WRITE ${CMAKE_BINARY_DIR}/#{name}.txt "${given}")
      install(FILES ${CMAKE_BINARY_DIR}/#{name}.txt DESTINATION share)
      foreach(file IN ITEMS #{files.join(' ')})
        get_filename_component(directory ${file} DIRECTORY)
        file(WRITE ${CMAKE_BINARY_DIR}/${file} "")
        install(FILES ${CMAKE_BINARY_DIR}/${file} DESTINATION ${directory})
      endforeach()
    CMAKE
  end

  # A configure script that writes a Makefile whose install rule records
  # the arguments configure was given in lib/libmodplug.a.
  FAKE_CONFIGURE = <<~'SH'
    #!/bin/sh
    for argument; do case $argument in --prefix=*) prefix=${argument#--prefix=};; esac; done
    echo "$@" > arguments.txt
    printf 'install:\n\tmkdir -p %s/lib\n\tcp arguments.txt %s/lib/libmodplug.a\n' "$prefix" "$prefix" > Makefile
  SH

  # The archive of +files+ (path => content) under +directory+, in
  # +repository+'s sources, recorded with its SHA-256.
  def fake_archive(repository, name, directory, files)
    stage = File.join(repository, "stage")
    files.each { |path, content| write(stage, File.join(directory, path), content) }
    archive = File.join(repository, WindowsBuild::SOURCES, "#{directory}.tar.gz")
    FileUtils.mkdir_p(File.dirname(archive))
    run!(stage, "cmake", "-E", "tar", "czf", archive, directory)
    WindowsBuild::Archive.new(name:, directory:, url: "https://example.com/#{directory}.tar.gz",
      sha256: Digest::SHA256.file(archive).hexdigest, checked: "the test")
  end

  def fake_archives(repository)
    [
      fake_archive(repository, "zlib", "zlib-1", "CMakeLists.txt" => fake_cmake_project(
        "zlib", files: %w[lib/libzlibstatic.a lib/libzlib.dll.a bin/libzlib1.dll]
      )),
      fake_archive(repository, "libmodplug", "libmodplug-1", "configure" => FAKE_CONFIGURE),
      fake_archive(repository, "FreeType", "freetype-1", "CMakeLists.txt" => fake_cmake_project("freetype")),
    ]
  end

  def build(repository, archives, out: StringIO.new)
    WindowsBuild.new(sources: WindowsBuild::SOURCES, root: "tmp/dependencies", repository:, archives:, out:)
  end

  # Each archive is extracted and built into installdir in order, each
  # with its options, and then is current; zlib keeps its static library
  # alone.
  def test_the_dependencies_build_each_archive_with_its_options_and_then_are_current
    in_tree do |repository|
      out = StringIO.new
      windows = build(repository, fake_archives(repository), out:)
      installdir = File.join(repository, "tmp/dependencies/installdir")

      assert_equal installdir, windows.dependencies
      assert_path_exists File.join(installdir, "lib/libzlibstatic.a")
      refute_path_exists File.join(installdir, "lib/libzlib.dll.a")
      refute_path_exists File.join(installdir, "bin/libzlib1.dll")
      freetype = File.read(File.join(installdir, "share/freetype.txt"))
      assert_includes freetype, "FT_DISABLE_BZIP2=ON\n"
      assert_includes freetype, "ZLIB_LIBRARY=#{installdir}/lib/libzlibstatic.a\n"
      assert_includes freetype, "CMAKE_PREFIX_PATH=#{installdir}\n"
      modplug = File.read(File.join(installdir, "lib/libmodplug.a"))
      assert_includes modplug, "--prefix=#{installdir} "
      assert_includes modplug, "--enable-static --disable-shared"
      assert_path_exists windows.dependencies_stamp

      windows.dependencies
      assert_equal 1, out.string.scan("✅ Built FreeType").size
      assert_includes out.string, "✅ LÖVE's Windows dependencies are current: #{installdir}"
    end
  end

  def test_the_dependencies_refuse_an_archive_that_is_not_the_one_recorded
    in_tree do |repository|
      archives = fake_archives(repository)
      archives[1] = archives[1].with(sha256: "0" * 64)
      failure = assert_raises(WindowsBuild::Failure) { build(repository, archives).dependencies }

      assert_includes failure.message, "#{WindowsBuild::SOURCES}/libmodplug-1.tar.gz has SHA-256"
    end
  end

  def test_the_dependencies_need_what_fetch_downloads
    in_tree do |repository|
      archives = fake_archives(repository)
      File.delete(File.join(repository, archives.first.path))
      failure = assert_raises(WindowsBuild::Failure) { build(repository, archives).dependencies }

      assert_includes failure.message, "zlib-1.tar.gz is missing; run bundle exec rake sources:fetch"
    end
  end

  def test_a_failing_step_raises_with_the_end_of_its_log
    in_tree do |repository|
      archives = fake_archives(repository)
      archives << fake_archive(repository, "HarfBuzz", "harfbuzz-1",
        "CMakeLists.txt" => "message(FATAL_ERROR \"no HarfBuzz here\")\n")
      windows = build(repository, archives)
      failure = assert_raises(WindowsBuild::Failure) { windows.dependencies }

      assert_includes failure.message, "failed; the end of #{windows.log}"
      assert_includes failure.message, "no HarfBuzz here"
      refute_path_exists windows.dependencies_stamp
    end
  end
end
