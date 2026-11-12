# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tmpdir"
require_relative "release"
require_relative "release_plan"

# Releasing (doc/contributors/releasing.md): CI's release job runs these,
# and anyone may run them to see what it would do. Bundler's own release
# task, which pushes to RubyGems, is not one of these; publishing to
# RubyGems is the maintainer's alone.

# Runs the block with a Release of this repository, and aborts with its
# refusal, if it refuses.
def release_task
  yield Release.new(root: Dir.pwd)
rescue Release::Refusal, Changelog::Malformed => e
  abort "❌ #{e.message}"
end

# What sig/ removes or changes at +sha+ since +tag+, as ApiDiff finds it.
def api_breaks(release, tag, sha)
  require_relative "api_diff"
  Dir.mktmpdir("lota-api") do |dir|
    release.export(tag, "sig", File.join(dir, "old"))
    release.export(sha, "sig", File.join(dir, "new"))
    ApiDiff.new(File.join(dir, "old", "sig"), File.join(dir, "new", "sig")).breaks
  end
end

# What #decide and #check_tag take, read from the repository at +sha+.
def release_facts(release, sha)
  previous = release.previous(sha)
  entries = release.added(sha)
  breaks = (previous && !entries.empty?) ? api_breaks(release, previous, sha) : []
  { previous: previous&.delete_prefix("v"), entries:, breaks:, ruby: release.ruby(sha) }
end

# The version +sha+ releases as, and why, when CI picks it on its own.
def release_decision(release, sha)
  ReleasePlan.decide(covering: release.covering(sha), **release_facts(release, sha))
end

namespace :release do
  desc "Print the version a commit (HEAD) would release as, or nothing, and why on standard error; " \
    "with a tag, check it as a release of its commit (refuses an API break with no Breaking: entry)"
  task :version, [:sha, :tag] do |_task, args|
    release_task do |release|
      sha = release.commit(args[:sha].to_s.empty? ? "HEAD" : args[:sha])
      tag = args[:tag].to_s
      if tag.empty?
        decision = release_decision(release, sha)
        warn decision.reason
        puts decision.version if decision.version
      else
        warn "#{tag} releases #{sha}"
        puts ReleasePlan.check_tag(tag:, **release_facts(release, sha))
      end
    end
  end

  desc "Print the version HEAD would release as next, or nothing, and why on standard error"
  task next: :version

  desc "Print what the release job does for a commit whose gems carry a version: tag_and_publish, publish, done, or skip"
  task :plan, [:sha, :version, :released] do |_task, args|
    release_task do |release|
      sha = release.commit(args.fetch(:sha))
      built = args[:version].to_s.empty? ? nil : args[:version]
      tagged = built && release.tagged("v#{built}")
      action = ReleasePlan.publish(built:, sha:, tagged:, released: args[:released] == "true",
        decision: tagged ? nil : release_decision(release, sha))
      warn action.reason
      puts action.name
    end
  end

  desc "Write a commit's release notes, what its [Unreleased] adds since the release before it, to a file"
  task :notes, [:sha, :file] do |_task, args|
    release_task { |release| File.write(args.fetch(:file), release.notes(release.commit(args.fetch(:sha)))) }
  end

  desc "Set a version in lib/lota/version.rb and Gemfile.lock, as a release's gems are built (commits nothing)"
  task :stamp, [:version] do |_task, args|
    release_task do |release|
      release.stamp(args.fetch(:version))
      puts "✅ Stamped #{args.fetch(:version)}"
    end
  end

  desc "Check a directory holds one verified gem of a version for each platform given, and write its SHA256SUMS"
  task :assemble, [:dir, :version] do |_task, args|
    release_task do |release|
      gems = release.assemble(args.fetch(:dir), args.fetch(:version), args.extras)
      puts "✅ Assembled #{gems.join(', ')}, and #{Release::CHECKSUMS}"
    end
  end
end

namespace :changelog do
  desc "Write a dated section into CHANGELOG.md for each release tag it lacks, moving that release's entries out of [Unreleased]"
  task :record do
    release_task do |release|
      text, recorded = release.record
      File.write(Release::CHANGELOG, text)
      puts recorded.empty? ? "✅ #{Release::CHANGELOG} has a section for every release tag" : "✅ Recorded #{recorded.join(', ')}"
    end
  end

  desc "Check CHANGELOG.md has a dated section for each release tag, listing what that release added"
  task :check do
    release_task do |release|
      problems = release.check_changelog
      abort "❌ #{problems.join("\n❌ ")}" unless problems.empty?
      puts "✅ #{Release::CHANGELOG} has the section each of #{release.tags.size} release tags released"
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

desc "Refused: CI releases the commits it proves, or you push a tag (doc/contributors/releasing.md)"
task :release do
  abort "❌ rake release would push to RubyGems, which only the maintainer does. " \
    "CI releases a commit it proves, or you push a release tag; see doc/contributors/releasing.md"
end
