# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require "digest"
require_relative "../../tasks/phone_notices"

# PhoneNotices writes a phone app's notices (rake ios:notices, rake
# android:notices) from the works ext/lota/licenses.rb records for the
# phone, which are what its desktop counterpart's bundle carries: macOS's
# for iOS, Linux's for Android.
class PhoneNoticesTest < Minitest::Test
  include TreeHelper

  VULKAN = ["Vulkan-Headers", "volk", "Vulkan Memory Allocator"].freeze

  def record
    @record ||= Licensing.load(File.join(ROOT, "ext/lota/licenses.rb"))
  end

  def components(phone)
    PhoneNotices.new(licensing: record, phone:, root: ROOT).components
  end

  def engine_sources(platform)
    File.readlines(File.join(ROOT, "ext/lota/engine/sources_#{platform}.cmake")).grep(/ENGINE_SOURCE_DIR/).map(&:strip)
  end

  # The record takes each phone's works from its desktop counterpart, which
  # holds only while the engine compiles the same files for both: iOS's
  # list is macOS's with ios.mm for macos.mm, and Android's is Linux's.
  def test_each_phone_compiles_what_its_desktop_counterpart_compiles
    macos = engine_sources("macos").map { |line| line.sub("src/common/macos.mm", "src/common/ios.mm") }

    assert_equal macos, engine_sources("ios")
    assert_equal engine_sources("linux"), engine_sources("android")
  end

  # iOS, as macOS, carries no Vulkan code, plays through Apple's OpenAL, and
  # links every library into the app's executable.
  def test_ios_names_its_archives_in_the_executable_and_no_vulkan_or_openal_soft
    ios = components("iOS")
    names = ios.map(&:name)

    assert_empty VULKAN & names
    assert_includes names, "LÖVE"
    assert_includes names, "Rice"
    refute_includes names, "OpenAL Soft"
    assert_equal names.uniq, names
    assert_equal ["the app's executable"], ios.map(&:file).uniq
    refute ios.any?(&:separate)
    assert_equal ["2.11.1"], ios.select { |component| component.name == "FreeType" }.map(&:version)
    assert_equal ["3.4.10"], ios.select { |component| component.name == "SDL" }.map(&:version)
  end

  # Android, as Linux, carries Vulkan's code, and ships OpenAL Soft and SDL
  # as libraries of their own, OpenAL Soft with its source in the app.
  def test_android_names_vulkan_and_its_two_libraries_with_openal_softs_source
    android = components("Android")
    by_name = android.to_h { |component| [component.name, component] }

    assert_equal VULKAN, VULKAN & by_name.keys
    assert_equal android.size, by_name.size
    assert_equal "1.3", by_name.fetch("zlib").version
    assert_equal "2.13.3", by_name.fetch("FreeType").version
    assert_includes by_name.fetch("FreeType").credit, "The FreeType Project"
    assert_equal "libfledgeext.so", by_name.fetch("LÖVE").file
    openal = by_name.fetch("OpenAL Soft")

    assert_equal ["libopenal.so", true, "1.24.3"], [openal.file, openal.separate, openal.version]
    assert_equal "app/sources/openal-soft-1.24.3.tar.bz2", openal.source&.file
    assert_equal ["libSDL3.so", true, "3.4.10"], by_name.fetch("SDL").then { |sdl| [sdl.file, sdl.separate, sdl.version] }
  end

  def test_no_work_of_another_platform_reaches_a_phone
    windows = record.works.select { |work| work.platform == "Windows" }.map(&:name)

    refute_empty windows
    %w[iOS Android].each do |phone|
      linked = record.phone_works(phone)

      assert_empty linked.map(&:name) & windows
      assert(linked.all? { |work| [nil, phone].include?(work.platform) })
    end
  end

  def test_a_work_whose_license_is_pending_is_not_named
    pending = record.works.select(&:pending).map(&:name)

    refute_empty pending
    %w[iOS Android].each { |phone| assert_empty record.phone_works(phone).map(&:name) & pending }
  end

  def test_the_text_says_where_the_app_holds_lota_and_its_libraries
    text = PhoneNotices.new(licensing: record, phone: "Android", root: ROOT).text

    assert_includes text, "rake android:notices wrote this file into this app's project"
    assert_includes text, "  In this app: app/vendor/cache/lota\n"
    assert_includes text, "\nCompiled into Lota's extension, libfledgeext.so:\n"
    assert_includes text, "\nA library of its own, libopenal.so:\n\nOpenAL Soft 1.24.3\n"
    assert_includes text, "  Source: app/sources/openal-soft-1.24.3.tar.bz2\n"
    assert_includes text, "\n==== LGPL-2.0-or-later ====\n"
  end

  # A record of its own, with an archive whose SHA-256 it records, in a
  # tree that holds the license texts.
  def small_record(root, archive)
    write(root, "LICENSES/AGPL-3.0-or-later.txt", "AGPL text\n")
    write(root, "ext/lota/licenses/LICENSE-Zlib.txt", "Zlib text\n")
    write(root, "ext/lota/licenses/LICENSE-LGPL-2.0-or-later.txt", "LGPL text\n")
    write(root, "vendor/sources/x-1.0.tar.bz2", archive)
    licensing = Licensing.new(File.join(root, "record.rb"))
    licensing.work("Engine", sources: ["e/**"], copyright: ["2026 E"], license: ["Zlib"])
    licensing.library("libx.so", title: "X", version: "1.0", copyright: ["2026 X"], license: ["LGPL-2.0-or-later"],
      source: {
url: "https://example.com/x-1.0.tar.bz2",
sha256: Digest::SHA256.hexdigest("x's source"),
path: "vendor/sources/x-1.0.tar.bz2",
copyright: ["2026 X"],
license: ["LGPL-2.0-or-later"],
})
    licensing.phone("Android", extension: "libfledgeext.so", libraries: ["libx.so"])
    licensing
  end

  def test_it_writes_the_notices_and_the_source_archive_into_the_project
    in_tree do |root|
      project = File.join(root, "MyGame-phone")
      FileUtils.mkdir_p(project)
      PhoneNotices.new(licensing: small_record(root, "x's source"), phone: "Android", root:).write(project)

      text = File.read(File.join(project, "NOTICES.txt"))

      assert_includes text, "Engine\n  License: Zlib\n  Copyright 2026 E"
      assert_includes text, "  Source: app/sources/x-1.0.tar.bz2\n"
      assert_equal "x's source", File.read(File.join(project, "sources/x-1.0.tar.bz2"))
    end
  end

  def test_an_archive_that_is_not_the_recorded_one_writes_nothing
    in_tree do |root|
      project = File.join(root, "MyGame-phone")
      FileUtils.mkdir_p(project)
      notices = PhoneNotices.new(licensing: small_record(root, "another source"), phone: "Android", root:)

      assert_raises(SourceArchive::Failure) { notices.write(project) }
      assert_empty Dir.children(project)
    end
  end

  def test_a_phone_cannot_leave_out_a_work_the_record_lacks
    licensing = Licensing.new("record.rb")
    licensing.work("Engine", sources: ["e/**"], copyright: ["2026 E"], license: ["Zlib"])

    error = assert_raises(Licensing::Invalid) { licensing.phone("iOS", extension: "x", without: ["Engine", "Nothing"]) }
    assert_equal "iOS leaves out Nothing, which record.rb does not record", error.message
  end
end
