# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "release"

# The decisions CI makes when it releases (doc/contributors/releasing.md):
# before a run builds its gems, which version its commit would release as,
# so the gems carry it; and once every job has passed, what the release
# job does for that commit. Each is a pure function of what the caller
# read from git, CHANGELOG.md, sig/, and GitHub, so the tests can ask it
# every case.
module ReleasePlan
  # Raised when the release must not go ahead.
  Refusal = Release::Refusal

  # The first version CI does not release on its own.
  BY_HAND = Gem::Version.new("1.0.0")

  # The version a commit releases as, or nil, and why.
  class Decision < Data.define(:version, :reason); end

  # What the release job does, and why.
  class Action < Data.define(:name, :reason); end

  # The version CI releases a commit as, when it picks it on its own. +previous+
  # is the version of the newest release tag before the commit, or nil;
  # +covering+, the release tags on the commit or after it; +entries+, the
  # CHANGELOG.md entries the commit adds since +previous+ (Release#added);
  # +breaks+, what ApiDiff found sig/ removes or changes since +previous+;
  # +ruby+, the Ruby the commit pins.
  #
  # The next PATCH, or the next MINOR when an entry says Breaking:.
  # Nothing when a release already holds the commit, when no release tag
  # is fetched, when the commit adds no entry, or from 1.0.0 on, which is
  # released by hand. Refuses an API break that no entry says is one.
  def self.decide(previous:, covering:, entries:, breaks:, ruby:)
    return Decision.new(nil, "#{covering.last} already releases this commit") if covering.any?
    return Decision.new(nil, "no release tag comes before this commit; fetch the tags") unless previous
    return Decision.new(nil, "CHANGELOG.md's [Unreleased] adds nothing since v#{previous}") if entries.empty?
    return Decision.new(nil, "#{previous} is 1.0.0 or later, which is released by hand") if Gem::Version.new(previous) >= BY_HAND

    major, minor, patch = previous.split(".").map(&:to_i)
    version, reason = if Changelog.breaking?(entries)
      ["#{major}.#{minor + 1}.0", "[Unreleased] adds a Breaking: entry since v#{previous}"]
    else
      raise Refusal, unmarked(previous, breaks) unless breaks.empty?

      ["#{major}.#{minor}.#{patch + 1}", "[Unreleased] adds entries since v#{previous}, none of them Breaking:"]
    end
    check_ruby(version, ruby)
    Decision.new(version, reason)
  end

  # Checks +tag+, pushed by hand, as a release of its commit, and returns
  # its version. The arguments are #decide's. Refuses a tag that is not v
  # and MAJOR.MINOR.PATCH, one not newer than +previous+, a commit that
  # adds nothing, an API break no entry marks, a Breaking: entry released
  # without the bump SemVer asks of it, and 1.0.0 or later while +ruby+ is
  # a preview.
  def self.check_tag(tag:, previous:, entries:, breaks:, ruby:)
    number = tag.delete_prefix("v")
    raise Refusal, "#{tag} is not a release tag, which is v and MAJOR.MINOR.PATCH" unless tag.match?(Release::TAG)
    raise Refusal, "#{tag} is not newer than v#{previous}" if previous && Gem::Version.new(number) <= Gem::Version.new(previous)
    raise Refusal, "CHANGELOG.md's [Unreleased] adds nothing#{" since v#{previous}" if previous} for #{tag} to release" if entries.empty?

    breaking = Changelog.breaking?(entries)
    raise Refusal, unmarked(previous, breaks) unless breaking || breaks.empty?
    raise Refusal, "[Unreleased] has a Breaking: entry, which #{tag} releases without a #{major?(previous) ? 'MAJOR' : 'MINOR'} bump" if
      breaking && previous && !bumped?(previous, number)

    check_ruby(number, ruby)
    number
  end

  # Refuses +version+ 1.0.0 or later while +ruby+, the Ruby the commit
  # pins, is a preview: a 1.0 is a promise about the Ruby it runs on.
  def self.check_ruby(version, ruby)
    return if Gem::Version.new(version) < BY_HAND
    return unless Gem::Version.correct?(ruby) && Gem::Version.new(ruby).prerelease?

    raise Refusal, "#{version} would be 1.0.0 or later, while mise.toml pins Ruby #{ruby}, a preview; pin a released Ruby first"
  end

  # What the release job does for the gems of +built+, the version this
  # run stamped into them, on commit +sha+, once every job passed: +tagged+
  # is the commit v+built+ already points at, or nil; +released+, whether
  # GitHub has a release of it; +decision+, #decide asked again now, with
  # the tags as they are.
  #
  # :tag_and_publish:: Tag +sha+, then publish.
  # :publish:: The tag is there, on +sha+; publish.
  # :done:: Tagged and published already; do nothing again.
  # :skip:: Release nothing: this run built no release, or a release made
  #         since it began holds the commit, or gives its version.
  #
  # Refuses when the tag points at another commit, since a tag never
  # moves, and when a release exists without its tag.
  def self.publish(built:, sha:, tagged:, released:, decision:)
    return Action.new(:skip, "this run built no release: #{decision.reason}") unless built

    tag = "v#{built}"
    raise Refusal, "#{tag} already tags #{tagged}, not #{sha}; a pushed tag never moves" if tagged && tagged != sha
    return Action.new(released ? :done : :publish, "#{tag} tags #{sha}") if tagged
    raise Refusal, "GitHub has a release #{tag}, but there is no tag #{tag}" if released
    return Action.new(:skip, "this run built #{built}, but now #{decision.reason}") unless decision.version == built

    Action.new(:tag_and_publish, decision.reason)
  end

  private_class_method def self.unmarked(previous, breaks)
    "sig/ removes or changes Lota's API since v#{previous}, and CHANGELOG.md's [Unreleased] has no **Breaking:** entry. " \
      "Add one for each, or restore the API:\n#{breaks.map { |line| "  #{line}\n" }.join}"
  end

  private_class_method def self.major?(previous)
    previous && Gem::Version.new(previous) >= BY_HAND
  end

  private_class_method def self.bumped?(previous, number)
    old_major, old_minor = previous.split(".").map(&:to_i)
    major, minor = number.split(".").map(&:to_i)
    major?(previous) ? major > old_major : major > old_major || minor > old_minor
  end
end
