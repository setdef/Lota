# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"

# Checks that each commit says its provenance in a trailer git reads, as
# AGENTS.md asks of every commit: one Provenance: line, written, wrought,
# or requested, in the message's last paragraph (rake provenance[RANGE],
# the first of the pre-push hook's checks). A line a blank line cuts off
# from the trailers after it is body text to git, so it says nothing,
# and a pushed commit cannot be mended; so the check reads the trailers
# as git does, and runs before the push, over the commits it brings.
#
# Merges and reverts made by git revert are commits like any other, and
# need the trailer too; the revert CI makes writes its own
# (tasks/auto_revert.rb).
class Provenance
  # The trailer, and the values it takes.
  TRAILER = "Provenance"
  VALUES = %w[written wrought requested].freeze

  # What git log writes for each commit: its name, its subject, the
  # values of the trailers git reads as Provenance:, and its message,
  # each apart from the next, and the commit apart from the next.
  FIELD = "\x1f"
  VALUE = "\x1d"
  RECORD = "\x1e"
  FORMAT = "%H%x1f%s%x1f%(trailers:key=#{TRAILER},valueonly,unfold,separator=%x1d)%x1f%B%x1e".freeze

  # A commit: its +sha+, +subject+, and +message+, and the +values+ of
  # the Provenance: trailers git reads in it.
  class Commit < Data.define(:sha, :subject, :message, :values)
    # What is wrong with the commit's provenance, or nil when nothing is.
    def fault
      return missing if values.empty?
      return "has #{values.size} #{TRAILER}: trailers (#{values.join(', ')}); a commit holds work of one provenance" if
        values.size > 1

      "has #{TRAILER}: #{values.first}, which is not #{Provenance.choices}" unless VALUES.include?(values.first)
    end

    # The fault of a commit git reads no Provenance: trailer in: it has
    # none, or a line of that name that git reads as body text.
    private def missing
      return "has no #{TRAILER}: trailer" unless message.match?(/^#{TRAILER}\s*:/i)

      "has a #{TRAILER}: line that is not in the trailer block (a blank line separates it from the last paragraph)"
    end
  end

  # The values the trailer takes, as a person reads them.
  def self.choices = "#{VALUES[0..-2].join(', ')}, or #{VALUES.last}"

  # The commits of +range+ (as git log takes it), newest first, read in
  # the checkout at +root+ with one git log.
  def self.read(root, range)
    output, error, status = Open3.capture3("git", "log", "--format=#{FORMAT}", range, chdir: root)
    raise ArgumentError, "git log #{range} failed: #{error.strip}" unless status.success?

    parse(output)
  end

  # The Commits in +log+, what git log writes for FORMAT.
  def self.parse(log)
    log.split(RECORD).filter_map do |record|
      sha, subject, values, message = record.delete_prefix("\n").split(FIELD, 4)
      Commit.new(sha:, subject:, message:, values: values.split(VALUE)) if message
    end
  end

  # What the author of +commits+ (newest first) reads when any of them
  # fails, naming each that fails, what is wrong, and how to mend it; nil
  # when none fails.
  def self.refusal(commits)
    faulty = commits.select(&:fault)
    return if faulty.empty?

    count = (faulty.size == 1) ? "1 commit does not say its provenance" : "#{faulty.size} commits do not say their provenance"
    [
      "#{count} in a trailer git reads:",
      *faulty.flat_map { |commit| ["  #{commit.sha[0, 12]} #{commit.subject}", "    #{commit.fault}"] },
      "Write one line, #{TRAILER}: #{choices}, in the message's last " \
        "paragraph, with Co-Authored-By: and any Red-before-green: in one paragraph, no blank line between " \
        "them; git log -1 --format='%(trailers)' COMMIT shows the trailers git reads. Mend HEAD's message " \
        "with git commit --amend, or each named here with git rebase -i #{faulty.last.sha}^, marking it reword.",
    ].join("\n")
  end
end
