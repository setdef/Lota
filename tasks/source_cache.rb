# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"

# The downloads rake sources:fetch makes, shared by every checkout of Lota
# on a computer: its clones, its worktrees, and checks running at once.
#
# #share fetches into the cache, laid out as a checkout is, while it holds
# the cache's lock, so one fetch runs at a time, then links each fetched
# path into the checkout file by file. A fetch another checkout makes later
# replaces files in the cache, never the checkout's links, so it cannot
# change what this checkout builds from. Before it fetches, a path the
# checkout has and the cache lacks, such as one CI restored from its own
# cache, goes into the cache, so the fetch finds it there and checks it
# rather than downloading it again.
class SourceCache
  # The cache's folder: lota/sources in XDG_CACHE_HOME, or in ~/.cache.
  def self.folder(env, home: Dir.home)
    base = env.fetch("XDG_CACHE_HOME", "")
    base = File.join(home, ".cache") unless base.start_with?("/")
    File.join(base, "lota", "sources")
  end

  # [checkout] The checkout's root.
  # [cache] The cache's folder.
  def initialize(checkout:, cache:)
    @checkout = checkout
    @cache = cache
  end

  # Yields the root to fetch into, holding the cache's lock, then links
  # each of +paths+ (relative to a root) the fetch made from the cache into
  # the checkout.
  def share(paths)
    FileUtils.mkdir_p(@cache)
    File.open(File.join(@cache, ".lock"), File::RDWR | File::CREAT, 0o644) do |lock|
      lock.flock(File::LOCK_EX)
      paths.each { |path| seed(path) }
      yield @cache
      paths.each { |path| link(path) }
    end
  end

  private def seed(path)
    from = File.join(@checkout, path)
    to = File.join(@cache, path)
    copy(from, to) if File.exist?(from) && !File.exist?(to)
  end

  private def link(path)
    from = File.join(@cache, path)
    to = File.join(@checkout, path)
    return unless File.exist?(from)
    return if same?(from, to)

    FileUtils.rm_rf(to)
    copy(from, to)
  end

  # Whether +to+ is already +from+'s link: the same file, or for a
  # folder, holding the same stamp.
  private def same?(from, to)
    return File.identical?(from, to) if File.file?(from)

    stamp = File.join(from, "stamp")
    File.file?(stamp) && File.identical?(stamp, File.join(to, "stamp"))
  end

  # Links +from+ to +to+, file by file, or copies it where the two are on
  # different file systems.
  private def copy(from, to)
    FileUtils.mkdir_p(File.dirname(to))
    FileUtils.cp_lr(from, to)
  rescue Errno::EXDEV, Errno::EPERM, NotImplementedError
    FileUtils.rm_rf(to)
    FileUtils.cp_r(from, to, preserve: true)
  end
end
