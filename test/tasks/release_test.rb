# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/release"
require "date"
require "digest"
require "open3"
require "rubygems/package"

# Release prepares a version in a real git repository of the three files
# it edits, and assembles real gems built by RubyGems.
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
      VERSION = "0.0.0"
    end
  RUBY

  CHANGELOG = <<~MARKDOWN
    # Changelog

    ## [Unreleased]

    ### Added

    - A precompiled gem.
  MARKDOWN

  LOCKFILE = <<~LOCK
    PATH
      remote: .
      specs:
        lota (0.0.0)

    DEPENDENCIES
      lota!

    CHECKSUMS
      lota (0.0.0)
      lotab (0.0.0)
  LOCK

  DATE = Date.new(2026, 11, 3)

  # A repository on +branch+ with the three files committed.
  def repository(root, branch: "trunk", changelog: CHANGELOG)
    write(root, "lib/lota/version.rb", VERSION_RB)
    write(root, "CHANGELOG.md", changelog)
    write(root, "Gemfile.lock", LOCKFILE)
    run!(root, "git", "init", "--quiet", "--initial-branch=#{branch}")
    run!(root, "git", "add", "--all")
    run!(root, "git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet", "-m", "start")
  end

  def test_prepare_moves_unreleased_under_the_dated_version_and_sets_the_version_everywhere
    in_tree do |root|
      repository(root)
      Release.new(root:).prepare("0.1.0", date: DATE)

      assert_equal <<~MARKDOWN, File.read(File.join(root, "CHANGELOG.md"))
        # Changelog

        ## [Unreleased]

        ## [0.1.0] - 2026-11-03

        ### Added

        - A precompiled gem.
      MARKDOWN
      assert_includes File.read(File.join(root, "lib/lota/version.rb")), %(  VERSION = "0.1.0"\n)
      assert_equal LOCKFILE.gsub("lota (0.0.0)", "lota (0.1.0)"), File.read(File.join(root, "Gemfile.lock"))
      assert_equal "0.1.0", Release.new(root:).version
    end
  end

  def test_a_prepared_release_passes_its_own_check_and_its_notes_are_its_section
    in_tree do |root|
      repository(root)
      release = Release.new(root:)
      release.prepare("0.1.0", date: DATE)

      assert_equal "0.1.0", release.check("v0.1.0")
      assert_equal "### Added\n\n- A precompiled gem.\n", release.notes("0.1.0")
    end
  end

  def test_prepare_refuses_a_tree_with_changes_and_changes_nothing
    in_tree do |root|
      repository(root)
      write(root, "stray.txt", "uncommitted")

      error = assert_raises(Release::Refusal) { Release.new(root:).prepare("0.1.0", date: DATE) }
      assert_match(/changes of its own.*stray\.txt/m, error.message)
      assert_equal CHANGELOG, File.read(File.join(root, "CHANGELOG.md"))
    end
  end

  def test_prepare_refuses_any_branch_but_trunk
    in_tree do |root|
      repository(root, branch: "topic")

      error = assert_raises(Release::Refusal) { Release.new(root:).prepare("0.1.0", date: DATE) }
      assert_equal "releases are cut from trunk, not topic", error.message
    end
  end

  def test_prepare_refuses_a_version_that_is_not_newer_or_not_a_version
    in_tree do |root|
      repository(root)

      assert_raises(Release::Refusal) { Release.new(root:).prepare("0.0.0", date: DATE) }
      assert_raises(Release::Refusal) { Release.new(root:).prepare("0.1", date: DATE) }
      assert_raises(Release::Refusal) { Release.new(root:).prepare("0.1.0.pre.1", date: DATE) }
      assert_includes File.read(File.join(root, "lib/lota/version.rb")), %(VERSION = "0.0.0")
    end
  end

  def test_prepare_refuses_an_empty_unreleased_section
    in_tree do |root|
      repository(root, changelog: "# Changelog\n\n## [Unreleased]\n\n## [0.0.1] - 2026-01-01\n\n- Old.\n")

      error = assert_raises(Release::Refusal) { Release.new(root:).prepare("0.1.0", date: DATE) }
      assert_equal "CHANGELOG.md's ## [Unreleased] section lists no changes", error.message
    end
  end

  def test_check_refuses_a_tag_the_version_file_disagrees_with
    in_tree do |root|
      repository(root)

      error = assert_raises(Release::Refusal) { Release.new(root:).check("v0.1.0") }
      assert_match(%r{v0\.1\.0 names 0\.1\.0, but lib/lota/version\.rb says 0\.0\.0}, error.message)
    end
  end

  def test_check_refuses_a_tag_that_is_not_v_and_three_numbers
    in_tree do |root|
      repository(root)

      %w[0.0.0 v0.0 v0.0.0-rc1 version0.0.0].each do |tag|
        assert_raises(Release::Refusal, tag) { Release.new(root:).check(tag) }
      end
    end
  end

  def test_check_refuses_a_version_whose_changelog_section_is_missing_or_undated
    in_tree do |root|
      repository(root, changelog: "## [Unreleased]\n\n- A change.\n\n## [0.0.0]\n\n- Undated.\n")

      error = assert_raises(Release::Refusal) { Release.new(root:).check("v0.0.0") }
      assert_equal "CHANGELOG.md has no section headed ## [0.0.0] - YYYY-MM-DD", error.message
    end
  end

  # A real gem of +name+, +version+, and +platform+, built into +dir+, and
  # the .sha256 file its delivery writes beside it.
  def gem(dir, platform, version: "0.0.0", name: "lota", sha256: nil)
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.platform = platform
      s.summary = "A test gem."
      s.authors = ["Test"]
      s.files = []
    end
    target = "lota-0.0.0-#{platform}.gem"
    Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
      Gem::Package.build(spec, true, false, File.join(dir, target))
    end
    File.write(File.join(dir, "#{target}.sha256"), "#{sha256 || Digest::SHA256.file(File.join(dir, target)).hexdigest}  #{target}\n")
    target
  end

  PLATFORMS = %w[arm64-darwin x86_64-linux-gnu].freeze

  def test_assemble_replaces_each_gems_checksum_with_one_sha256sums_for_them_all
    in_tree do |root|
      repository(root)
      dir = File.join(root, "release")
      Dir.mkdir(dir)
      gems = PLATFORMS.map { |platform| gem(dir, platform) }

      assert_equal gems, Release.new(root:).assemble(dir, PLATFORMS)
      assert_equal (gems + ["SHA256SUMS"]).sort, Dir.children(dir).sort
      assert_equal gems.sort.map { |g| "#{Digest::SHA256.file(File.join(dir, g)).hexdigest}  #{g}\n" }.join,
        File.read(File.join(dir, "SHA256SUMS"))
    end
  end

  def test_assemble_refuses_a_missing_platform_and_an_unexpected_file
    in_tree do |root|
      repository(root)
      dir = File.join(root, "release")
      Dir.mkdir(dir)
      gem(dir, "arm64-darwin")
      write(dir, "stray.gem")

      error = assert_raises(Release::Refusal) { Release.new(root:).assemble(dir, PLATFORMS) }
      assert_match(/missing lota-0\.0\.0-x86_64-linux-gnu\.gem, lota-0\.0\.0-x86_64-linux-gnu\.gem\.sha256; unexpected stray\.gem\z/, error.message)
    end
  end

  def test_assemble_refuses_a_gem_whose_bytes_are_not_the_ones_delivery_verified
    in_tree do |root|
      repository(root)
      dir = File.join(root, "release")
      Dir.mkdir(dir)
      gem(dir, "arm64-darwin", sha256: "0" * 64)

      error = assert_raises(Release::Refusal) { Release.new(root:).assemble(dir, ["arm64-darwin"]) }
      assert_match(/has SHA-256 \h{64}, not the 0{64} its delivery verified/, error.message)
      refute_path_exists File.join(dir, "SHA256SUMS")
    end
  end

  def test_assemble_refuses_a_gem_whose_specification_is_not_the_one_its_name_says
    in_tree do |root|
      repository(root)
      dir = File.join(root, "release")
      Dir.mkdir(dir)
      gem(dir, "arm64-darwin", version: "9.9.9")

      error = assert_raises(Release::Refusal) { Release.new(root:).assemble(dir, ["arm64-darwin"]) }
      assert_equal "lota-0.0.0-arm64-darwin.gem holds lota 9.9.9 arm64-darwin, not lota 0.0.0 arm64-darwin", error.message
    end
  end
end
