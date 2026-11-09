# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tmpdir"
require_relative "release"
require_relative "release_plan"

# Cutting a release (doc/contributors/releasing.md). Bundler's own release
# task, which pushes to RubyGems, is not one of these; publishing to
# RubyGems is the maintainer's alone.

# Runs the block with a Release of this repository, and aborts with its
# refusal, if it refuses. LOTA_RELEASE_BRANCH names another branch to
# prepare on, for CI's rehearsal of an automatic release on a branch.
def release_task
  yield Release.new(root: Dir.pwd, branch: ENV.fetch("LOTA_RELEASE_BRANCH", Release::BRANCH))
rescue Release::Refusal => e
  abort "❌ #{e.message}"
end

# What sig/ removes or changes since +tag+, as ApiDiff finds it.
def api_breaks(release, tag)
  require_relative "api_diff"
  Dir.mktmpdir("lota-api") do |dir|
    release.export(tag, "sig", dir)
    ApiDiff.new(File.join(dir, "sig"), "sig").breaks
  end
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

  desc "Print the version to release next, or nothing, and why on standard error (refuses an API break with no Breaking: entry)"
  task :next do
    release_task do |release|
      version = release.version
      tags = release.tags
      breaks = tags.include?("v#{version}") ? api_breaks(release, "v#{version}") : []
      plan = ReleasePlan.next_release(version:, unreleased: release.unreleased, tags:, breaks:)
      warn plan.reason
      puts plan.version if plan.version
    end
  end

  desc "Print what the release job does for a tag on a commit: tag_and_publish, publish, done, or skip"
  task :plan, [:tag, :sha, :released] do |_task, args|
    release_task do |release|
      tag = args.fetch(:tag)
      puts ReleasePlan.publish(tag:, sha: args.fetch(:sha), tagged: release.tagged(tag), released: args.fetch(:released) == "true",
        unreleased: release.unreleased)
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
