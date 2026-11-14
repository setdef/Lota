# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/release"

# A release pins the phone engines it publishes in the gems it builds, as
# it stamps its version: Release#pin_engines writes ext/lota/phone/engines.txt
# into the working tree from the engines' SHA256SUMS, and commits nothing.
class ReleaseEnginesTest < Minitest::Test
  include TreeHelper

  ASSETS = Lota::PhoneEngine::TARGETS.map { |target| Lota::PhoneEngine.asset(target) }

  # SHA256SUMS of the four engines, as phone-engine.yml writes it, each
  # bundle's checksum a different digit repeated.
  def sums(assets = ASSETS)
    assets.each_with_index.map { |asset, index| "#{index.to_s * 64}  #{asset}\n" }.join
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
