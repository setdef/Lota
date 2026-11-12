# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/changelog"
require "date"

# Changelog reads [Unreleased] and the dated sections as entries, tells
# what a commit adds since the release before it, and writes a release's
# dated section by moving exactly its entries out of [Unreleased].
class ChangelogTest < Minitest::Test
  TEXT = <<~MARKDOWN
    # Changelog

    Preamble.

    ## [Unreleased]

    ### Added

    - A new function.
    - A wrapped entry
      that goes on.

    ### Changed

    - **Breaking:** an old function is gone.

    ## [0.3.1] - 2026-11-09

    ### Fixed

    - An old fix.

    ## [0.3.0] - 2026-11-08

    - An older change.
  MARKDOWN

  def entry(heading, text) = Changelog::Entry.new(heading, text)

  ADDED = "### Added"
  CHANGED = "### Changed"

  def test_unreleased_is_its_entries_under_their_headings_with_wrapped_lines_kept
    assert_equal [
      entry(ADDED, "- A new function."),
      entry(ADDED, "- A wrapped entry\n  that goes on."),
      entry(CHANGED, "- **Breaking:** an old function is gone."),
    ], Changelog.new(TEXT).unreleased
  end

  def test_a_dated_section_is_read_as_entries_and_as_written
    log = Changelog.new(TEXT)

    assert_equal [entry("### Fixed", "- An old fix.")], log.released("0.3.1")
    assert_equal "### Fixed\n\n- An old fix.", log.released_text("0.3.1")
    assert_equal [entry(nil, "- An older change.")], log.released("0.3.0")
    assert_nil log.released("0.2.0")
    assert_equal %w[0.3.1 0.3.0], log.versions
  end

  def test_a_changelog_without_unreleased_is_malformed
    assert_raises(Changelog::Malformed) { Changelog.new("# Changelog\n").unreleased }
  end

  def test_added_is_what_the_previous_release_did_not_list_counting_repeats
    old = entry(ADDED, "- Old.")
    new = entry(ADDED, "- New.")
    same_text_elsewhere = entry(CHANGED, "- Old.")

    assert_equal [new, same_text_elsewhere], Changelog.added([old, new, same_text_elsewhere], [old])
    assert_equal [old], Changelog.added([old, old], [old])
    assert_empty Changelog.added([old], [old, old])
  end

  def test_breaking_is_an_entry_that_starts_with_breaking_bold_or_not
    assert Changelog.breaking?([entry(nil, "- Breaking: gone.")])
    assert Changelog.breaking?([entry(nil, "- **Breaking:** gone.")])
    refute Changelog.breaking?([entry(nil, "- Fixes a Breaking: label in a message.")])
  end

  def test_a_body_lists_each_heading_once_where_its_first_entry_is
    entries = [entry(ADDED, "- One."), entry(CHANGED, "- Two."), entry(ADDED, "- Three.")]

    assert_equal "### Added\n\n- One.\n- Three.\n\n### Changed\n\n- Two.\n", Changelog.body(entries)
  end

  def test_recording_moves_exactly_the_released_entries_under_a_dated_section
    log = Changelog.new(TEXT)
    released = log.unreleased.first(2)
    later = log.record("0.4.0", Date.new(2026, 11, 12), released, released)

    assert_equal <<~MARKDOWN, later.to_s
      # Changelog

      Preamble.

      ## [Unreleased]

      ### Changed

      - **Breaking:** an old function is gone.

      ## [0.4.0] - 2026-11-12

      ### Added

      - A new function.
      - A wrapped entry
        that goes on.

      ## [0.3.1] - 2026-11-09

      ### Fixed

      - An old fix.

      ## [0.3.0] - 2026-11-08

      - An older change.
    MARKDOWN
  end

  def test_recording_every_entry_leaves_unreleased_empty
    log = Changelog.new("# Changelog\n\n## [Unreleased]\n\n### Added\n\n- New.\n")
    later = log.record("0.1.0", Date.new(2026, 1, 2), log.unreleased, log.unreleased)

    assert_equal "# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - 2026-01-02\n\n### Added\n\n- New.\n", later.to_s
  end

  # Entries added since the tagged commit stay where they are; an entry
  # the release listed that trunk no longer has is not taken twice.
  def test_recording_leaves_later_entries_and_takes_nothing_that_is_gone
    log = Changelog.new("## [Unreleased]\n\n- Later.\n")
    released = [entry(nil, "- Released, then removed.")]

    assert_equal "## [Unreleased]\n\n- Later.\n\n## [0.1.0] - 2026-01-02\n\n- Released, then removed.\n",
      log.record("0.1.0", Date.new(2026, 1, 2), released, released).to_s
  end

  def test_recording_a_version_already_recorded_changes_nothing
    log = Changelog.new(TEXT)

    assert_equal TEXT, log.record("0.3.1", Date.new(2026, 11, 12), log.unreleased, log.unreleased).to_s
  end

  def test_an_older_version_is_recorded_below_the_newer_ones
    log = Changelog.new("## [Unreleased]\n\n## [0.4.0] - 2026-01-03\n\n- Newer.\n\n## [0.2.0] - 2026-01-01\n\n- Older.\n")
    later = log.record("0.3.0", Date.new(2026, 1, 2), [entry(nil, "- Middle.")], [])

    assert_equal %w[0.4.0 0.3.0 0.2.0], later.versions
    assert_equal [entry(nil, "- Middle.")], later.released("0.3.0")
  end
end
