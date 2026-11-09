# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/release_plan"

# What CI releases on its own: whether a green trunk has something to
# release, which version it is, and what the release job does for a tag.
class ReleasePlanTest < Minitest::Test
  ADDED = ["\n", "### Added\n", "\n", "- A new function.\n", "\n"].freeze
  BREAKING = ["### Changed\n", "\n", "- **Breaking:** an old function is gone.\n"].freeze
  TAGS = %w[v0.1.0 v0.3.0 v0.3.1].freeze

  def next_release(unreleased: ADDED, version: "0.3.1", tags: TAGS, breaks: [])
    ReleasePlan.next_release(version:, unreleased:, tags:, breaks:)
  end

  def test_changes_with_no_breaking_entry_bump_the_patch_version
    assert_equal "0.3.2", next_release.version
  end

  def test_a_breaking_entry_bumps_the_minor_version_and_resets_the_patch
    assert_equal "0.4.0", next_release(unreleased: ADDED + BREAKING).version
  end

  def test_a_breaking_entry_counts_with_or_without_bold
    assert_equal "0.4.0", next_release(unreleased: ["- Breaking: an old function is gone.\n"]).version
  end

  def test_the_word_breaking_inside_an_entry_is_not_a_breaking_entry
    assert_equal "0.3.2", next_release(unreleased: ["- Fixes a Breaking: label in a message.\n"]).version
  end

  def test_an_empty_unreleased_section_releases_nothing
    plan = next_release(unreleased: ["\n", "### Added\n", "\n"])

    assert_nil plan.version
    assert_equal "CHANGELOG.md's [Unreleased] lists no changes", plan.reason
  end

  def test_a_version_with_no_tag_yet_is_a_release_in_flight_and_nothing_more_is_prepared
    plan = next_release(tags: %w[v0.3.0])

    assert_nil plan.version
    assert_match(/0\.3\.1 is prepared, but v0\.3\.1 has no tag yet/, plan.reason)
  end

  def test_from_one_point_oh_releases_are_cut_by_hand
    plan = next_release(version: "1.0.0", tags: %w[v1.0.0])

    assert_nil plan.version
    assert_match(/1\.0\.0 and later/, plan.reason)
  end

  def test_an_api_break_with_no_breaking_entry_is_refused_and_named
    error = assert_raises(ReleasePlan::Refusal) do
      next_release(breaks: ["removed Lota::Sensor.get_name", "changed Lota::Audio.pause"])
    end

    assert_match(/no \*\*Breaking:\*\* entry/, error.message)
    assert_includes error.message, "  removed Lota::Sensor.get_name\n"
    assert_includes error.message, "  changed Lota::Audio.pause"
  end

  def test_an_api_break_with_a_breaking_entry_bumps_the_minor_version
    assert_equal "0.4.0", next_release(unreleased: BREAKING, breaks: ["removed Lota::Sensor.get_name"]).version
  end

  SHA = "a" * 40
  OTHER = "b" * 40

  def publish(tagged: nil, released: false, unreleased: [])
    ReleasePlan.publish(tag: "v0.3.2", sha: SHA, tagged:, released:, unreleased:)
  end

  def test_an_untagged_release_commit_is_tagged_and_published
    assert_equal :tag_and_publish, publish
  end

  def test_a_commit_already_tagged_with_no_release_yet_is_published
    assert_equal :publish, publish(tagged: SHA)
  end

  def test_a_commit_already_tagged_and_released_is_left_alone
    assert_equal :done, publish(tagged: SHA, released: true)
  end

  def test_a_tag_on_another_commit_is_never_moved
    error = assert_raises(ReleasePlan::Refusal) { publish(tagged: OTHER) }

    assert_match(/v0\.3\.2 already tags #{OTHER}, not #{SHA}/, error.message)
  end

  def test_a_release_without_its_tag_is_refused
    assert_raises(ReleasePlan::Refusal) { publish(released: true) }
  end

  def test_an_untagged_commit_with_unreleased_changes_is_not_a_release_commit
    assert_equal :skip, publish(unreleased: ["- A change after the release.\n"])
  end
end
