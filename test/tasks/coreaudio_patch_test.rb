# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"

# ext/lota/engine/coreaudio.patch, which CMake applies to a copy of LÖVE's
# sound/lullaby/CoreAudioDecoder.cpp for iOS alone. What it changes
# compiles only against Apple's iOS SDK, and the iOS Simulator check in
# .github/workflows/phones.yml decodes the sounds it lets Core Audio read.
# These tests check what can be read here: that it applies to the pinned
# vendor/love as CMake applies it, that the read callback seeks to the
# offset it is asked for before it reads, and that CMake compiles the
# decoder, patched, for iOS alone.
class CoreAudioPatchTest < Minitest::Test
  include TreeHelper

  PATCH = File.join(ROOT, "ext/lota/engine/coreaudio.patch")
  SOURCE = "src/modules/sound/lullaby/CoreAudioDecoder.cpp"
  LOVE = File.join(ROOT, "vendor/love", SOURCE)

  def test_it_applies_to_the_pinned_love_as_cmake_applies_it
    refute_equal File.read(LOVE), apply
  end

  def test_the_read_callback_seeks_to_the_offset_before_it_reads
    code = read_callback(apply).lines.grep_v(%r{^\s*//}).join

    assert_equal <<~CPP, code
      \tauto stream = (Stream *) inClientData;
      \tif (!stream->seek(inPosition))
      \t{
      \t\t*actualCount = 0;
      \t\treturn kAudioFilePositionError;
      \t}

      \tint64 readbytes = stream->read(buffer, requestCount);

      \t*actualCount = (UInt32) readbytes;
      \treturn readbytes > 0 ? noErr : kAudioFilePositionError;
    CPP
  end

  def test_outside_the_read_callback_the_file_is_loves
    patched = apply
    love = File.read(LOVE)

    assert_equal love.sub(read_callback(love), ""), patched.sub(read_callback(patched), "")
  end

  def test_cmake_compiles_the_patched_decoder_on_ios_alone
    cmake = File.read(File.join(ROOT, "ext/lota/engine/CMakeLists.txt"))
    guarded = cmake.scan(/^if\(CMAKE_SYSTEM_NAME STREQUAL "iOS"\)\n(.*?)^endif\(\)/m).flatten

    assert_includes guarded, "\tlist(APPEND ENGINE_SOURCES ${ENGINE_SOURCE_DIR}/${COREAUDIO_SOURCE})\n" \
      "\tlist(APPEND PATCHES coreaudio)\n\tlist(APPEND PATCHED_FILES_ALONE COREAUDIO_SOURCE)\n"
    assert_includes cmake, "\nset(COREAUDIO_SOURCE #{SOURCE})\n"
    assert_includes File.read(File.join(ROOT, "ext/lota/engine/dependencies_ios.cmake")),
      "\ntarget_compile_definitions(lota_engine PRIVATE LOVE_SUPPORT_COREAUDIO)\n"
  end

  # The body of readFunc in +source+, between its braces.
  private def read_callback(source)
    body = source[/^static OSStatus readFunc\(.*?\)\n\{\n(.*?)^\}\n/m, 1]

    refute_nil body, "the file has a readFunc"
    body
  end

  # LÖVE's file as the patch, applied with CMake's command to a copy,
  # leaves it.
  private def apply
    in_tree do |dir|
      write(dir, SOURCE, File.read(LOVE))
      run!(dir, "patch", "-p1", "--forward", "--batch", "--silent", "--no-backup-if-mismatch", "-i", PATCH)
      File.read(File.join(dir, SOURCE))
    end
  end
end
