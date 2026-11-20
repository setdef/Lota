# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/release"

# A release publishes the phone engines its run built beside its gems,
# with their checksums in its one SHA256SUMS (Release#add_engines), and
# CI's bookkeeping afterward pins that release's engines on trunk, as
# rake phone:engine:pin does: Release#pin_engines writes
# ext/lota/phone/engines.txt from a SHA256SUMS that lists them.
class ReleaseEnginesTest < Minitest::Test
  include TreeHelper

  ASSETS = Lota::PhoneEngine::TARGETS.map { |target| Lota::PhoneEngine.asset(target) }

  # The gems a release's SHA256SUMS lists beside the engines.
  GEMS = %w[lota-0.4.0-arm64-darwin.gem lota-0.4.0-x86_64-linux-gnu.gem].freeze

  # SHA256SUMS of the four engines, as phone-engine.yml writes it, each
  # bundle's checksum a different digit repeated.
  def sums(assets = ASSETS)
    assets.each_with_index.map { |asset, index| "#{index.to_s * 64}  #{asset}\n" }.join
  end

  # A release's SHA256SUMS: its gems' lines, then the engines'.
  def release_sums
    "#{GEMS.map { |gem| "#{'a' * 64}  #{gem}\n" }.join}#{sums}"
  end

  # The folder phone-engine.yml's phone-engines artifact unpacks to: each
  # engine, named +names+, holding its own name, and SHA256SUMS for them.
  def engines(root, names = ASSETS)
    names.each { |name| write(root, "engines/#{name}", name) }
    lines = names.map { |name| "#{Digest::SHA256.hexdigest(name)}  #{name}\n" }
    write(root, "engines/SHA256SUMS", lines.join)
    File.join(root, "engines")
  end

  # The folder Release#assemble leaves: two gems and their SHA256SUMS.
  def assembled(root)
    GEMS.each { |gem| write(root, "release/#{gem}", gem) }
    write(root, "release/SHA256SUMS", GEMS.map { |gem| "#{Digest::SHA256.hexdigest(gem)}  #{gem}\n" }.join)
    File.join(root, "release")
  end

  def test_add_engines_puts_each_engine_beside_the_gems_and_its_checksum_in_their_sha256sums
    in_tree do |root|
      release = assembled(root)

      assert_equal ASSETS, Release.new(root:).add_engines(release, engines(root))

      assert_equal (GEMS + ASSETS + ["SHA256SUMS"]).sort, Dir.children(release).sort
      ASSETS.each { |asset| assert_equal asset, File.read(File.join(release, asset)) }
      expected = (GEMS + ASSETS).sort.map { |name| "#{Digest::SHA256.hexdigest(name)}  #{name}\n" }.join
      assert_equal expected, File.read(File.join(release, "SHA256SUMS"))
    end
  end

  def test_add_engines_refuses_a_folder_without_every_engine_and_adds_nothing
    in_tree do |root|
      release = assembled(root)
      before = File.read(File.join(release, "SHA256SUMS"))

      error = assert_raises(Release::Refusal) { Release.new(root:).add_engines(release, engines(root, ASSETS.drop(1))) }

      assert_match(/missing #{Regexp.escape(ASSETS.first)}/, error.message)
      assert_equal (GEMS + ["SHA256SUMS"]).sort, Dir.children(release).sort
      assert_equal before, File.read(File.join(release, "SHA256SUMS"))
    end
  end

  def test_add_engines_refuses_an_engine_that_is_not_the_bytes_its_checksum_names
    in_tree do |root|
      release = assembled(root)
      from = engines(root)
      File.write(File.join(from, ASSETS.last), "other bytes")

      error = assert_raises(Release::Refusal) { Release.new(root:).add_engines(release, from) }

      assert_match(/#{Regexp.escape(ASSETS.last)} has SHA-256 #{Digest::SHA256.hexdigest('other bytes')}/, error.message)
      assert_equal (GEMS + ["SHA256SUMS"]).sort, Dir.children(release).sort
    end
  end

  def test_add_engines_refuses_checksums_that_name_other_files_than_the_folder_holds
    in_tree do |root|
      release = assembled(root)
      from = engines(root)
      File.write(File.join(from, "SHA256SUMS"), File.readlines(File.join(from, "SHA256SUMS")).drop(1).join)

      error = assert_raises(Release::Refusal) { Release.new(root:).add_engines(release, from) }

      assert_match(/SHA256SUMS/, error.message)
      assert_equal (GEMS + ["SHA256SUMS"]).sort, Dir.children(release).sort
    end
  end

  def test_pin_engines_takes_a_releases_sha256sums_and_pins_only_its_engines
    in_tree do |root|
      Release.new(root:).pin_engines("v0.4.0", release_sums)

      pin = Lota::PhoneEngine.pin(File.read(File.join(root, "ext/lota/phone/engines.txt")))

      assert_equal "v0.4.0", pin.release
      assert_equal ASSETS.sort, pin.sums.keys.sort
    end
  end

  def test_pin_published_engines_pins_a_release_the_pin_does_not_name
    in_tree do |root|
      write(root, "ext/lota/phone/engines.txt", Lota::PhoneEngine.pin_text("v0.3.0", sums))

      assert Release.new(root:).pin_published_engines("v0.4.0", release_sums)

      assert_equal "v0.4.0", Lota::PhoneEngine.pin(File.read(File.join(root, "ext/lota/phone/engines.txt"))).release
    end
  end

  def test_pin_published_engines_leaves_a_pin_that_names_the_release_already
    in_tree do |root|
      pinned = write(root, "ext/lota/phone/engines.txt", Lota::PhoneEngine.pin_text("v0.4.0", sums))
      File.write(pinned, "#{File.read(pinned)}\n")

      refute Release.new(root:).pin_published_engines("v0.4.0", release_sums)

      assert_equal "#{Lota::PhoneEngine.pin_text('v0.4.0', sums)}\n", File.read(pinned)
    end
  end

  def test_pin_published_engines_pins_nothing_for_a_release_that_published_no_engines
    in_tree do |root|
      refute Release.new(root:).pin_published_engines("v0.4.0", "#{'a' * 64}  #{GEMS.first}\n")

      refute_path_exists File.join(root, "ext/lota/phone/engines.txt")
    end
  end

  def test_pin_engines_writes_the_release_and_each_engines_checksum_where_the_gem_reads_them
    in_tree do |root|
      Release.new(root:).pin_engines("v0.4.0", sums)

      pin = Lota::PhoneEngine.pin(File.read(File.join(root, "ext/lota/phone/engines.txt")))

      assert_equal "v0.4.0", pin.release
      assert_equal ASSETS.each_with_index.to_h { |asset, index| [asset, index.to_s * 64] }, pin.sums
    end
  end

  def test_pin_engines_refuses_sums_that_leave_out_an_engine_and_writes_nothing
    in_tree do |root|
      error = assert_raises(Release::Refusal) { Release.new(root:).pin_engines("v0.4.0", sums(ASSETS.drop(1))) }

      assert_match(/lacks #{Regexp.escape(ASSETS.first)}/, error.message)
      refute_path_exists File.join(root, "ext/lota/phone/engines.txt")
    end
  end

  def test_pin_engines_refuses_an_engine_lota_does_not_build
    in_tree do |root|
      error = assert_raises(Release::Refusal) do
        Release.new(root:).pin_engines("v0.4.0", sums + "#{'f' * 64}  lota-engine-android-armeabi-v7a.tar.gz\n")
      end

      assert_match(/lota-engine-android-armeabi-v7a\.tar\.gz/, error.message)
    end
  end

  def test_pin_engines_refuses_what_is_not_a_release_tag_or_not_a_sha256sums
    in_tree do |root|
      %w[0.4.0 v0.4 v0.0.1.dev].each do |tag|
        assert_raises(Release::Refusal, tag) { Release.new(root:).pin_engines(tag, sums) }
      end
      assert_raises(Release::Refusal) { Release.new(root:).pin_engines("v0.4.0", "not a checksum\n") }
      refute_path_exists File.join(root, "ext/lota/phone/engines.txt")
    end
  end
end
