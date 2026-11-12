# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/source_cache"

# SourceCache shares rake sources:fetch's downloads between checkouts, in
# real folders, one fetch at a time.
class SourceCacheTest < Minitest::Test
  include TreeHelper

  ARCHIVE = "vendor/sources/openal-soft.tar.bz2"
  LINUX = "vendor/sources/linux"

  def test_the_folder_follows_xdg_cache_home_or_falls_back_to_the_homes_cache
    assert_equal "/x/lota/sources", SourceCache.folder({ "XDG_CACHE_HOME" => "/x" }, home: "/h")
    assert_equal "/h/.cache/lota/sources", SourceCache.folder({}, home: "/h")
    assert_equal "/h/.cache/lota/sources", SourceCache.folder({ "XDG_CACHE_HOME" => "relative" }, home: "/h")
  end

  def test_a_fetch_goes_into_the_cache_and_the_checkout_gets_its_files
    in_tree do |dir|
      checkout = File.join(dir, "checkout")
      cache = File.join(dir, "cache")

      SourceCache.new(checkout:, cache:).share([ARCHIVE, LINUX]) do |root|
        write(root, ARCHIVE, "archive")
        write(root, "#{LINUX}/stamp", "stamp")
        write(root, "#{LINUX}/SDL/README", "sdl")
      end

      assert_equal "archive", File.read(File.join(checkout, ARCHIVE))
      assert File.identical?(File.join(cache, ARCHIVE), File.join(checkout, ARCHIVE))
      assert_equal "sdl", File.read(File.join(checkout, LINUX, "SDL/README"))
    end
  end

  def test_a_later_fetch_into_the_cache_leaves_another_checkouts_files_alone
    in_tree do |dir|
      cache = File.join(dir, "cache")
      first = File.join(dir, "first")
      SourceCache.new(checkout: first, cache:).share([ARCHIVE]) { |root| write(root, ARCHIVE, "old") }

      SourceCache.new(checkout: File.join(dir, "second"), cache:).share([ARCHIVE]) do |root|
        path = File.join(root, ARCHIVE)
        File.write("#{path}.part", "new")
        File.rename("#{path}.part", path)
      end

      assert_equal "old", File.read(File.join(first, ARCHIVE))
      assert_equal "new", File.read(File.join(dir, "second", ARCHIVE))
    end
  end

  def test_what_the_checkout_already_has_seeds_the_cache_before_the_fetch
    in_tree do |dir|
      checkout = File.join(dir, "checkout")
      write(checkout, "#{LINUX}/stamp", "restored")
      seen = nil

      SourceCache.new(checkout:, cache: File.join(dir, "cache")).share([LINUX]) do |root|
        seen = File.read(File.join(root, LINUX, "stamp"))
      end

      assert_equal "restored", seen
      assert_equal "restored", File.read(File.join(checkout, LINUX, "stamp"))
    end
  end

  def test_one_fetch_at_a_time
    in_tree do |dir|
      cache = File.join(dir, "cache")
      inside = Queue.new
      release = Queue.new
      first = Thread.new do
        SourceCache.new(checkout: File.join(dir, "a"), cache:).share([]) do
          inside << :first
          release.pop
        end
      end
      inside.pop
      second = Thread.new do
        SourceCache.new(checkout: File.join(dir, "b"), cache:).share([]) { inside << :second }
      end

      sleep 0.2
      assert_empty inside, "a second fetch ran while the first held the cache"
      release << :go
      [first, second].each(&:join)
      assert_equal :second, inside.pop
    end
  end
end
