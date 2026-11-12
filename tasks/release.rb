# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "date"
require "digest"
require "fileutils"
require "open3"
require "rubygems/package"
require_relative "changelog"

# A release of Lota: a tag on a commit CI proved, its notes, and one
# precompiled gem for each platform, published on GitHub
# (doc/contributors/releasing.md).
#
# A release picks a commit and writes nothing back first: the version is
# decided from the tags and the commit's CHANGELOG.md, stamped into the
# gems as CI builds them (#stamp), and the dated section reaches trunk
# afterward (#record). Everything a release needs is read from git at the
# commits and tags it names, never from the working tree's state, so a
# commit tagged after trunk moved on releases what it holds.
class Release
  # Raised when a release cannot be made as asked.
  class Refusal < StandardError; end

  # The file that holds Lota::VERSION.
  VERSION_FILE = "lib/lota/version.rb"

  # The changelog, in Keep a Changelog's format.
  CHANGELOG = "CHANGELOG.md"

  # The lockfile, which records the version of the gem it is the bundle of.
  LOCKFILE = "Gemfile.lock"

  # The file whose first ruby = "..." line pins the Ruby CI and
  # contributors use.
  TOOLS = "mise.toml"

  # A version a release can have: MAJOR.MINOR.PATCH, nothing more.
  NUMBER = /\A\d+\.\d+\.\d+\z/

  # A release tag: v and a NUMBER.
  TAG = /\Av\d+\.\d+\.\d+\z/

  # Lota::VERSION's assignment in VERSION_FILE.
  ASSIGNMENT = /^(\s*VERSION = ")([^"]*)(")$/

  # The Ruby TOOLS pins, as ruby/setup-ruby reads it.
  RUBY = /^ruby = "([^"]+)"/

  # The file of checksums each release carries, in sha256sum's format.
  CHECKSUMS = "SHA256SUMS"

  # [root] The repository.
  def initialize(root:)
    @root = root
  end

  # The version VERSION_FILE gives in the working tree.
  def version
    match = read(VERSION_FILE).match(ASSIGNMENT)
    raise Refusal, "#{VERSION_FILE} assigns no VERSION" unless match

    match[2]
  end

  # Sets +number+ as the version in VERSION_FILE and LOCKFILE of the
  # working tree, as a release's gems are built, and commits nothing.
  def stamp(number)
    raise Refusal, "#{number} is not a version, which is MAJOR.MINOR.PATCH" unless number.match?(NUMBER)

    current = version
    pattern = /^(\s+lota \()#{Regexp.escape(current)}(\))$/
    lockfile = binread(LOCKFILE)
    raise Refusal, "#{LOCKFILE} records no lota #{current}" unless lockfile.match?(pattern)

    binwrite(LOCKFILE, lockfile.gsub(pattern) { "#{Regexp.last_match(1)}#{number}#{Regexp.last_match(2)}" })
    binwrite(VERSION_FILE, binread(VERSION_FILE).sub(ASSIGNMENT) { "#{Regexp.last_match(1)}#{number}#{Regexp.last_match(3)}" })
  end

  # The repository's release tags, oldest version first.
  def tags
    sorted(git("tag", "--list", "v*").split)
  end

  # The commit +tag+ points at, or nil when there is no such tag.
  def tagged(tag)
    output, status = Open3.capture2("git", "rev-parse", "--quiet", "--verify", "refs/tags/#{tag}^{commit}", chdir: @root)
    status.success? ? output.chomp : nil
  end

  # The full name of the commit +ref+ names.
  def commit(ref)
    git("rev-parse", "--verify", "#{ref}^{commit}").chomp
  end

  # The release tags on +sha+ or on a commit after it, oldest first: the
  # releases that already hold it.
  def covering(sha)
    sorted(git("tag", "--list", "v*", "--contains", sha).split)
  end

  # The newest release tag on a commit before +sha+, or nil: the release
  # whose notes +sha+'s notes follow. Tags on +sha+ itself are not before
  # it.
  def previous(sha)
    sha = commit(sha)
    sorted(git("tag", "--list", "v*", "--merged", sha).split).reject { |tag| tagged(tag) == sha }.last
  end

  # The file at +path+ as commit +ref+ has it, or nil when it has none.
  def show(ref, path)
    output, status = Open3.capture2("git", "show", "#{ref}:#{path}", chdir: @root, binmode: true)
    status.success? ? output.force_encoding(Encoding::UTF_8) : nil
  end

  # The CHANGELOG.md entries +sha+ adds since the release before it: those
  # of its [Unreleased] that the previous release's [Unreleased] did not
  # list. A commit tagged before the last release's dated section reached
  # trunk still lists that release's entries, and they are not its own.
  def added(sha)
    previous = previous(sha)
    entries = changelog(sha).unreleased
    previous ? Changelog.added(entries, changelog(previous).unreleased) : entries
  end

  # The notes of a release of +sha+: what it adds, as a section's body.
  def notes(sha)
    entries = added(sha)
    raise Refusal, "#{CHANGELOG} at #{sha[0, 12]} lists nothing new since #{previous(sha) || 'the start'}" if entries.empty?

    Changelog.body(entries)
  end

  # The Ruby TOOLS pins at +ref+.
  def ruby(ref)
    show(ref, TOOLS).to_s[RUBY, 1] or raise Refusal, "#{TOOLS} at #{ref} pins no Ruby"
  end

  # The day +tag+ was made, in UTC.
  def date(tag)
    seconds = git("for-each-ref", "--format=%(creatordate:unix)", "refs/tags/#{tag}").strip
    raise Refusal, "there is no tag #{tag}" if seconds.empty?

    Time.at(Integer(seconds)).utc.to_date
  end

  # The working tree's CHANGELOG.md with a dated section for each release
  # tag it has none for, oldest first, each listing what its commit added
  # and taking exactly that out of [Unreleased]. Returns the text and the
  # versions recorded. It reads only the tags, so it gives the same text
  # however often it runs, and puts back any section a failed push left
  # out.
  def record
    log = Changelog.new(read(CHANGELOG))
    recorded = tags.filter_map do |tag|
      number = tag.delete_prefix("v")
      next if log.released(number)

      log = log.record(number, date(tag), added(tag), changelog(tag).unreleased)
      number
    end
    [log.to_s, recorded]
  end

  # How the working tree's CHANGELOG.md disagrees with the tags: for each
  # release tag, a missing dated section, or one that lists other than
  # what the release added. A section CI did not write, from before
  # releases were recorded, must match the tag's own section word for
  # word.
  def check_changelog
    log = Changelog.new(read(CHANGELOG))
    tags.filter_map do |tag|
      number = tag.delete_prefix("v")
      own = changelog(tag).released_text(number)
      if !log.released(number)
        "#{CHANGELOG} has no section for #{number}, which #{tag} released"
      elsif own ? log.released_text(number) != own : sorted_entries(log.released(number)) != sorted_entries(added(tag))
        "#{CHANGELOG}'s section for #{number} lists other than #{tag} released"
      end
    end
  end

  # Checks that +dir+ holds exactly one gem of +number+ for each of
  # +platforms+, each the gem its <tt>.sha256</tt> file names by its
  # SHA-256, and replaces those files with one SHA256SUMS for them all.
  # Returns the gems' names.
  def assemble(dir, number, platforms)
    expected = platforms.map { |platform| "lota-#{number}-#{platform}.gem" }
    check_contents(dir, expected)
    platforms.zip(expected).each { |platform, gem| check_gem(dir, gem, number, platform) }
    File.write(File.join(dir, CHECKSUMS), expected.sort.map { |gem| "#{sha256(dir, gem)}  #{gem}\n" }.join)
    expected.each { |gem| File.delete(File.join(dir, "#{gem}.sha256")) }
    expected
  end

  # Writes the files under +path+ as they are at +ref+ into +dir+.
  def export(ref, path, dir)
    git("ls-tree", "-r", "--name-only", ref, "--", path).lines(chomp: true).each do |file|
      target = File.join(dir, file)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, git("show", "#{ref}:#{file}"))
    end
  end

  private def changelog(ref)
    text = show(ref, CHANGELOG) or raise Refusal, "#{ref} has no #{CHANGELOG}"
    Changelog.new(text)
  end

  private def sorted_entries(entries)
    entries.sort_by { |entry| [entry.heading.to_s, entry.text] }
  end

  # The release tags among +names+, oldest version first.
  private def sorted(names)
    names.grep(TAG).sort_by { |tag| Gem::Version.new(tag.delete_prefix("v")) }
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

  private def check_gem(dir, gem, number, platform)
    spec = Gem::Package.new(File.join(dir, gem)).spec
    found = [spec.name, spec.version.to_s, spec.platform.to_s]
    raise Refusal, "#{gem} holds #{found.join(' ')}, not lota #{number} #{platform}" unless found == ["lota", number, platform]

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
    File.read(File.join(@root, path), encoding: Encoding::UTF_8)
  end

  private def binread(path)
    File.binread(File.join(@root, path))
  end

  # Writes bytes as they are, so that Windows' Ruby, which writes a text
  # file's newlines as CRLF, leaves the file's LFs alone.
  private def binwrite(path, content)
    File.binwrite(File.join(@root, path), content)
  end
end
