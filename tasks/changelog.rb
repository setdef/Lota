# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# CHANGELOG.md, in Keep a Changelog's format, read as Lota's releases read
# it (doc/contributors/releasing.md).
#
# A release tags whatever commit CI proved, wherever trunk has moved since,
# so the commit it tags may come before the last release's dated section
# reached trunk. Its [Unreleased] then still lists what the last release
# carried. So a release's notes are the entries of [Unreleased] at its
# commit that were not in [Unreleased] at the release before it
# (Changelog.added), and its dated section is written afterward, on top of
# trunk, by moving exactly those entries out of [Unreleased] (#record).
#
# This class reads and rewrites the text alone; Release reads it from the
# commits and tags it names.
class Changelog
  # An entry: a list item, with any lines that continue it, under the
  # ### heading it is listed under, or nil above any.
  class Entry < Data.define(:heading, :text); end

  # The heading of the changes no release holds yet.
  UNRELEASED = "## [Unreleased]"

  # A released section's heading: ## [0.3.1] - 2026-11-09.
  DATED = /\A## \[(?<version>[^\]]+)\] - (?<date>\d{4}-\d{2}-\d{2})\s*\z/

  # A list item that starts an entry, as against a line that continues one.
  ITEM = /\A[-*]\s/

  # An entry that marks a breaking change: one that starts with Breaking:,
  # bold or not.
  BREAKING = /\A[-*]\s+(?:\*\*)?Breaking:/

  # Raised when the text is not a changelog this class can read.
  class Malformed < StandardError; end

  # The entries of +entries+ that +previous+ does not hold, in order. An
  # entry listed twice in +entries+ and once in +previous+ is added once.
  def self.added(entries, previous)
    left = previous.tally
    entries.reject do |entry|
      next false unless left[entry].to_i.positive?

      left[entry] -= 1
      true
    end
  end

  # Whether any of +entries+ is a breaking change.
  def self.breaking?(entries)
    entries.any? { |entry| entry.text.match?(BREAKING) }
  end

  # +entries+ as a section's body: each heading once, where its first
  # entry is, with its entries under it.
  def self.body(entries)
    entries.group_by(&:heading).map do |heading, group|
      items = group.map { |entry| "#{entry.text}\n" }.join
      heading ? "#{heading}\n\n#{items}" : items
    end.join("\n")
  end

  # [text] The changelog's Markdown.
  def initialize(text)
    @lines = text.lines.map { |line| line.end_with?("\n") ? line : "#{line}\n" }
  end

  # The changelog's Markdown.
  def to_s
    @lines.join
  end

  # The entries of [Unreleased].
  def unreleased
    parse(section(unreleased_heading))
  end

  # The versions of the dated sections, as they are listed.
  def versions
    @lines.filter_map { |line| line.match(DATED)&.[](:version) }
  end

  # The entries of the dated section for +version+, or nil when there is
  # none.
  def released(version)
    heading = dated_heading(version)
    heading && parse(section(heading))
  end

  # The body of the dated section for +version+ as written, or nil when
  # there is none.
  def released_text(version)
    heading = dated_heading(version)
    heading && section(heading).join.strip
  end

  # This changelog with a section for +version+, dated +date+, listing
  # +entries+, below [Unreleased] and above the sections of older
  # versions, and with each of +moved+ taken out of [Unreleased] once
  # where it is still there, along with any heading left with nothing
  # under it. Returns self unchanged when a section for +version+ is there
  # already, so recording a release twice records it once.
  def record(version, date, entries, moved)
    return self if dated_heading(version)

    heading = unreleased_heading
    kept = without(section(heading), moved)
    after = heading + 1 + section(heading).size
    rest = @lines.drop(after)
    at = older_section(rest, version) || rest.size
    older = rest.drop(at)
    dated = ["## [#{version}] - #{date.iso8601}\n", "\n", Changelog.body(entries), *("\n" unless older.empty?)]
    Changelog.new([*@lines.take(heading + 1), *kept, *rest.take(at), *dated, *older].join)
  end

  private def unreleased_heading
    @lines.index { |line| line.chomp == UNRELEASED } or raise Malformed, "the changelog has no #{UNRELEASED} section"
  end

  private def dated_heading(version)
    @lines.index { |line| line.match(DATED)&.[](:version) == version }
  end

  # The lines after +heading+, up to the next section's heading.
  private def section(heading)
    @lines.drop(heading + 1).take_while { |line| !line.start_with?("## ") }
  end

  private def parse(lines)
    blocks(lines).filter_map(&:entry)
  end

  # The index in +lines+ of the first dated section older than +version+.
  private def older_section(lines, version)
    lines.index do |line|
      found = line.match(DATED)&.[](:version)
      found && Gem::Version.new(found) < Gem::Version.new(version)
    end
  end

  # +lines+ of [Unreleased] without the entries in +moved+, nor the
  # headings that then head nothing, with one blank line around what is
  # left.
  private def without(lines, moved)
    left = moved.tally
    blocks = blocks(lines).reject do |block|
      entry = block.entry
      next false unless entry && left[entry].to_i.positive?

      left[entry] -= 1
      true
    end
    tidy(blocks)
  end

  # A part of a section: a heading's line, an entry's lines, or a line of
  # anything else, with the Entry it is, if it is one.
  class Block < Data.define(:heading, :entry, :lines)
    # Whether it is a ### heading.
    def heading? = entry.nil? && lines.first.start_with?("### ")
  end
  private_constant :Block

  # +lines+ cut into blocks.
  private def blocks(lines)
    heading = nil
    lines.each_with_object([]) do |line, blocks|
      last = blocks.last
      if line.start_with?("### ")
        heading = line.strip
        blocks << Block.new(heading, nil, [line])
      elsif line.match?(ITEM)
        blocks << Block.new(heading, Entry.new(heading, line.rstrip), [line])
      elsif !line.strip.empty? && last&.entry && line.start_with?(" ", "\t")
        blocks[-1] = last.with(entry: last.entry.with(text: "#{last.entry.text}\n#{line.rstrip}"), lines: [*last.lines, line])
      else
        blocks << Block.new(heading, nil, [line])
      end
    end
  end

  # The lines of +blocks+, leaving out each heading with no entry left
  # under it, and blank lines run together.
  private def tidy(blocks)
    kept = blocks.each_with_index.reject do |block, index|
      block.heading? && blocks.drop(index + 1).take_while { |later| !later.heading? }.none?(&:entry)
    end
    lines = kept.flat_map { |block, _index| block.lines }
    lines = lines.chunk_while { |a, b| a.strip.empty? && b.strip.empty? }.map(&:first)
    lines.shift while lines.first&.strip&.empty?
    lines.pop while lines.last&.strip&.empty?
    lines.empty? ? ["\n"] : ["\n", *lines, "\n"]
  end
end
