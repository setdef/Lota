# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/release"
require_relative "../../tasks/player_app"

# A release publishes Lota's app and the fuser for each desktop beside its
# gems, as a LÖVE release publishes LÖVE's app, from the artifacts
# fuse.yml keeps of what its run built, player-PLATFORM and
# fuser-PLATFORM, with their checksums in its one SHA256SUMS
# (Release#add_apps).
class ReleaseAppsTest < Minitest::Test
  include TreeHelper

  PLATFORMS = %w[arm64-darwin x86_64-linux-gnu aarch64-linux-gnu x64-mingw-ucrt aarch64-mingw-ucrt].freeze

  # The gems a release's SHA256SUMS lists before the apps join it.
  GEMS = %w[lota-0.4.0-arm64-darwin.gem lota-0.4.0-x86_64-linux-gnu.gem].freeze

  # What Fledge writes for each platform's app named +name+: its archive
  # and its installer, as fuse.yml uploads them.
  def files(name, platform)
    {
      "arm64-darwin" => ["#{name}-arm64-darwin.tar.gz", "#{name}-arm64-darwin.dmg"],
      "x86_64-linux-gnu" => ["#{name}-x86_64-linux.tar.gz", "#{name}-x86_64-linux.AppImage"],
      "aarch64-linux-gnu" => ["#{name}-aarch64-linux.tar.gz", "#{name}-aarch64-linux.AppImage"],
      "x64-mingw-ucrt" => ["#{name}-x64-mingw-ucrt.zip", "#{name}-x64-mingw-ucrt-setup.exe"],
      "aarch64-mingw-ucrt" => ["#{name}-aarch64-mingw-ucrt.zip", "#{name}-aarch64-mingw-ucrt-setup.exe"],
    }.fetch(platform)
  end

  # The folder the release job downloads the artifacts into, one folder
  # for each, as download-artifact leaves them without merge-multiple:
  # each app's files holding their own names, beside the lockfile of the
  # project it was built from. +skip+ leaves a file out.
  def artifacts(root, skip: nil)
    { "player" => PlayerApp::NAME, "fuser" => "Lota Fuser" }.each do |kind, name|
      PLATFORMS.each do |platform|
        folder = "apps/#{kind}-#{platform}"
        files(name, platform).each { |file| write(root, "#{folder}/#{file}", file) unless file == skip }
        write(root, "#{folder}/fuse-project/Gemfile.lock", "GEM\n")
      end
    end
    File.join(root, "apps")
  end

  # The folder Release#assemble leaves: two gems and their SHA256SUMS.
  def assembled(root)
    GEMS.each { |gem| write(root, "release/#{gem}", gem) }
    write(root, "release/SHA256SUMS", GEMS.map { |gem| "#{Digest::SHA256.hexdigest(gem)}  #{gem}\n" }.join)
    File.join(root, "release")
  end

  # Each file the release carries for the apps, by the name it publishes
  # it under, with the file it is.
  def published
    [PlayerApp::NAME, "Lota Fuser"].flat_map do |name|
      PLATFORMS.flat_map { |platform| files(name, platform) }
    end.to_h { |file| [file.tr(" ", "."), file] }
  end

  def test_add_apps_puts_each_platforms_app_and_fuser_beside_the_gems_and_their_checksums_in_their_sha256sums
    in_tree do |root|
      release = assembled(root)

      added = Release.new(root:).add_apps(release, artifacts(root), PLATFORMS)

      assert_equal published.keys.sort, added.sort
      assert_equal 20, added.size
      assert_equal (GEMS + published.keys + ["SHA256SUMS"]).sort, Dir.children(release).sort
      published.each { |asset, file| assert_equal file, File.read(File.join(release, asset)) }
      sums = GEMS.to_h { |gem| [gem, gem] }.merge(published).sort.map { |asset, file| "#{Digest::SHA256.hexdigest(file)}  #{asset}\n" }
      assert_equal sums.join, File.read(File.join(release, "SHA256SUMS"))
    end
  end

  # GitHub stores an asset whose name has a space under another name, so
  # the release names the fuser's files without one, and its SHA256SUMS
  # lists each by the name a person downloads it as.
  def test_add_apps_names_no_file_with_a_space
    in_tree do |root|
      added = Release.new(root:).add_apps(assembled(root), artifacts(root), PLATFORMS)

      assert_includes added, "Lota.Fuser-x64-mingw-ucrt-setup.exe"
      assert_includes added, "Lota-arm64-darwin.dmg"
      assert(added.all? { |name| name.match?(/\A[A-Za-z0-9._-]+\z/) }, added.inspect)
    end
  end

  def test_add_apps_refuses_an_artifact_without_its_installer_and_adds_nothing
    in_tree do |root|
      release = assembled(root)
      before = File.read(File.join(release, "SHA256SUMS"))

      error = assert_raises(Release::Refusal) do
        Release.new(root:).add_apps(release, artifacts(root, skip: "Lota Fuser-x86_64-linux.AppImage"), PLATFORMS)
      end

      assert_match(/fuser-x86_64-linux-gnu .*missing Lota Fuser-x86_64-linux\.AppImage/, error.message)
      assert_equal (GEMS + ["SHA256SUMS"]).sort, Dir.children(release).sort
      assert_equal before, File.read(File.join(release, "SHA256SUMS"))
    end
  end

  def test_add_apps_refuses_a_platform_whose_artifact_is_missing
    in_tree do |root|
      from = artifacts(root)
      FileUtils.rm_rf(File.join(from, "player-aarch64-mingw-ucrt"))

      error = assert_raises(Release::Refusal) { Release.new(root:).add_apps(assembled(root), from, PLATFORMS) }

      assert_match(/no artifact player-aarch64-mingw-ucrt/, error.message)
    end
  end

  # A file the release does not know, such as a .deb a change to the app
  # made Fledge write, would otherwise be left out unseen.
  def test_add_apps_refuses_a_file_it_does_not_expect
    in_tree do |root|
      from = artifacts(root)
      write(root, "apps/player-x86_64-linux-gnu/Lota-x86_64-linux.deb", "deb")

      error = assert_raises(Release::Refusal) { Release.new(root:).add_apps(assembled(root), from, PLATFORMS) }

      assert_match(/unexpected Lota-x86_64-linux\.deb/, error.message)
    end
  end

  def test_add_apps_refuses_a_platform_lota_builds_no_app_for
    in_tree do |root|
      error = assert_raises(Release::Refusal) do
        Release.new(root:).add_apps(assembled(root), artifacts(root), PLATFORMS + ["x86_64-linux-musl"])
      end

      assert_match(/x86_64-linux-musl/, error.message)
    end
  end

  def test_add_apps_refuses_a_file_the_release_holds_already
    in_tree do |root|
      release = assembled(root)
      write(root, "release/Lota-arm64-darwin.dmg", "an older one")

      error = assert_raises(Release::Refusal) { Release.new(root:).add_apps(release, artifacts(root), PLATFORMS) }

      assert_match(/already holds Lota-arm64-darwin\.dmg/, error.message)
      assert_equal "an older one", File.read(File.join(release, "Lota-arm64-darwin.dmg"))
    end
  end

  # The names the release expects are the apps' own; FuserApp loads Lota's
  # extension, so its test checks the fuser's.
  def test_the_apps_are_lotas_app_and_the_fuser
    assert_equal({ "player" => PlayerApp::NAME, "fuser" => "Lota Fuser" }, Release::APPS)
  end
end
