# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/release_plan"

# What CI releases: which version a commit it picks releases as, whether a
# tag pushed by hand may release its commit, and what the release job does
# once a run has passed.
class ReleasePlanTest < Minitest::Test
  ADDED = [Changelog::Entry.new("### Added", "- A new function.")].freeze
  BREAKING = [Changelog::Entry.new("### Changed", "- **Breaking:** an old function is gone.")].freeze
  RUBY = "4.0.7"

  def decide(entries: ADDED, previous: "0.3.1", covering: [], breaks: [], ruby: RUBY)
    ReleasePlan.decide(previous:, covering:, entries:, breaks:, ruby:)
  end

  def test_entries_with_no_breaking_one_bump_the_patch_version
    assert_equal "0.3.2", decide.version
  end

  def test_a_breaking_entry_bumps_the_minor_version_and_resets_the_patch
    assert_equal "0.4.0", decide(entries: ADDED + BREAKING).version
  end

  def test_a_commit_that_adds_nothing_releases_nothing
    decision = decide(entries: [])

    assert_nil decision.version
    assert_equal "CHANGELOG.md's [Unreleased] adds nothing since v0.3.1", decision.reason
  end

  # A release tag on the commit, or on a later one, already holds it, as
  # when a newer run released first: the older run releases nothing.
  def test_a_commit_a_release_already_holds_releases_nothing
    decision = decide(covering: %w[v0.3.2 v0.4.0])

    assert_nil decision.version
    assert_equal "v0.4.0 already releases this commit", decision.reason
  end

  def test_with_no_release_tag_fetched_nothing_is_released
    decision = decide(previous: nil)

    assert_nil decision.version
    assert_match(/fetch the tags/, decision.reason)
  end

  def test_from_one_point_oh_releases_are_cut_by_hand
    decision = decide(previous: "1.0.0")

    assert_nil decision.version
    assert_match(/1\.0\.0 or later, which is released by hand/, decision.reason)
  end

  def test_an_api_break_with_no_breaking_entry_is_refused_and_named
    error = assert_raises(ReleasePlan::Refusal) do
      decide(breaks: ["removed Lota::Sensor.get_name", "changed Lota::Audio.pause"])
    end

    assert_match(/no \*\*Breaking:\*\* entry/, error.message)
    assert_includes error.message, "  removed Lota::Sensor.get_name\n"
    assert_includes error.message, "  changed Lota::Audio.pause"
  end

  def test_an_api_break_with_a_breaking_entry_bumps_the_minor_version
    assert_equal "0.4.0", decide(entries: BREAKING, breaks: ["removed Lota::Sensor.get_name"]).version
  end

  def check_tag(tag, entries: ADDED, previous: "0.3.1", breaks: [], ruby: RUBY)
    ReleasePlan.check_tag(tag:, previous:, entries:, breaks:, ruby:)
  end

  def test_a_tag_pushed_by_hand_releases_its_version
    assert_equal "0.3.2", check_tag("v0.3.2")
    assert_equal "1.0.0", check_tag("v1.0.0", entries: BREAKING)
  end

  def test_a_tag_that_is_not_v_and_three_numbers_is_refused
    %w[0.3.2 v0.4 v0.4.0-rc1 version0.4.0].each do |tag|
      assert_raises(ReleasePlan::Refusal, tag) { check_tag(tag) }
    end
  end

  def test_a_tag_not_newer_than_the_last_release_is_refused
    error = assert_raises(ReleasePlan::Refusal) { check_tag("v0.3.1") }

    assert_equal "v0.3.1 is not newer than v0.3.1", error.message
  end

  def test_a_tag_on_a_commit_that_adds_nothing_is_refused
    assert_raises(ReleasePlan::Refusal) { check_tag("v0.3.2", entries: []) }
  end

  def test_a_tag_that_releases_a_breaking_entry_as_a_patch_is_refused
    error = assert_raises(ReleasePlan::Refusal) { check_tag("v0.3.2", entries: BREAKING) }

    assert_match(/without a MINOR bump/, error.message)
    assert_equal "0.4.0", check_tag("v0.4.0", entries: BREAKING)
    assert_match(/without a MAJOR bump/, assert_raises(ReleasePlan::Refusal) do
      check_tag("v1.1.0", previous: "1.0.0", entries: BREAKING)
    end.message)
  end

  def test_a_tag_with_an_unmarked_api_break_is_refused
    assert_raises(ReleasePlan::Refusal) { check_tag("v0.4.0", breaks: ["removed Lota::Sensor.get_name"]) }
  end

  # 1.0.0 is a promise about the Ruby it runs on, so no release of it
  # goes out while the Ruby Lota pins is a preview.
  def test_one_point_oh_is_refused_while_the_pinned_ruby_is_a_preview
    error = assert_raises(ReleasePlan::Refusal) { check_tag("v1.0.0", entries: BREAKING, ruby: "4.1.0-preview1") }

    assert_match(/pins Ruby 4\.1\.0-preview1, a preview/, error.message)
    assert_equal "0.4.0", check_tag("v0.4.0", entries: BREAKING, ruby: "4.1.0-preview1")
  end

  SHA = "a" * 40
  OTHER = "b" * 40

  def publish(built: "0.3.2", tagged: nil, released: false, decision: ReleasePlan::Decision.new("0.3.2", "adds entries"))
    ReleasePlan.publish(built:, sha: SHA, tagged:, released:, decision:).name
  end

  def test_gems_built_as_the_version_the_commit_still_releases_as_are_tagged_and_published
    assert_equal :tag_and_publish, publish
  end

  def test_a_commit_already_tagged_with_no_release_yet_is_published
    assert_equal :publish, publish(tagged: SHA, decision: nil)
  end

  def test_a_commit_already_tagged_and_released_is_left_alone
    assert_equal :done, publish(tagged: SHA, released: true, decision: nil)
  end

  def test_a_run_that_built_no_release_releases_nothing
    assert_equal :skip, publish(built: nil, decision: ReleasePlan::Decision.new(nil, "adds nothing"))
  end

  # A release made while the run went on holds the commit, or moved the
  # version on, so the gems this run built carry the wrong version.
  def test_gems_whose_version_a_newer_release_has_overtaken_are_not_released
    assert_equal :skip, publish(decision: ReleasePlan::Decision.new(nil, "v0.3.2 already releases this commit"))
    assert_equal :skip, publish(decision: ReleasePlan::Decision.new("0.3.3", "adds entries"))
  end

  def test_a_tag_on_another_commit_is_never_moved
    error = assert_raises(ReleasePlan::Refusal) { publish(tagged: OTHER) }

    assert_match(/v0\.3\.2 already tags #{OTHER}, not #{SHA}/, error.message)
  end

  def test_a_release_without_its_tag_is_refused
    assert_raises(ReleasePlan::Refusal) { publish(released: true) }
  end
end
