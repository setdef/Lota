# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"

# ext/lota/engine/vulkan_present.patch, which CMake applies to a copy of
# LÖVE's vulkan/Graphics.cpp for Android alone. What it changes happens
# only on an Android device whose Vulkan driver LÖVE uses: an emulator
# falls back to OpenGL ES, so no test here or in CI runs it. These tests
# check what can be read: that it applies to the pinned vendor/love as
# CMake applies it, and that outside LOVE_ANDROID the file is LÖVE's.
class VulkanPresentPatchTest < Minitest::Test
  include TreeHelper

  PATCH = File.join(ROOT, "ext/lota/engine/vulkan_present.patch")
  SOURCE = "src/modules/graphics/vulkan/Graphics.cpp"
  LOVE = File.join(ROOT, "vendor/love", SOURCE)

  def test_it_applies_to_the_pinned_love_as_cmake_applies_it
    patched = apply

    refute_equal File.read(LOVE), patched
  end

  def test_outside_love_android_the_file_is_loves
    patched = apply

    assert_equal File.read(LOVE), patched.sub("#{added_block(patched)}\n", "")
  end

  def test_on_android_a_suboptimal_present_is_a_success_before_love_reads_it
    patched = apply
    block = added_block(patched)
    love_reads = patched[/#{Regexp.escape(block)}\n(.*)\n/, 1]
    code = block.lines[1..-2].grep_v(%r{^\s*//}).join

    assert_equal "\tif (result == VK_SUBOPTIMAL_KHR)\n\t\tresult = VK_SUCCESS;\n", code
    assert_match(/\A\tif \(result == VK_ERROR_OUT_OF_DATE_KHR \|\| result == VK_SUBOPTIMAL_KHR/, love_reads)
  end

  def test_cmake_applies_it_on_android_alone
    cmake = File.read(File.join(ROOT, "ext/lota/engine/CMakeLists.txt"))
    guarded = cmake[/^if\(CMAKE_SYSTEM_NAME STREQUAL "Android"\)\n(.*?)^endif\(\)/m, 1]

    assert_includes guarded, "list(APPEND PATCHES vulkan_present)"
    assert_includes guarded, "list(APPEND PATCHED_FILES_ALONE VULKAN_PRESENT_SOURCE)"
    assert_includes cmake, "\nset(PATCHES physics mesh lz4)\nset(PATCHED_FILES_ALONE MESH_SOURCE LZ4_SOURCE)\n"
  end

  # The one #ifdef LOVE_ANDROID block of +patched+ that LÖVE's file lacks,
  # from #ifdef to #endif.
  private def added_block(patched)
    blocks = -> (text) { text.scan(/^#ifdef LOVE_ANDROID\n.*?^#endif\n/m) }
    added = blocks.(patched) - blocks.(File.read(LOVE))

    assert_equal 1, added.size, "the patch adds one #ifdef LOVE_ANDROID block"
    added.first
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
