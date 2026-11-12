# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "licensing"
require_relative "linux_build"
require_relative "windows_build"
require_relative "source_archive"
require_relative "source_cache"

namespace :sources do
  desc "Download the source archives the precompiled gem carries (ext/lota/licenses.rb) into vendor/sources, " \
    "and on Linux and Windows what LÖVE's dependencies build from"
  task :fetch do
    licensing = Licensing.load("ext/lota/licenses.rb")
    sources = licensing.frameworks.each_value.filter_map(&:source).uniq
    fetch = lambda do |root|
      sources.each do |source|
        SourceArchive.new(source, root:).fetch
        puts "✅ #{source.path} is #{source.url}, SHA-256 #{source.sha256}"
      rescue SourceArchive::Failure => e
        abort "❌ #{e.message}"
      end
      # tasks/engine.rake
      if ENGINE_PLATFORM == "linux"
        LinuxBuild.new(makefile: LINUX_BUILD.makefile, sources: File.join(root, LINUX_SOURCES), root: "tmp/dependencies")
          .fetch
      end
    end
    # On Linux and macOS every checkout shares one cache of the downloads
    # (tasks/source_cache.rb); Windows fetches into the checkout.
    if ENGINE_PLATFORM == "windows"
      fetch.call(Dir.pwd)
      WINDOWS_BUILD.fetch
    else
      paths = sources.map(&:path) + ((ENGINE_PLATFORM == "linux") ? [LINUX_SOURCES] : [])
      SourceCache.new(checkout: Dir.pwd, cache: SourceCache.folder(ENV)).share(paths, &fetch)
    end
  rescue LinuxBuild::Failure, WindowsBuild::Failure => e
    abort "❌ #{e.message}"
  end
end
