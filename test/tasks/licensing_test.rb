# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/licensing"

# Licensing reads ext/lota/licenses.rb and decides which of its works the
# bundle carries, from LinkedFiles, which reads the linker's map and
# ninja's dependency log.
class LicensingTest < Minitest::Test
  include TreeHelper

  BUILD = File.join(ROOT, "tmp/engine/build")
  LIBRARIES = File.join(ROOT, "vendor/love/src/libraries")

  def record
    Licensing.load(File.join(ROOT, "ext/lota/licenses.rb"))
  end

  # A linker map's object files, as ld -map writes them.
  def map(*objects)
    listed = objects.each_with_index.map { |object, index| "[#{index + 1}] #{object}\n" }.join
    "# Path: /build/lib/x.bundle\n# Arch: arm64\n# Object files:\n[  0] linker synthesized\n#{listed}" \
      "# Sections:\n# Address\tSize\n"
  end

  # ninja -t deps's report on each object, to what it read.
  def deps(objects)
    objects.map do |object, inputs|
      "#{object}: #deps #{inputs.size}, deps mtime 1 (VALID)\n#{inputs.map { |input| "    #{input}\n" }.join}\n"
    end.join
  end

  def test_an_archive_member_is_each_object_of_its_target_with_its_name
    linked = LinkedFiles.parse(map("engine/libengine.a(Font.cpp.o)", "/toolchain/librt.a(version.c.o)"), deps(
      "engine/CMakeFiles/engine.dir/src/font/Font.cpp.o" => ["/src/font/Font.cpp", "/src/font/Font.h"],
      "engine/CMakeFiles/engine.dir/src/graphics/Font.cpp.o" => ["/src/graphics/Font.cpp"],
      "engine/CMakeFiles/engine.dir/src/Data.cpp.o" => ["/src/Data.cpp"],
      "other/CMakeFiles/other.dir/Font.cpp.o" => ["/other/Font.cpp"]
    ), build: "/build")

    assert_equal ["/src/font/Font.cpp", "/src/font/Font.h", "/src/graphics/Font.cpp", "/toolchain/librt.a"],
      linked.files.sort
    assert_equal ["/src/font/Font.cpp", "/src/graphics/Font.cpp"], linked.sources.sort
    assert_equal ["/other/Font.cpp", "/src/Data.cpp", "/src/font/Font.cpp", "/src/graphics/Font.cpp"],
      linked.compiled.sort
  end

  def test_a_map_without_object_files_fails
    assert_raises(LinkedFiles::Failure) { LinkedFiles.parse("# Path: x\n", "", build: "/build") }
    assert_raises(LinkedFiles::Failure) { LinkedFiles.parse("Memory Configuration\n", "", build: "/build") }
  end

  # GNU ld's map (-Map), on Linux: each archive member it took starts a
  # line of the section that says why, its reason on the next line when
  # the member's name is long, and each object it loaded whole is a LOAD
  # line, among the archives and shared libraries it searched.
  def test_gnu_lds_map_lists_the_members_it_took_and_the_objects_it_loaded
    map = <<~MAP
      Archive member included to satisfy reference by file (symbol)

      engine/libengine.a(Font.cpp.o)
                                    native/CMakeFiles/native.dir/font.cpp.o (love::font::Font::Font())
      /usr/lib/gcc/aarch64-linux-gnu/11/libgcc.a(lse-init.o)  native/CMakeFiles/native.dir/font.cpp.o (__aarch64_have_lse_atomics)

      Discarded input sections

       .text          0x0000000000000000        0x0 /usr/lib/gcc/aarch64-linux-gnu/11/crtbeginS.o

      Memory Configuration

      Linker script and memory map

      LOAD /usr/lib/gcc/aarch64-linux-gnu/11/crtbeginS.o
      LOAD native/CMakeFiles/native.dir/font.cpp.o
      LOAD engine/libengine.a
      LOAD /usr/lib/gcc/aarch64-linux-gnu/11/libstdc++.so
    MAP
    linked = LinkedFiles.parse(map, deps(
      "native/CMakeFiles/native.dir/font.cpp.o" => ["/src/native/font.cpp"],
      "engine/CMakeFiles/engine.dir/src/font/Font.cpp.o" => ["/src/font/Font.cpp"]
    ), build: "/build")

    assert_equal [
      "/src/font/Font.cpp",
      "/src/native/font.cpp",
      "/usr/lib/gcc/aarch64-linux-gnu/11/crtbeginS.o",
      "/usr/lib/gcc/aarch64-linux-gnu/11/libgcc.a",
],
      linked.files.sort
    assert_equal ["/src/font/Font.cpp", "/src/native/font.cpp"], linked.sources.sort
  end

  def test_a_work_covers_the_files_under_its_globs
    lz4 = record.works.find { |work| work.name == "LZ4" }
    noto = record.works.find { |work| work.name == "Noto Sans" }

    assert lz4.covers?(File.join(LIBRARIES, "lz4/lz4.c"), ROOT)
    refute lz4.covers?(File.join(LIBRARIES, "lz4hc/lz4.c"), ROOT)
    assert noto.covers?(File.join(ROOT, "vendor/love/src/modules/font/NotoSans-Regular.ttf.gzip.h"), ROOT)
    refute noto.covers?(File.join(ROOT, "vendor/love/src/modules/font/Font.cpp"), ROOT)
  end

  # Rice's headers are in the rice gem Bundler installed, not the
  # repository.
  def test_a_work_of_a_gem_covers_the_gems_files
    rice = record.works.find { |work| work.name == "Rice" }
    header = File.join(Gem::Specification.find_by_name("rice").full_gem_path, "include/rice/rice.hpp")

    assert rice.covers?(header, ROOT)
  end

  def test_a_work_records_its_copyright_and_license_unless_they_are_pending
    licensing = Licensing.new

    assert_raises(Licensing::Invalid) { licensing.work("A", sources: ["a/**"], copyright: [], license: ["MIT"]) }
    assert_raises(Licensing::Invalid) { licensing.work("B", sources: ["b/**"], copyright: ["2026 B"]) }
    licensing.work("C", sources: ["c/**"], copyright: [], pending: "no license text")

    assert_equal ["C"], licensing.works.map(&:name)
  end

  # LodePNG's object is linked, so the bundle carries it; stb_image has no
  # object of its own, so reading its header carries it; PhysicsFS has
  # objects, none linked, so reading physfs.h's declarations does not.
  def test_a_work_is_carried_by_a_linked_object_or_by_a_header_only_librarys_header
    lodepng = File.join(LIBRARIES, "lodepng/lodepng.cpp")
    stb = File.join(LIBRARIES, "stb/stb_image.h")
    physfs = File.join(LIBRARIES, "physfs/physfs.h")
    linked = LinkedFiles.new(files: [lodepng, stb, physfs], sources: [lodepng],
      compiled: [lodepng, File.join(LIBRARIES, "physfs/physfs.c")])

    assert_equal %w[LodePNG stb_image], record.bundled(linked, root: ROOT, outside: []).map(&:name)
  end

  def test_a_file_no_work_covers_is_unrecorded_unless_it_is_outside
    stray = File.join(LIBRARIES, "box3d/box3d.cpp")
    linked = LinkedFiles.new(files: [stray], sources: [stray], compiled: [stray])

    error = assert_raises(Licensing::Unrecorded) { record.bundled(linked, root: ROOT, outside: []) }
    assert_includes error.message, stray
    assert_empty record.bundled(linked, root: ROOT, outside: ["#{LIBRARIES}/"])
  end

  # A shared library on Linux is recorded under its soname, as a framework
  # is under its name.
  def test_a_library_is_recorded_as_a_framework_is
    licensing = Licensing.new("record.rb")
    licensing.library("libx.so.1", copyright: ["2026 X"], license: ["Zlib"])

    assert_equal ["Zlib"], licensing.framework_for("libx.so.1").license
  end

  # Two libraries built from one source, as libvorbis and libvorbisfile
  # are, carry its archive once.
  def test_an_archive_two_libraries_share_is_carried_once
    licensing = Licensing.new("record.rb")
    source = {
url: "https://example.com/x.tar.gz",
sha256: "ab",
path: "vendor/sources/x.tar.gz",
copyright: ["2026 X"],
license: ["LGPL-2.0-or-later"],
}
    licensing.library("libx.so.1", copyright: ["2026 X"], license: ["LGPL-2.0-or-later"], source:)
    licensing.library("libxfile.so.1", copyright: ["2026 X"], license: ["LGPL-2.0-or-later"], source:)

    assert_equal 1, licensing.sources(["libx.so.1", "libxfile.so.1"]).size
  end

  # rake compile's bundle, as the linker and ninja report it: the
  # libraries its graphics, images, and filesystem need, and none it only
  # declares.
  def test_the_real_bundle_carries_what_its_objects_were_compiled_from
    linked = LinkedFiles.read(map: File.join(BUILD, "lib/lota/native.map"), build: BUILD)
    linux = RUBY_PLATFORM.include?("linux")
    outside = [
      linux ? "/usr" : `xcode-select --print-path`.strip,
      RbConfig::CONFIG["rubyhdrdir"],
      File.join(ROOT, linux ? "tmp/dependencies/installdir" : "vendor/love-apple-dependencies"),
].map { |dir| File.join(dir, "") }
    names = record.bundled(linked, root: ROOT, outside:).map(&:name)

    [
      "Lota",
      "Rice",
      "LodePNG",
      "glslang",
      "SPIRV-Cross",
      "PhysicsFS",
      "PhysicsFS's miniz",
      "PhysicsFS's LZMA SDK",
      "Noto Sans",
      "LÖVE",
].each { |name| assert_includes names, name }
    refute_includes names, "Noise1234"
  end

  def test_annotations_record_each_works_copyright_and_license_and_name_what_is_pending
    licensing = Licensing.new("record.rb")
    licensing.work("Quoted", sources: ["q/**"], copyright: [%(2026 "Q" \\ Co)], license: ["MIT"])
    licensing.work("Font", sources: ["f/**"], copyright: ["2019 F"], pending: "OFL-1.1")
    licensing.framework("X.framework", copyright: ["2026 X"], license: ["Zlib"])
    toml = licensing.annotations(bundle: "lib/x.bundle", works: licensing.works,
      frameworks: { "X.framework" => "lib/frameworks/X.framework/**" })

    assert_equal <<~TOML, toml
      # Licenses the maintainer has yet to decide, left out below (record.rb):
      #   Font: OFL-1.1
      [[annotations]]
      path = "lib/x.bundle"
      SPDX-FileCopyrightText = [
        "2026 \\"Q\\" \\\\ Co",
        "2019 F",
      ]
      SPDX-License-Identifier = [
        "MIT",
      ]

      [[annotations]]
      path = "lib/frameworks/X.framework/**"
      SPDX-FileCopyrightText = [
        "2026 X",
      ]
      SPDX-License-Identifier = [
        "Zlib",
      ]
    TOML
  end

  # A framework whose license asks for its source records its archive,
  # which gets an annotation of its own in the gem's sources/.
  def test_a_frameworks_source_archive_is_annotated_in_sources
    licensing = Licensing.new("record.rb")
    licensing.framework("X.framework", copyright: ["2026 X"], license: ["LGPL-2.0-or-later"],
      source: {
url: "https://example.com/x-1.0.tar.bz2",
sha256: "ab",
path: "vendor/sources/x-1.0.tar.bz2",
copyright: ["2026 X", "2025 Y"],
license: ["LGPL-2.0-or-later", "GPL-2.0-or-later"],
})
    toml = licensing.annotations(bundle: "lib/x.bundle", works: [],
      frameworks: { "X.framework" => "lib/frameworks/X.framework/**" })

    assert_equal "x-1.0.tar.bz2", licensing.sources(["X.framework"]).first.name
    assert toml.end_with?(<<~TOML), toml
      [[annotations]]
      path = "sources/x-1.0.tar.bz2"
      SPDX-FileCopyrightText = [
        "2026 X",
        "2025 Y",
      ]
      SPDX-License-Identifier = [
        "LGPL-2.0-or-later",
        "GPL-2.0-or-later",
      ]
    TOML
  end

  def test_a_framework_the_record_lacks_is_unrecorded
    error = assert_raises(Licensing::Unrecorded) { Licensing.new("record.rb").framework_for("Y.framework") }

    assert_equal "Y.framework has no recorded license; record its copyright and license in record.rb", error.message
  end
end
