# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/release"
require "date"
require "digest"
require "open3"
require "rubygems/package"

# Release reads what a release needs from the commits and tags of a real
# git repository, stamps a version into a working tree, records dated
# sections, and assembles real gems built by RubyGems.
class ReleaseTest < Minitest::Test
  include TreeHelper

  # Bundler's `release` task tags, pushes, and pushes the gem to RubyGems.
  # Only a dry run (-n), which runs nothing, may ask rake for it here.
  def test_bundlers_release_task_that_would_publish_to_rubygems_is_not_run
    out, status = Open3.capture2e("bundle", "exec", "rake", "-n", "release", chdir: File.expand_path("../..", __dir__))

    assert_predicate status, :success?, out
    assert_includes out, "Execute (dry run) release"
    refute_match(/rubygem_push|source_control_push|guard_clean|Invoke build/, out)
  end

  VERSION_RB = <<~RUBY
    module Lota
      # The gem's version, following Semantic Versioning.
      VERSION = "0.0.1.dev"
    end
  RUBY

  # CHANGELOG.md as it stood at an old release commit: [Unreleased] empty,
  # the release's own dated section below it.
  CHANGELOG = <<~MARKDOWN
    # Changelog

    ## [Unreleased]

    ## [0.1.0] - 2026-11-03

    ### Added

    - A precompiled gem.
  MARKDOWN

  LOCKFILE = <<~LOCK
    PATH
      remote: .
      specs:
        lota (0.0.1.dev)

    DEPENDENCIES
      lota!

    CHECKSUMS
      lota (0.0.1.dev)
      lotab (0.0.1.dev)
  LOCK

  TOOLS = %(# A comment naming ruby = "0.0.1"\n[tools]\nruby = "4.0.7"\nrust = "1.99.1"\n)

  GIT = %w[git -c user.name=Test -c user.email=test@example.com].freeze

  # A repository on trunk with the files committed and the old release
  # tagged v0.1.0, with git's background maintenance off: a commit starts
  # it, and it makes and removes files under .git while in_tree removes the
  # directory, which failed on CI with ENOENT on objects/maintenance.lock.
  def repository(root)
    write(root, "lib/lota/version.rb", VERSION_RB)
    write(root, "CHANGELOG.md", CHANGELOG)
    write(root, "Gemfile.lock", LOCKFILE)
    write(root, "mise.toml", TOOLS)
    run!(root, "git", "init", "--quiet", "--initial-branch=trunk")
    run!(root, "git", "config", "maintenance.auto", "false")
    run!(root, "git", "config", "gc.auto", "0")
    commit(root, "chore: release 0.1.0")
    tag(root, "v0.1.0")
  end

  # Commits every change, and returns the commit.
  def commit(root, message)
    run!(root, "git", "add", "--all")
    run!(root, *GIT, "commit", "--quiet", "--allow-empty", "-m", message)
    run!(root, "git", "rev-parse", "HEAD").chomp
  end

  # Tags HEAD as the release job does, with an annotated tag made at +date+.
  def tag(root, name, date: "2026-11-12T23:30:00Z")
    _, status = Open3.capture2e({ "GIT_COMMITTER_DATE" => date }, *GIT, "tag", "--annotate", name, "-m", "Lota #{name}", chdir: root)
    assert_predicate status, :success?
  end

  # [Unreleased] listing +entries+, above the old release's section.
  def unreleased(*entries)
    CHANGELOG.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Added\n\n#{entries.map { |entry| "- #{entry}\n" }.join}")
  end

  def test_a_repository_built_for_a_test_runs_no_background_git_maintenance
    in_tree do |root|
      repository(root)

      assert_equal "false", run!(root, "git", "config", "--get", "maintenance.auto").strip
      assert_equal "0", run!(root, "git", "config", "--get", "gc.auto").strip
    end
  end

  def test_stamp_sets_the_version_in_the_version_file_and_the_lockfile_and_commits_nothing
    in_tree do |root|
      repository(root)
      Release.new(root:).stamp("0.2.0")

      assert_equal VERSION_RB.sub("0.0.1.dev", "0.2.0"), File.read(File.join(root, "lib/lota/version.rb"))
      assert_equal LOCKFILE.gsub("lota (0.0.1.dev)", "lota (0.2.0)"), File.read(File.join(root, "Gemfile.lock"))
      assert_equal "0.2.0", Release.new(root:).version
      assert_equal ["M Gemfile.lock", "M lib/lota/version.rb"], run!(root, "git", "status", "--porcelain").lines.map(&:strip).sort
    end
  end

  # A Windows checkout with core.autocrlf on, as CI's fuse jobs have, has
  # CRLF line endings, which the stamp keeps.
  def test_stamp_reads_and_keeps_crlf_line_endings
    in_tree do |root|
      repository(root)
      write(root, "lib/lota/version.rb", VERSION_RB.gsub("\n", "\r\n"))
      write(root, "Gemfile.lock", LOCKFILE.gsub("\n", "\r\n"))
      Release.new(root:).stamp("0.2.0")

      assert_equal VERSION_RB.sub("0.0.1.dev", "0.2.0").gsub("\n", "\r\n"), File.binread(File.join(root, "lib/lota/version.rb"))
      assert_equal LOCKFILE.gsub("lota (0.0.1.dev)", "lota (0.2.0)").gsub("\n", "\r\n"), File.binread(File.join(root, "Gemfile.lock"))
    end
  end

  def test_stamp_refuses_what_is_not_a_version_and_changes_nothing
    in_tree do |root|
      repository(root)

      %w[0.2 0.2.0.pre.1 v0.2.0].each do |number|
        assert_raises(Release::Refusal, number) { Release.new(root:).stamp(number) }
      end
      assert_empty run!(root, "git", "status", "--porcelain")
    end
  end

  def test_tags_are_the_release_tags_by_version_and_tagged_is_the_commit_one_names
    in_tree do |root|
      repository(root)
      commit(root, "feat: more")
      tag(root, "v0.10.0")
      tag(root, "v0.2.0")
      run!(root, "git", "tag", "other")
      run!(root, "git", "tag", "v1.0.0-rc1")
      release = Release.new(root:)

      assert_equal %w[v0.1.0 v0.2.0 v0.10.0], release.tags
      assert_equal run!(root, "git", "rev-parse", "HEAD").chomp, release.tagged("v0.2.0")
      assert_nil release.tagged("v9.9.9")
    end
  end

  def test_covering_is_the_release_tags_on_a_commit_or_after_it
    in_tree do |root|
      repository(root)
      picked = commit(root, "feat: picked")
      commit(root, "feat: later")
      tag(root, "v0.2.0")
      release = Release.new(root:)

      assert_equal ["v0.2.0"], release.covering(picked)
      assert_equal %w[v0.1.0 v0.2.0], release.covering(release.tagged("v0.1.0"))
      write(root, "new.txt", "x")
      assert_empty release.covering(commit(root, "feat: newer"))
    end
  end

  def test_previous_is_the_newest_release_before_a_commit_not_one_on_it
    in_tree do |root|
      repository(root)
      tagged = commit(root, "feat: released")
      tag(root, "v0.2.0")
      release = Release.new(root:)

      assert_equal "v0.1.0", release.previous(tagged)
      assert_equal "v0.2.0", release.previous(commit(root, "feat: after"))
    end
  end

  # The commit a release picks may come before the last release's dated
  # section reached trunk, so its [Unreleased] still lists that release.
  def test_added_is_what_unreleased_lists_that_the_release_before_did_not
    in_tree do |root|
      repository(root)
      write(root, "CHANGELOG.md", unreleased("First."))
      commit(root, "feat: first")
      tag(root, "v0.1.1")
      write(root, "CHANGELOG.md", unreleased("First.", "Second."))
      before_recording = commit(root, "feat: second")
      release = Release.new(root:)

      assert_equal [Changelog::Entry.new("### Added", "- Second.")], release.added(before_recording)
      assert_equal "### Added\n\n- Second.\n", release.notes(before_recording)
      assert_equal [Changelog::Entry.new("### Added", "- First.")], release.added("v0.1.1")
    end
  end

  def test_notes_refuse_a_commit_that_adds_nothing
    in_tree do |root|
      repository(root)
      empty = commit(root, "docs: nothing to note")

      error = assert_raises(Release::Refusal) { Release.new(root:).notes(empty) }
      assert_match(/lists nothing new since v0\.1\.0/, error.message)
    end
  end

  def test_ruby_is_the_first_ruby_line_of_mise_toml_at_a_commit
    in_tree do |root|
      repository(root)

      assert_equal "4.0.7", Release.new(root:).ruby("HEAD")
    end
  end

  def test_date_is_the_day_the_tag_was_made_in_utc
    in_tree do |root|
      repository(root)

      assert_equal Date.new(2026, 11, 12), Release.new(root:).date("v0.1.0")
    end
  end

  # Two releases tagged before either dated section reached trunk: the
  # record writes both, each with what it added, and leaves what came
  # after them in [Unreleased].
  def test_record_writes_a_section_for_each_tag_without_one_and_moves_its_entries
    in_tree do |root|
      repository(root)
      write(root, "CHANGELOG.md", unreleased("First."))
      commit(root, "feat: first")
      tag(root, "v0.1.1", date: "2026-11-12T10:00:00Z")
      write(root, "CHANGELOG.md", unreleased("First.", "Second."))
      commit(root, "feat: second")
      tag(root, "v0.1.2", date: "2026-11-13T10:00:00Z")
      write(root, "CHANGELOG.md", unreleased("First.", "Second.", "Third."))
      commit(root, "feat: third")
      text, recorded = Release.new(root:).record

      assert_equal %w[0.1.1 0.1.2], recorded
      assert_equal <<~MARKDOWN, text
        # Changelog

        ## [Unreleased]

        ### Added

        - Third.

        ## [0.1.2] - 2026-11-13

        ### Added

        - Second.

        ## [0.1.1] - 2026-11-12

        ### Added

        - First.

        ## [0.1.0] - 2026-11-03

        ### Added

        - A precompiled gem.
      MARKDOWN
      write(root, "CHANGELOG.md", text)
      assert_equal [text, []], Release.new(root:).record
      assert_empty Release.new(root:).check_changelog
    end
  end

  def test_check_changelog_names_a_missing_section_and_one_that_lists_other_entries
    in_tree do |root|
      repository(root)
      write(root, "CHANGELOG.md", unreleased("First."))
      commit(root, "feat: first")
      tag(root, "v0.1.1")
      release = Release.new(root:)

      assert_equal ["CHANGELOG.md has no section for 0.1.1, which v0.1.1 released"], release.check_changelog
      write(root, "CHANGELOG.md", "## [Unreleased]\n\n## [0.1.1] - 2026-11-12\n\n- Other.\n\n## [0.1.0] - 2026-11-03\n\n### Added\n\n- Changed.\n")
      assert_equal [
        "CHANGELOG.md's section for 0.1.0 lists other than v0.1.0 released",
        "CHANGELOG.md's section for 0.1.1 lists other than v0.1.1 released",
      ], release.check_changelog
    end
  end

  def test_export_writes_the_files_under_a_path_as_a_commit_has_them
    in_tree do |root|
      repository(root)
      write(root, "lib/lota/version.rb", "changed since\n")
      out = File.join(root, "out")
      Release.new(root:).export("HEAD", "lib", out)

      assert_equal ["lib/lota/version.rb"], Dir.glob("**/*", base: out).select { |path| File.file?(File.join(out, path)) }
      assert_equal VERSION_RB, File.read(File.join(out, "lib/lota/version.rb"))
    end
  end

  # A real gem of +name+, +version+, and +platform+, built into +dir+, and
  # the .sha256 file its delivery writes beside it.
  def gem(dir, platform, version: "0.2.0", name: "lota", sha256: nil)
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.platform = platform
      s.summary = "A test gem."
      s.authors = ["Test"]
      s.files = []
    end
    target = "lota-0.2.0-#{platform}.gem"
    Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
      Gem::Package.build(spec, true, false, File.join(dir, target))
    end
    File.write(File.join(dir, "#{target}.sha256"), "#{sha256 || Digest::SHA256.file(File.join(dir, target)).hexdigest}  #{target}\n")
    target
  end

  PLATFORMS = %w[arm64-darwin x86_64-linux-gnu].freeze

  def test_assemble_replaces_each_gems_checksum_with_one_sha256sums_for_them_all
    in_tree do |root|
      dir = File.join(root, "release")
      Dir.mkdir(dir)
      gems = PLATFORMS.map { |platform| gem(dir, platform) }

      assert_equal gems, Release.new(root:).assemble(dir, "0.2.0", PLATFORMS)
      assert_equal (gems + ["SHA256SUMS"]).sort, Dir.children(dir).sort
      assert_equal gems.sort.map { |g| "#{Digest::SHA256.file(File.join(dir, g)).hexdigest}  #{g}\n" }.join,
        File.read(File.join(dir, "SHA256SUMS"))
    end
  end

  def test_assemble_refuses_a_missing_platform_and_an_unexpected_file
    in_tree do |root|
      dir = File.join(root, "release")
      Dir.mkdir(dir)
      gem(dir, "arm64-darwin")
      write(dir, "stray.gem")

      error = assert_raises(Release::Refusal) { Release.new(root:).assemble(dir, "0.2.0", PLATFORMS) }
      assert_match(/missing lota-0\.2\.0-x86_64-linux-gnu\.gem, lota-0\.2\.0-x86_64-linux-gnu\.gem\.sha256; unexpected stray\.gem\z/, error.message)
    end
  end

  def test_assemble_refuses_a_gem_whose_bytes_are_not_the_ones_delivery_verified
    in_tree do |root|
      dir = File.join(root, "release")
      Dir.mkdir(dir)
      gem(dir, "arm64-darwin", sha256: "0" * 64)

      error = assert_raises(Release::Refusal) { Release.new(root:).assemble(dir, "0.2.0", ["arm64-darwin"]) }
      assert_match(/has SHA-256 \h{64}, not the 0{64} its delivery verified/, error.message)
      refute_path_exists File.join(dir, "SHA256SUMS")
    end
  end

  # A gem built before the version was stamped carries the clone's
  # version, not the release's.
  def test_assemble_refuses_a_gem_whose_specification_is_not_the_one_its_name_says
    in_tree do |root|
      dir = File.join(root, "release")
      Dir.mkdir(dir)
      gem(dir, "arm64-darwin", version: "0.0.1.dev")

      error = assert_raises(Release::Refusal) { Release.new(root:).assemble(dir, "0.2.0", ["arm64-darwin"]) }
      assert_equal "lota-0.2.0-arm64-darwin.gem holds lota 0.0.1.dev arm64-darwin, not lota 0.2.0 arm64-darwin", error.message
    end
  end
end
