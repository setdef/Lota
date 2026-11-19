# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/provenance"

# Provenance judges each commit a push brings by its message and the
# Provenance: trailers git reads in it, and tells the author of a commit
# that fails how to mend it.
class ProvenanceTest < Minitest::Test
  FOOTER = "Co-Authored-By: Sample <sample@example.com>\n"

  def commit(message, values, sha: "a" * 40, subject: "chore: do a thing")
    Provenance::Commit.new(sha:, subject:, message: "#{subject}\n\nBecause.\n\n#{message}", values:)
  end

  def test_each_of_the_three_provenances_in_the_trailer_block_passes
    %w[written wrought requested].each do |value|
      assert_nil commit("Provenance: #{value}\n#{FOOTER}", [value]).fault
    end
  end

  def test_a_message_with_no_provenance_line_has_no_trailer
    assert_equal "has no Provenance: trailer", commit(FOOTER, []).fault
  end

  # The fault this check exists for: a blank line before the footer makes
  # the footer the trailer block and the provenance line body text.
  def test_a_provenance_line_git_does_not_read_as_a_trailer_is_not_in_the_trailer_block
    fault = commit("Provenance: requested\n\n#{FOOTER}", []).fault

    assert_equal "has a Provenance: line that is not in the trailer block " \
      "(a blank line separates it from the last paragraph)", fault
  end

  def test_two_provenances_are_one_too_many
    fault = commit("Provenance: requested\nProvenance: wrought\n#{FOOTER}", %w[requested wrought]).fault

    assert_equal "has 2 Provenance: trailers (requested, wrought); a commit holds work of one provenance", fault
  end

  def test_a_value_that_is_not_one_of_the_three_is_named
    assert_equal "has Provenance: Requested, which is not written, wrought, or requested",
      commit("Provenance: Requested\n#{FOOTER}", ["Requested"]).fault
    assert_equal "has Provenance: requested (mostly), which is not written, wrought, or requested",
      commit("Provenance: requested (mostly)\n#{FOOTER}", ["requested (mostly)"]).fault
  end

  # What git log writes for Provenance::FORMAT: a commit per record, its
  # fields apart, its trailer values apart, and the message whole.
  def test_git_logs_records_become_commits
    log = "#{'b' * 40}\x1ffix: b\x1frequested\x1dwrought\x1ffix: b\n\nBody.\n\nProvenance: requested\n\x1e\n" \
      "#{'c' * 40}\x1ffix: c\x1f\x1ffix: c\n\x1e\n"

    commits = Provenance.parse(log)

    assert_equal ["b" * 40, "fix: b", "fix: b\n\nBody.\n\nProvenance: requested\n", %w[requested wrought]],
      commits.first.deconstruct
    assert_equal ["c" * 40, "fix: c", "fix: c\n", []], commits.last.deconstruct
    assert_equal 2, commits.size
  end

  def test_nothing_is_refused_when_every_commit_passes
    assert_nil Provenance.refusal([commit("Provenance: requested\n#{FOOTER}", ["requested"])])
    assert_nil Provenance.refusal([])
  end

  # git log lists the newest first, so the rebase starts below the last
  # commit refused, which is the oldest.
  def test_the_refusal_names_each_commit_its_fault_and_the_remedy
    commits = [
      commit("Provenance: requested\n#{FOOTER}", ["requested"], sha: "1" * 40, subject: "fix: newest"),
      commit("Provenance: requested\n\n#{FOOTER}", [], sha: "2" * 40, subject: "fix: middle"),
      commit(FOOTER, [], sha: "3" * 40, subject: "fix: oldest"),
    ]

    refusal = Provenance.refusal(commits)

    assert_includes refusal, "2 commits do not say their provenance in a trailer git reads:\n"
    assert_includes refusal, "  #{'2' * 12} fix: middle\n    has a Provenance: line that is not in the trailer block"
    assert_includes refusal, "  #{'3' * 12} fix: oldest\n    has no Provenance: trailer\n"
    refute_includes refusal, "fix: newest"
    assert_includes refusal, "Provenance: written, wrought, or requested"
    assert_includes refusal, "with Co-Authored-By: and any Red-before-green: in one paragraph"
    assert_includes refusal, "git log -1 --format='%(trailers)' COMMIT"
    assert_includes refusal, "git commit --amend"
    assert_includes refusal, "git rebase -i #{'3' * 40}^"
  end
end
