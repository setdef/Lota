# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "licensing"
require_relative "source_archive"

namespace :sources do
  desc "Download the source archives the precompiled gem carries (ext/lota/licenses.rb) into vendor/sources"
  task :fetch do
    licensing = Licensing.load("ext/lota/licenses.rb")
    licensing.frameworks.each_value.filter_map(&:source).each do |source|
      SourceArchive.new(source, root: Dir.pwd).fetch
      puts "✅ #{source.path} is #{source.url}, SHA-256 #{source.sha256}"
    rescue SourceArchive::Failure => e
      abort "❌ #{e.message}"
    end
  end
end
