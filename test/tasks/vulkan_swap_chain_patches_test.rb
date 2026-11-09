# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"

# ext/lota/engine/vulkan_semaphores.patch and vulkan_submit.patch, which
# CMake applies to a copy of LÖVE's vulkan/Graphics.cpp wherever it builds
# LÖVE's Vulkan renderer. What they change happens only where LÖVE draws
# with Vulkan: when a driver gives a rebuilt swap chain more images than
# the first, and when a frame's submit fails. CI and the gate draw with
# OpenGL, so no test here runs either change; Linux's build compiles them.
# These tests check what can be read: that each applies to the pinned
# vendor/love as CMake applies it, in CMake's order, that each changes
# only the function it is for, and that CMake applies them where LÖVE
# builds the renderer.
class VulkanSwapChainPatchesTest < Minitest::Test
  include TreeHelper

  ENGINE = File.join(ROOT, "ext/lota/engine")
  SEMAPHORES = File.join(ENGINE, "vulkan_semaphores.patch")
  SUBMIT = File.join(ENGINE, "vulkan_submit.patch")
  PRESENT = File.join(ENGINE, "vulkan_present.patch")
  SOURCE = "src/modules/graphics/vulkan/Graphics.cpp"
  LOVE = File.join(ROOT, "vendor/love", SOURCE)

  def test_each_applies_to_the_pinned_love_alone_and_in_cmakes_order_on_android
    [[SEMAPHORES], [SUBMIT], [SEMAPHORES, SUBMIT], [SEMAPHORES, SUBMIT, PRESENT]].each do |patches|
      refute_equal File.read(LOVE), apply(*patches), "#{patches.map { File.basename(it) }} change nothing"
    end
  end

  def test_a_rebuilt_swap_chain_gets_a_semaphore_for_each_image_it_adds
    body = function(apply(SEMAPHORES), "void Graphics::recreateSwapChain()")
    added = body[/^\tfor \(size_t i = renderFinishedSemaphores\.size\(\); i < swapChainImages\.size\(\); i\+\+\)\n\t\{\n.*?^\t\}\n/m]

    refute_nil added, "recreateSwapChain makes the semaphores of the images a new swap chain adds"
    assert_operator body.index("\tcreateSwapChain();"), :<, body.index(added)
    assert_operator body.index(added), :<, body.index("\tswapChainRequestFlags = SWAP_CHAIN_REQUEST_KEEP;")
    assert_includes added, "vkCreateSemaphore(device, &semaphoreInfo, nullptr, &semaphore)"
    assert_includes added, "renderFinishedSemaphores.push_back(semaphore);"
  end

  def test_the_semaphores_patch_changes_recreate_swap_chain_alone
    patched = apply(SEMAPHORES)
    love = File.read(LOVE)
    name = "void Graphics::recreateSwapChain()"

    assert_equal love.sub(function(love, name), ""), patched.sub(function(patched, name), "")
  end

  def test_a_frame_whose_commands_end_unsubmitted_records_again
    body = function(apply(SUBMIT), "StrongRef<image::ImageData> Graphics::submitGpuCommands(SubmitMode submitMode)")
    guard = body[/^\tstruct RestartUnsubmittedFrame\n.*?^\t\} restartUnsubmittedFrame = \{ \*this, imageRequested, false \};\n/m]

    refute_nil guard, "submitGpuCommands guards the frame from where its commands end"
    assert_operator body.index(guard), :<, body.index("\tendRecordingGraphicsCommands();")
    submit = body.index("\tVkResult result = vkQueueSubmit(graphicsQueue, 1, &submitInfo, fence);")
    disarm = body.index("\trestartUnsubmittedFrame.submitted = true;")

    assert_operator submit, :<, disarm
    assert_operator body.index("Failed to submit Vulkan draw command buffer", submit), :<, disarm,
      "the guard stays armed until vkQueueSubmit has succeeded"
    restart = guard[/~RestartUnsubmittedFrame\(\)\n(.*)\n\t\t\}\n/m, 1]

    assert_match(/if \(submitted\)\n\t\t\t\treturn;/, restart)
    assert_match(/graphics\.imageRequested = imageRequested;\n\t\t\t\tgraphics\.startRecordingGraphicsCommands\(\);/, restart)
    ["swapChainImages[graphics.imageIndex]", "graphics.depthImage", "graphics.colorImage"].each do |image|
      assert_match(/#{Regexp.escape(image)}, [^\n]*\n\t+VK_IMAGE_LAYOUT_UNDEFINED, /, restart)
    end
    assert_match(/catch \(\.\.\.\)/, restart, "an error while restarting does not end the program as it unwinds")
  end

  def test_the_submit_patch_changes_submit_gpu_commands_alone
    patched = apply(SUBMIT)
    love = File.read(LOVE)
    name = "StrongRef<image::ImageData> Graphics::submitGpuCommands(SubmitMode submitMode)"

    assert_equal love.sub(function(love, name), ""), patched.sub(function(patched, name), "")
  end

  def test_cmake_applies_them_wherever_love_builds_vulkan_and_android_s_after_them
    cmake = File.read(File.join(ENGINE, "CMakeLists.txt"))
    not_apple = cmake[/^if\(NOT APPLE\)\n(.*?)^endif\(\)/m, 1]
    android = cmake[/^if\(CMAKE_SYSTEM_NAME STREQUAL "Android"\)\n(.*?)^endif\(\)/m, 1]

    expected = "\tlist(APPEND PATCHES vulkan_semaphores vulkan_submit)\n\tlist(APPEND PATCHED_FILES_ALONE VULKAN_SOURCE)\n"

    assert_equal expected, not_apple
    assert_equal "\tlist(APPEND PATCHES vulkan_present)\n", android
    assert_operator cmake.index(not_apple), :<, cmake.index(android)
    %w[linux windows android].each do |platform|
      assert_includes File.read(File.join(ENGINE, "sources_#{platform}.cmake")), SOURCE
    end
    %w[macos ios].each do |platform|
      refute_includes File.read(File.join(ENGINE, "sources_#{platform}.cmake")), SOURCE
    end
  end

  # The definition of the function +signature+ names in +source+, from its
  # signature to its closing brace.
  private def function(source, signature)
    source[/^#{Regexp.escape(signature)}\n\{\n.*?^\}\n/m] or flunk("#{signature} is not in the file")
  end

  # LÖVE's file as +patches+, applied in order with CMake's command to a
  # copy, leave it.
  private def apply(*patches)
    in_tree do |dir|
      write(dir, SOURCE, File.read(LOVE))
      patches.each do |patch|
        run!(dir, "patch", "-p1", "--forward", "--batch", "--silent", "--no-backup-if-mismatch", "-i", patch)
      end
      File.read(File.join(dir, SOURCE))
    end
  end
end
