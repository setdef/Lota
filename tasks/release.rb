# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "date"
require "digest"
require "open3"
require "rubygems/package"

# A release of Lota: a version, its CHANGELOG section, and one precompiled
# gem for each platform, published on GitHub for a tag
# (doc/contributors/releasing.md).
#
# A release is made of edits that are easy to get almost right by hand:
# the version in lib/lota/version.rb and Gemfile.lock, a CHANGELOG
# section moved out of [Unreleased] under a date, and a tag that names the
# same version. CI publishes whatever the tag points at, so a tag whose
# version disagrees with the code, or whose CHANGELOG says nothing, would
# publish a release that lies about itself.
#
# This class makes those edits mechanically (#prepare), and checks them
# again where CI publishes (#check, #notes, #assemble), so a release CI
# publishes is one whose tag, version, CHANGELOG, and gems agree.
class Release
  # Raised when a release cannot be prepared or published as asked.
  class Refusal < StandardError; end

  # The file that holds Lota::VERSION.
  VERSION_FILE = "lib/lota/version.rb"

  # The changelog, in Keep a Changelog's format.
  CHANGELOG = "CHANGELOG.md"

  # The lockfile, which records the version of the gem it is the bundle of.
  LOCKFILE = "Gemfile.lock"

  # The branch releases are cut from.
  BRANCH = "trunk"

  # A version a release can have: MAJOR.MINOR.PATCH, nothing more.
  NUMBER = /\A\d+\.\d+\.\d+\z/

  # Lota::VERSION's assignment in VERSION_FILE.
  ASSIGNMENT = /^(\s*VERSION = ")([^"]*)(")$/

  # The heading of the changes no release holds yet.
  UNRELEASED = "## [Unreleased]"

  # The file of checksums each release carries, in sha256sum's format.
  CHECKSUMS = "SHA256SUMS"

  # [root] The repository.
  # [branch] The branch #prepare runs on.
  def initialize(root:, branch: BRANCH)
    @root = root
    @branch = branch
  end

  # The version VERSION_FILE gives.
  def version
    match = read(VERSION_FILE).match(ASSIGNMENT)
    raise Refusal, "#{VERSION_FILE} assigns no VERSION" unless match

    match[2]
  end

  # Moves CHANGELOG.md's [Unreleased] changes under a heading for
  # +number+ and +date+, under a fresh, empty [Unreleased], and sets
  # +number+ as the version in VERSION_FILE and LOCKFILE. Refuses on a
  # tree with changes of its own, on a branch other than the one releases
  # are cut from, for a version that is not newer, and when [Unreleased]
  # holds nothing.
  def prepare(number, date: Date.today)
    check_tree
    check_number(number)
    changelog = prepared_changelog(number, date)
    lockfile = prepared_lockfile(number)
    write(CHANGELOG, changelog)
    write(LOCKFILE, lockfile)
    write(VERSION_FILE, read(VERSION_FILE).sub(ASSIGNMENT) { "#{Regexp.last_match(1)}#{number}#{Regexp.last_match(3)}" })
  end

  # Checks that +tag+ is a release tag for the version VERSION_FILE gives,
  # and that CHANGELOG.md has a dated section for it with something in it.
  # Returns the version.
  def check(tag)
    number = tag.delete_prefix("v")
    raise Refusal, "#{tag} is not a release tag, which is v and MAJOR.MINOR.PATCH" unless tag.start_with?("v") && number.match?(NUMBER)
    raise Refusal, "#{tag} names #{number}, but #{VERSION_FILE} says #{version}; tag the commit bundle exec rake release:prepare[#{number}] made" unless number == version

    notes(number)
    number
  end

  # The changes CHANGELOG.md lists under +number+'s dated heading, which
  # are the release's notes.
  def notes(number)
    lines = read(CHANGELOG).lines
    heading = lines.index { |line| line.match?(/\A## \[#{Regexp.escape(number)}\] - \d{4}-\d{2}-\d{2}$/) }
    raise Refusal, "#{CHANGELOG} has no section headed ## [#{number}] - YYYY-MM-DD" unless heading

    body = section(lines, heading).join.strip
    raise Refusal, "#{CHANGELOG}'s section for #{number} lists no changes" if body.empty?

    "#{body}\n"
  end

  # Checks that +dir+ holds exactly one gem of this version for each of
  # +platforms+, each the gem its <tt>.sha256</tt> file names by its
  # SHA-256, and replaces those files with one SHA256SUMS for them all.
  # Returns the gems' names.
  def assemble(dir, platforms)
    expected = platforms.map { |platform| "lota-#{version}-#{platform}.gem" }
    check_contents(dir, expected)
    platforms.zip(expected).each { |platform, gem| check_gem(dir, gem, platform) }
    File.write(File.join(dir, CHECKSUMS), expected.sort.map { |gem| "#{sha256(dir, gem)}  #{gem}\n" }.join)
    expected.each { |gem| File.delete(File.join(dir, "#{gem}.sha256")) }
    expected
  end

  private def check_tree
    changes = git("status", "--porcelain")
    raise Refusal, "the tree has changes of its own; commit or remove them first:\n#{changes}" unless changes.empty?

    branch = git("rev-parse", "--abbrev-ref", "HEAD").chomp
    raise Refusal, "releases are cut from #{@branch}, not #{branch}" unless branch == @branch
  end

  private def check_number(number)
    raise Refusal, "#{number} is not a version, which is MAJOR.MINOR.PATCH" unless number.match?(NUMBER)
    return if Gem::Version.new(number) > Gem::Version.new(version)

    raise Refusal, "#{number} is not newer than #{version}, the version #{VERSION_FILE} gives"
  end

  private def prepared_changelog(number, date)
    lines = read(CHANGELOG).lines
    heading = lines.index { |line| line.chomp == UNRELEASED }
    raise Refusal, "#{CHANGELOG} has no #{UNRELEASED} section" unless heading
    raise Refusal, "#{CHANGELOG} already has a section for #{number}" if lines.any? { |line| line.start_with?("## [#{number}]") }
    raise Refusal, "#{CHANGELOG}'s #{UNRELEASED} section lists no changes" if section(lines, heading).join.strip.empty?

    lines.insert(heading + 1, "\n", "## [#{number}] - #{date.iso8601}\n").join
  end

  private def prepared_lockfile(number)
    lockfile = read(LOCKFILE)
    pattern = /^(\s+lota \()#{Regexp.escape(version)}(\))$/
    raise Refusal, "#{LOCKFILE} records no lota #{version}" unless lockfile.match?(pattern)

    lockfile.gsub(pattern) { "#{Regexp.last_match(1)}#{number}#{Regexp.last_match(2)}" }
  end

  # The lines after +heading+, up to the next section's heading.
  private def section(lines, heading)
    lines.drop(heading + 1).take_while { |line| !line.start_with?("## ") }
  end

  private def check_contents(dir, expected)
    present = Dir.children(dir).sort
    wanted = expected.flat_map { |gem| [gem, "#{gem}.sha256"] }.sort
    return if present == wanted

    missing = wanted - present
    extra = present - wanted
    raise Refusal, "#{dir} is not one verified gem for each platform:" \
      "#{" missing #{missing.join(', ')};" unless missing.empty?}" \
      "#{" unexpected #{extra.join(', ')};" unless extra.empty?}".chomp(";")
  end

  private def check_gem(dir, gem, platform)
    spec = Gem::Package.new(File.join(dir, gem)).spec
    found = [spec.name, spec.version.to_s, spec.platform.to_s]
    raise Refusal, "#{gem} holds #{found.join(' ')}, not lota #{version} #{platform}" unless found == ["lota", version, platform]

    recorded = File.read(File.join(dir, "#{gem}.sha256")).split.first
    actual = sha256(dir, gem)
    raise Refusal, "#{gem} has SHA-256 #{actual}, not the #{recorded} its delivery verified" unless actual == recorded
  end

  private def sha256(dir, gem)
    Digest::SHA256.file(File.join(dir, gem)).hexdigest
  end

  private def git(*arguments)
    output, status = Open3.capture2e("git", *arguments, chdir: @root)
    raise Refusal, "git #{arguments.join(' ')} failed:\n#{output}" unless status.success?

    output
  end

  private def read(path)
    File.read(File.join(@root, path))
  end

  private def write(path, content)
    File.write(File.join(@root, path), content)
  end
end
