# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "release"

# The decisions CI makes when it releases on its own
# (doc/contributors/releasing.md): after a full run passes on trunk,
# whether there is something to release and which version it is; and in
# the run that proves the release commit, what the release job does for
# its tag. Each is a pure function of what the caller read from the
# repository, CHANGELOG.md, and GitHub, so the tests can ask it every case.
module ReleasePlan
  # Raised when the release must not go ahead.
  Refusal = Release::Refusal

  # A CHANGELOG.md entry that marks a breaking change: a list item that
  # starts with Breaking:, bold or not.
  BREAKING = /\A\s*[-*]\s+(?:\*\*)?Breaking:/

  # A list item: an entry, as against a heading or a blank line.
  ENTRY = /\A\s*[-*]\s/

  # The first version CI does not release on its own.
  BY_HAND = Gem::Version.new("1.0.0")

  # The version to release next, or nil, and why.
  class Next < Data.define(:version, :reason); end

  # What to release after +version+, the version lib/lota/version.rb
  # gives: the next PATCH, or the next MINOR when +unreleased+, the lines
  # of CHANGELOG.md's [Unreleased], has a Breaking: entry. Nothing while
  # +version+ has no tag among +tags+ (its release is in flight, or
  # stalled), when [Unreleased] lists nothing, or from 1.0.0 on. Refuses
  # when +breaks+, what ApiDiff found removed or changed since +version+,
  # is not empty and no entry says Breaking:.
  def self.next_release(version:, unreleased:, tags:, breaks:)
    unless tags.include?("v#{version}")
      return Next.new(nil, "#{version} is prepared, but v#{version} has no tag yet: its release is in flight, or stalled")
    end

    entries = unreleased.grep(ENTRY)
    return Next.new(nil, "CHANGELOG.md's [Unreleased] lists no changes") if entries.empty?
    return Next.new(nil, "#{version} is 1.0.0 or later, and 1.0.0 and later are released by hand") if Gem::Version.new(version) >= BY_HAND

    major, minor, patch = version.split(".").map(&:to_i)
    return Next.new("#{major}.#{minor + 1}.0", "[Unreleased] has a Breaking: entry") if entries.any?(BREAKING)
    raise Refusal, unmarked(version, breaks) unless breaks.empty?

    Next.new("#{major}.#{minor}.#{patch + 1}", "[Unreleased] lists changes, none of them Breaking:")
  end

  # What the release job does for +tag+ on commit +sha+: +tagged+ is the
  # commit +tag+ already points at, or nil; +released+, whether GitHub
  # has a release for it; +unreleased+, the commit's [Unreleased] lines.
  #
  # :tag_and_publish:: Tag +sha+, then publish.
  # :publish:: The tag is there, on +sha+; publish.
  # :done:: Tagged and published already; do nothing again.
  # :skip:: +sha+ is not a release commit, since [Unreleased] lists
  #         changes the release would carry unnamed: trunk moved before
  #         the run began.
  #
  # Refuses when the tag points at another commit, since a tag never
  # moves, and when a release exists without its tag.
  def self.publish(tag:, sha:, tagged:, released:, unreleased:)
    raise Refusal, "#{tag} already tags #{tagged}, not #{sha}; a pushed tag never moves" if tagged && tagged != sha
    return released ? :done : :publish if tagged
    raise Refusal, "GitHub has a release #{tag}, but there is no tag #{tag}" if released
    return :skip if unreleased.grep(ENTRY).any?

    :tag_and_publish
  end

  private_class_method def self.unmarked(version, breaks)
    "sig/ removes or changes Lota's API since v#{version}, and CHANGELOG.md's [Unreleased] has no **Breaking:** entry. " \
      "Add one for each, or restore the API:\n#{breaks.map { |line| "  #{line}\n" }.join}"
  end
end
