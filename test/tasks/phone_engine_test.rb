# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../ext/lota/phone/engine"
require "digest"
require "stringio"
require "zlib"

# Lota::PhoneEngine fetches a phone's prebuilt engine from a release, by
# the SHA-256 the gem pins, and unpacks it. Its transport is a fake here,
# answering as a release's host does, so the test reaches no network.
class PhoneEngineTest < Minitest::Test
  include TreeHelper

  Answer = Lota::PhoneEngine::Answer
  TARGET = "android-x86_64"
  URL = "https://github.com/setdef/Lota/releases/download/v1.2.3/"

  # A tree of the engine files a gem carries, and their digest.
  def ext(root)
    write(root, "ext/CMakeLists.txt", "project(lota)\n")
    write(root, "ext/engine/CMakeLists.txt", "add_library(lota_engine)\n")
    write(root, "ext/engine/physics.patch", "--- a\n+++ b\n")
    File.join(root, "ext")
  end

  # A gzipped bundle holding +files+ and a manifest for +target+ built from
  # the engine files with +digest+.
  def bundle(digest:, target: TARGET, files: { "lib/liblota_engine.a" => "!<arch>\n" })
    manifest = JSON.generate({ "target" => target, "engine_digest" => digest })
    tar = StringIO.new(+"".b)
    Lota::PhoneEngine::Tar.write(tar, files.merge("manifest.json" => manifest))
    gzip = StringIO.new(+"".b)
    writer = Zlib::GzipWriter.new(gzip)
    writer.write(tar.string)
    writer.finish
    gzip.string
  end

  # A pin of +body+ as the bundle release v1.2.3 published.
  def pin(body, asset: Lota::PhoneEngine.asset(TARGET))
    "release v1.2.3\n#{Digest::SHA256.hexdigest(body)}  #{asset}\n"
  end

  # A host that answers from +routes+, a Hash of each URL to its Answer, and
  # records what was asked.
  def host(routes)
    asked = []
    transport = lambda do |uri|
      asked << uri.to_s
      routes.fetch(uri.to_s) { Answer.new(status: 404, location: nil, body: "") }
    end
    [transport, asked]
  end

  # The engine for TARGET, fetching from the pinned release unless +url+
  # names a mirror.
  def engine(ext, pin:, transport:, url: nil, out: StringIO.new, pause: -> (_) {})
    Lota::PhoneEngine.new(TARGET, ext:, pin:, url:, out:, transport:, pause:)
  end

  def test_fetch_follows_the_release_redirect_checks_the_pinned_sha256_and_unpacks_the_bundle
    in_tree do |root|
      ext = ext(root)
      body = bundle(digest: Lota::PhoneEngine.digest(ext), files: {
"lib/liblota_engine.a" => "engine",
"include/0/love/common/Object.h" => "#pragma once\n",
})
      transport, asked = host(
        "#{URL}lota-engine-android-x86_64.tar.gz" =>
          Answer.new(status: 302, location: "https://objects.example.com/asset?sig=1", body: ""),
        "https://objects.example.com/asset?sig=1" => Answer.new(status: 200, location: nil, body:)
      )

      folder = engine(ext, pin: pin(body), transport:).fetch(cache: File.join(root, "cache"))

      assert_equal File.join(root, "cache", Digest::SHA256.hexdigest(body), TARGET), folder
      assert_equal "engine", File.read(File.join(folder, "lib/liblota_engine.a"))
      assert_equal "#pragma once\n", File.read(File.join(folder, "include/0/love/common/Object.h"))
      assert_equal 2, asked.size
    end
  end

  def test_fetch_refuses_bytes_other_than_the_pinned_ones_and_keeps_nothing
    in_tree do |root|
      ext = ext(root)
      body = bundle(digest: Lota::PhoneEngine.digest(ext))
      transport, = host("#{URL}lota-engine-android-x86_64.tar.gz" => Answer.new(status: 200, location: nil,
        body: "#{body}tampered"))

      error = assert_raises(Lota::PhoneEngine::Failure) do
        engine(ext, pin: pin(body), transport:).fetch(cache: File.join(root, "cache"))
      end

      assert_match(/not the #{Digest::SHA256.hexdigest(body)} this Lota pins/, error.message)
      assert_empty Dir.glob("**/*.{gz,a}", base: File.join(root, "cache"))
    end
  end

  def test_fetch_downloads_once_and_reuses_what_it_unpacked
    in_tree do |root|
      ext = ext(root)
      body = bundle(digest: Lota::PhoneEngine.digest(ext))
      transport, asked = host("#{URL}lota-engine-android-x86_64.tar.gz" => Answer.new(status: 200, location: nil,
        body:))
      engine = engine(ext, pin: pin(body), transport:)

      first = engine.fetch(cache: File.join(root, "cache"))
      second = engine.fetch(cache: File.join(root, "cache"))

      assert_equal first, second
      assert_equal 1, asked.size
    end
  end

  def test_fetch_refuses_a_bundle_built_from_other_engine_files
    in_tree do |root|
      ext = ext(root)
      body = bundle(digest: Lota::PhoneEngine.digest(ext))
      write(root, "ext/engine/physics.patch", "--- a\n+++ b\n@@ changed @@\n")
      transport, = host("#{URL}lota-engine-android-x86_64.tar.gz" => Answer.new(status: 200, location: nil,
        body:))

      error = assert_raises(Lota::PhoneEngine::Failure) do
        engine(ext, pin: pin(body), transport:).fetch(cache: File.join(root, "cache"))
      end

      assert_match(/built from other engine files/, error.message)
      assert_match(/--with-lota-source/, error.message)
    end
  end

  def test_fetch_refuses_a_bundle_for_another_target
    in_tree do |root|
      ext = ext(root)
      body = bundle(digest: Lota::PhoneEngine.digest(ext), target: "android-arm64-v8a")
      transport, = host("#{URL}lota-engine-android-x86_64.tar.gz" => Answer.new(status: 200, location: nil,
        body:))

      error = assert_raises(Lota::PhoneEngine::Failure) do
        engine(ext, pin: pin(body), transport:).fetch(cache: File.join(root, "cache"))
      end

      assert_match(/for android-arm64-v8a, not android-x86_64/, error.message)
    end
  end

  def test_a_gem_that_pins_no_bundle_says_to_build_from_source
    in_tree do |root|
      transport, asked = host({})

      error = assert_raises(Lota::PhoneEngine::Failure) do
        engine(ext(root), pin: "", transport:).fetch(cache: File.join(root, "cache"))
      end

      assert_match(/pins no prebuilt engine for android-x86_64/, error.message)
      assert_match(/--with-lota-source=DIR/, error.message)
      assert_empty asked
    end
  end

  def test_a_server_error_is_tried_again_and_a_missing_asset_is_not
    in_tree do |root|
      ext = ext(root)
      body = bundle(digest: Lota::PhoneEngine.digest(ext))
      answers = [Answer.new(status: 503, location: nil, body: ""), Answer.new(status: 200, location: nil, body:)]
      waits = []
      engine(ext, pin: pin(body), transport: -> (_) { answers.shift }, pause: -> (seconds) { waits << seconds })
        .fetch(cache: File.join(root, "cache"))

      assert_equal [2], waits

      missing, = host({})
      error = assert_raises(Lota::PhoneEngine::Failure) do
        engine(ext, pin: pin(body), transport: missing, pause: -> (_) { flunk "retried a 404" })
          .fetch(cache: File.join(root, "other"))
      end
      assert_match(/answered 404/, error.message)
    end
  end

  def test_the_digest_covers_the_engine_files_and_not_the_extension
    in_tree do |root|
      ext = ext(root)
      before = Lota::PhoneEngine.digest(ext)
      write(root, "ext/native/graphics.cpp", "// the extension\n")

      assert_equal before, Lota::PhoneEngine.digest(ext)

      write(root, "ext/engine/dependencies_ios.cmake", "set(X 1)\n")

      refute_equal before, Lota::PhoneEngine.digest(ext)
    end
  end

  def test_sums_reads_what_sha256sum_writes_and_refuses_anything_else
    sha = "a" * 64

    assert_equal({ "x.tar.gz" => sha, "y.tar.gz" => sha },
      Lota::PhoneEngine.sums("#{sha}  x.tar.gz\n\n#{sha.upcase} *y.tar.gz\n"))
    assert_raises(Lota::PhoneEngine::Failure) { Lota::PhoneEngine.sums("not a checksum  x.tar.gz\n") }
  end

  # A clone's version names no release, so the pin names the one that
  # published the bundles, and a mirror stands in for it when asked.
  def test_the_pin_names_the_release_to_fetch_from_and_a_mirror_replaces_it
    in_tree do |root|
      ext = ext(root)
      body = bundle(digest: Lota::PhoneEngine.digest(ext))
      mirror = "https://mirror.example.com/lota/"
      transport, asked = host("#{mirror}lota-engine-android-x86_64.tar.gz" => Answer.new(status: 200, location: nil,
        body:))

      engine(ext, pin: pin(body), transport:, url: mirror).fetch(cache: File.join(root, "cache"))

      assert_equal ["#{mirror}lota-engine-android-x86_64.tar.gz"], asked

      error = assert_raises(Lota::PhoneEngine::Failure) do
        engine(ext, pin: pin(body).sub("release v1.2.3\n", ""), transport:).fetch(cache: File.join(root, "other"))
      end
      assert_match(/names no release to fetch lota-engine-android-x86_64.tar.gz from/, error.message)
    end
  end

  def test_pin_reads_one_release_and_the_checksums_and_pin_text_writes_them
    sha = "b" * 64
    text = Lota::PhoneEngine.pin_text("v0.5.0", "#{sha}  y.tar.gz\n#{sha}  x.tar.gz\n")

    assert_equal "release v0.5.0\n#{sha}  x.tar.gz\n#{sha}  y.tar.gz\n", text
    assert_equal Lota::PhoneEngine::Pin.new(release: "v0.5.0", sums: { "x.tar.gz" => sha, "y.tar.gz" => sha }),
      Lota::PhoneEngine.pin(text)
    assert_raises(Lota::PhoneEngine::Failure) { Lota::PhoneEngine.pin("release v1\nrelease v2\n") }
    assert_raises(Lota::PhoneEngine::Failure) { Lota::PhoneEngine.pin("release 0.0.1.dev\n") }
  end

  def test_the_cache_is_lotas_folder_in_the_users_cache
    assert_equal "/x/lota/phone-engine", Lota::PhoneEngine.cache({ "XDG_CACHE_HOME" => "/x", "HOME" => "/h" })
    assert_equal "/h/.cache/lota/phone-engine", Lota::PhoneEngine.cache({ "XDG_CACHE_HOME" => "", "HOME" => "/h" })
  end

  def test_a_target_lota_does_not_build_is_refused
    assert_raises(Lota::PhoneEngine::Failure) { Lota::PhoneEngine.new("android-armeabi-v7a", ext: "/x", pin: "") }
  end

  def test_tar_is_the_same_bytes_for_the_same_files_in_any_order_with_long_paths
    long = "include/3/#{'deep/' * 30}header.h"
    files = { "b.txt" => "b", "a/x.txt" => "x" * 700, long => "long" }
    one = StringIO.new(+"".b)
    two = StringIO.new(+"".b)

    Lota::PhoneEngine::Tar.write(one, files)
    Lota::PhoneEngine::Tar.write(two, files.to_a.reverse.to_h)

    assert_equal one.string, two.string
    in_tree do |root|
      Lota::PhoneEngine::Tar.extract(StringIO.new(one.string), root)

      assert_equal "x" * 700, File.read(File.join(root, "a/x.txt"))
      assert_equal "long", File.read(File.join(root, long))
      assert_equal "b", File.read(File.join(root, "b.txt"))
    end
  end

  def test_tar_refuses_a_path_outside_the_folder_and_a_link
    ["../escape.txt", "/etc/passwd", "a/../../b"].each do |path|
      tar = StringIO.new(+"".b)
      Lota::PhoneEngine::Tar.write(tar, { "ok.txt" => "" })
      block = tar.string.dup
      block[0, 100] = path.ljust(100, "\0")
      checksum_free = block[0, 512]

      in_tree do |root|
        assert_raises(Lota::PhoneEngine::Failure, path) do
          Lota::PhoneEngine::Tar.extract(StringIO.new(checksum_free + ("\0" * 1024)), root)
        end
        assert_empty Dir.children(root)
      end
    end

    link = StringIO.new(+"".b)
    Lota::PhoneEngine::Tar.write(link, { "ok.txt" => "" })
    linked = link.string.dup
    linked[156] = "2"
    in_tree do |root|
      assert_raises(Lota::PhoneEngine::Failure) { Lota::PhoneEngine::Tar.extract(StringIO.new(linked), root) }
    end
  end
end
