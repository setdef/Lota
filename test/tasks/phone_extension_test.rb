# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../ext/lota/phone/extension"
require "digest"
require "stringio"

# Lota::PhoneExtension packs Lota's extension as built for one phone
# target, and fetches it from a release by the SHA-256 the gem pins, as
# Lota::PhoneEngine fetches the engine, refusing one built from other
# files or for a Ruby of another ABI. Its transport is a fake here, so the
# test reaches no network.
class PhoneExtensionTest < Minitest::Test
  include TreeHelper

  Answer = Lota::PhoneEngine::Answer
  Headers = Lota::PhoneExtension::Headers
  TARGET = "ios-arm64-simulator"
  URL = "https://github.com/setdef/Lota/releases/download/v1.2.3/"
  RELEASE = Headers.new(ruby_version: "4.1.0", digest: "a" * 64)
  PREVIEW = Headers.new(ruby_version: "4.1.0+5", digest: "b" * 64)

  # A tree of the files a gem's extension is built from.
  def ext(root)
    write(root, "ext/CMakeLists.txt", "project(lota)\n")
    write(root, "ext/engine/CMakeLists.txt", "add_library(lota_engine)\n")
    write(root, "ext/cmake/LotaExtension.cmake", "function(lota_extension)\nendfunction()\n")
    write(root, "ext/native/graphics.cpp", "void draw() {}\n")
    write(root, "ext/native/generated/graphics.cpp", "void line() {}\n")
    File.join(root, "ext")
  end

  # The bundle PhoneExtension.pack writes for +headers+ from the files
  # under +ext+, linked by +link+ against the engine at +engine+, as its
  # bytes.
  def bundle(root, ext, headers:, link: ["#{root}/engine/lib/liblota_engine.a", "-framework Metal"],
    engine: "#{root}/engine"
  )
    # In binary, so Windows writes no CR before the newline.
    FileUtils.mkdir_p(File.join(root, "build"))
    File.binwrite(File.join(root, "build/liblota_native.a"), "!<arch>\nnative")
    path = Lota::PhoneExtension.pack(into: File.join(root, "packed"), target: TARGET,
      archive: File.join(root, "build/liblota_native.a"), link:, engine:, ext:, headers:, fledge: "v0.14.0",
      version: "1.2.3")
    File.binread(path)
  end

  def host(body)
    asked = []
    transport = lambda do |uri|
      asked << uri.to_s
      (uri.to_s == "#{URL}lota-extension-#{TARGET}.tar.gz") ? Answer.new(status: 200, location: nil, body:) :
        Answer.new(status: 404, location: nil, body: "")
    end
    [transport, asked]
  end

  def extension(ext, body, headers:, pin: "release v1.2.3\n#{Digest::SHA256.hexdigest(body)}  lota-extension-#{TARGET}.tar.gz\n")
    transport, = host(body)
    Lota::PhoneExtension.new(TARGET, ext:, pin:, headers:, out: StringIO.new, transport:, pause: -> (_) {})
  end

  def test_fetch_unpacks_the_pinned_extension_and_its_link_names_the_fetched_engine
    in_tree do |root|
      ext = ext(root)
      body = bundle(root, ext, headers: RELEASE)

      folder = extension(ext, body, headers: RELEASE).fetch(cache: File.join(root, "cache"))

      assert_equal File.join(root, "cache", Digest::SHA256.hexdigest(body), TARGET), folder
      assert_equal "!<arch>\nnative", File.binread(File.join(folder, "lib/liblota_native.a"))
      assert_equal ["/fetched/engine/lib/liblota_engine.a", "-framework Metal"],
        Lota::PhoneExtension.link(folder, "/fetched/engine")
      manifest = JSON.parse(File.read(File.join(folder, "manifest.json")))
      assert_equal({
"target" => TARGET,
"lota" => "1.2.3",
"extension_digest" => Lota::PhoneExtension.digest(ext),
"fledge" => "v0.14.0",
"ruby_version" => "4.1.0",
"ruby_headers_digest" => "a" * 64,
}, manifest)
    end
  end

  # A gem built between releases pins the last release's extension, built
  # from other files, so it compiles its own, as a gem that pins none does.
  def test_an_extension_built_from_other_files_is_not_used_and_the_build_says_why
    in_tree do |root|
      ext = ext(root)
      body = bundle(root, ext, headers: RELEASE)
      write(root, "ext/native/graphics.cpp", "void draw(int) {}\n")
      out = StringIO.new
      transport, = host(body)
      extension = Lota::PhoneExtension.new(TARGET, ext:, headers: RELEASE, out:, transport:, pause: -> (_) {},
        pin: "release v1.2.3\n#{Digest::SHA256.hexdigest(body)}  lota-extension-#{TARGET}.tar.gz\n")

      assert_nil extension.fetch(cache: File.join(root, "cache"))
      assert_match(/extension this Lota pins for #{TARGET} was built from other files than #{ext}'s/, out.string)
      assert_includes out.string, "So Lota compiles its extension for #{TARGET}."
    end
  end

  def test_an_empty_pin_pins_no_extension
    in_tree do |root|
      refute_predicate Lota::PhoneExtension.new(TARGET, ext: ext(root), headers: RELEASE, pin: ""), :pinned?
    end
  end

  def test_fetch_refuses_an_extension_built_for_a_ruby_of_another_abi
    in_tree do |root|
      ext = ext(root)
      body = bundle(root, ext, headers: PREVIEW)

      error = assert_raises(Lota::PhoneExtension::OtherRuby) do
        extension(ext, body, headers: RELEASE).fetch(cache: File.join(root, "cache"))
      end

      assert_equal "The extension this Lota pins for #{TARGET} was built for Ruby 4.1.0+5, the phone Ruby of " \
        "Fledge v0.14.0, and this phone's Ruby is 4.1.0, whose ABI differs. Name Fledge v0.14.0 in the Gemfile, " \
        "or compile the extension for this Ruby: pass --with-rice-dir=DIR, the rice gem's directory, with CMake " \
        "on PATH.", error.message
    end
  end

  # A build that can compile the extension, given Rice, compiles it for
  # its own Ruby instead, and says why.
  def test_a_build_that_can_compile_compiles_in_place_of_an_extension_for_another_ruby
    in_tree do |root|
      ext = ext(root)
      body = bundle(root, ext, headers: PREVIEW)
      out = StringIO.new
      transport, = host(body)
      extension = Lota::PhoneExtension.new(TARGET, ext:, headers: RELEASE, compiles: true, out:, transport:,
        pause: -> (_) {}, pin: "release v1.2.3\n#{Digest::SHA256.hexdigest(body)}  lota-extension-#{TARGET}.tar.gz\n")

      assert_nil extension.fetch(cache: File.join(root, "cache"))
      assert_includes out.string, "and this phone's Ruby is 4.1.0, whose ABI differs."
      assert_includes out.string, "So Lota compiles its extension for #{TARGET}."
    end
  end

  # A development Ruby's ABI number is bumped by hand, so its headers must
  # be the same ones; a released Ruby keeps its ABI across teeny versions,
  # whose headers may differ.
  def test_only_a_development_ruby_also_needs_the_same_headers
    in_tree do |root|
      ext = ext(root)
      preview = bundle(root, ext, headers: PREVIEW)
      error = assert_raises(Lota::PhoneExtension::OtherRuby) do
        extension(ext, preview, headers: PREVIEW.with(digest: "c" * 64)).fetch(cache: File.join(root, "cache"))
      end
      assert_includes error.message, "was built for Ruby 4.1.0+5, the phone Ruby of Fledge v0.14.0, and this " \
        "phone's Ruby has other headers, which alone tell a development Ruby's ABI. Name Fledge v0.14.0"

      release = bundle(root, ext, headers: RELEASE)
      folder = extension(ext, release, headers: RELEASE.with(digest: "c" * 64)).fetch(cache: File.join(root, "cache"))
      assert_path_exists File.join(folder, "lib/liblota_native.a")
    end
  end

  def test_a_pin_of_the_engine_alone_pins_no_extension
    in_tree do |root|
      ext = ext(root)
      body = bundle(root, ext, headers: RELEASE)
      pin = "release v1.2.3\n#{'d' * 64}  lota-engine-#{TARGET}.tar.gz\n"

      refute_predicate extension(ext, body, headers: RELEASE, pin:), :pinned?
      assert_predicate extension(ext, body, headers: RELEASE), :pinned?
    end
  end

  def test_the_digest_covers_the_engine_files_and_the_extensions_own
    in_tree do |root|
      ext = ext(root)
      before = Lota::PhoneExtension.digest(ext)

      write(root, "ext/native/generated/graphics.cpp", "void line(int) {}\n")
      after_native = Lota::PhoneExtension.digest(ext)
      write(root, "ext/engine/CMakeLists.txt", "add_library(lota_engine STATIC)\n")

      refute_equal before, after_native
      refute_equal after_native, Lota::PhoneExtension.digest(ext)
      refute_equal Lota::PhoneEngine.digest(ext), Lota::PhoneExtension.digest(ext)
    end
  end

  def test_headers_are_the_ruby_version_and_a_digest_of_every_header
    in_tree do |root|
      write(root, "include/ruby.h", "#include \"ruby/ruby.h\"\n")
      write(root, "include/ruby/config.h", "#define SIZEOF_VALUE 8\n")
      config = { "ruby_version" => "4.1.0+5", "rubyhdrdir" => "#{root}/include", "rubyarchhdrdir" => "#{root}/include" }
      before = Headers.of(config)

      write(root, "include/ruby/config.h", "#define SIZEOF_VALUE 4\n")

      assert_equal "4.1.0+5", before.ruby_version
      assert_predicate before, :development?
      refute_predicate Headers.of(config.merge("ruby_version" => "4.1.0")), :development?
      refute_equal before.digest, Headers.of(config).digest
    end
  end

  def test_pack_writes_the_same_bytes_from_the_same_build
    in_tree do |root|
      ext = ext(root)

      assert_equal bundle(root, ext, headers: RELEASE), bundle(root, ext, headers: RELEASE)
      assert_equal "lota-extension-android-arm64-v8a.tar.gz", Lota::PhoneExtension.asset("android-arm64-v8a")
    end
  end
end
