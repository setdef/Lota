# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "release"

# Cutting a release (doc/contributors/releasing.md). Bundler's own release
# task, which pushes to RubyGems, is not one of these; publishing to
# RubyGems is the maintainer's alone.

# Runs the block with a Release of this repository, and aborts with its
# refusal, if it refuses.
def release_task
  yield Release.new(root: Dir.pwd)
rescue Release::Refusal => e
  abort "❌ #{e.message}"
end

namespace :release do
  desc "Set the version and move CHANGELOG.md's [Unreleased] under it, dated today (on a clean trunk)"
  task :prepare, [:version] do |_task, args|
    number = args[:version] or abort "❌ name the version: bundle exec rake release:prepare[0.1.0]"
    release_task do |release|
      release.prepare(number)
      puts "✅ Prepared #{number}: review the diff, run bundle exec rake, commit, then tag v#{number}"
    end
  end

  desc "Check a release tag (by default v and lib/lota/version.rb's version) against the version and CHANGELOG.md"
  task :check, [:tag] do |_task, args|
    release_task do |release|
      tag = args[:tag] || "v#{release.version}"
      puts "✅ #{tag} releases #{release.check(tag)}"
    end
  end

  desc "Write a version's CHANGELOG.md section, the release's notes, to a file"
  task :notes, [:version, :file] do |_task, args|
    release_task { |release| File.write(args.fetch(:file), release.notes(args.fetch(:version))) }
  end

  desc "Check a directory holds one verified gem for each platform given, and write its SHA256SUMS"
  task :assemble, [:dir] do |_task, args|
    release_task do |release|
      gems = release.assemble(args.fetch(:dir), args.extras)
      puts "✅ Assembled #{gems.join(', ')}, and #{Release::CHECKSUMS}"
    end
  end
end

# Bundler's gem_tasks, which the Rakefile requires, also defines `release`,
# which builds the gem, tags the commit, pushes it, and pushes the gem to
# RubyGems. Lota is released by tagging (doc/contributors/releasing.md), and
# publishing to RubyGems is the maintainer's alone, so `release` and the
# tasks it runs refuse here, where `rake -T` shows them beside the real ones.
BUNDLER_RELEASE_TASKS = %w[release release:guard_clean release:source_control_push release:rubygem_push].freeze
BUNDLER_RELEASE_TASKS.each { |name| Rake::Task[name].clear if Rake::Task.task_defined?(name) }

desc "Refused: cut a release with release:prepare and a tag (doc/contributors/releasing.md)"
task :release do
  abort "❌ rake release would push to RubyGems, which only the maintainer does. " \
    "Prepare with release:prepare, then tag; see doc/contributors/releasing.md"
end
