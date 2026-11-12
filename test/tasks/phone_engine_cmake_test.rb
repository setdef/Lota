# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/phone_engine"

# Lota's CMake project takes a prebuilt phone engine in place of building
# one (LOTA_ENGINE_DIR), through the engine.cmake rake phone:engine
# writes, and builds the engine alone without Ruby (LOTA_EXTENSION off).
class PhoneEngineCMakeTest < Minitest::Test
  include TreeHelper

  def bundle(root)
    folder = File.join(root, "bundle")
    write(folder, "lib/liblota_engine.a", "!<arch>\n")
    write(folder, "engine.cmake", PhoneEngineBuild.engine_cmake(
      includes: %w[include/0 include/0/libraries], definitions: %w[HAS_SOCKLEN_T LOVE_APPLE_USE_FRAMEWORKS],
      options: [], archives: %w[lib/libz.a], flags: %w[-L${LOTA_ENGINE_LIB} -lopenal -llog]
    ))
    folder
  end

  def test_lotas_project_takes_the_prebuilt_engine_and_writes_its_link_for_the_phone_extconf
    in_tree do |root|
      folder = bundle(root)
      # A probe project beside Lota's, which includes it and reports what
      # lota_engine became.
      write(root, "probe/CMakeLists.txt", <<~CMAKE)
        cmake_minimum_required(VERSION 3.25)
        project(probe C CXX)
        set(LOTA_ENGINE_DIR #{folder} CACHE PATH "" FORCE)
        set(LOTA_EXTENSION OFF CACHE BOOL "" FORCE)
        add_subdirectory(#{File.join(ROOT, 'ext/lota')} lota)
        get_target_property(imported lota_engine IMPORTED)
        get_target_property(location lota_engine IMPORTED_LOCATION)
        get_target_property(includes lota_engine INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(definitions lota_engine INTERFACE_COMPILE_DEFINITIONS)
        file(WRITE ${CMAKE_BINARY_DIR}/probe.txt "${imported}\\n${location}\\n${includes}\\n${definitions}\\n")
      CMAKE
      build = File.join(root, "build")
      run!(root, "cmake", "-S", "probe", "-B", build)

      imported, location, includes, definitions = File.readlines(File.join(build, "probe.txt"), chomp: true)

      assert_equal "TRUE", imported
      assert_equal "#{folder}/lib/liblota_engine.a", location
      assert_equal "#{folder}/include/0;#{folder}/include/0/libraries", includes
      assert_equal "HAS_SOCKLEN_T;LOVE_APPLE_USE_FRAMEWORKS", definitions
      assert_equal ["#{folder}/lib/libz.a", "-L#{folder}/lib", "-lopenal", "-llog"],
        File.readlines(File.join(build, "phone_link.txt"), chomp: true)
      refute_path_exists File.join(build, "lota/engine"), "the engine was configured from source"
      refute_path_exists File.join(build, "lota/native"), "the extension was configured without LOTA_EXTENSION"
    end
  end
end
