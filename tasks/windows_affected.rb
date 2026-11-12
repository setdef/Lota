# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"

# Whether a range of commits can change Lota on Windows, for a contributor
# deciding whether to run the Windows checks (.github/windows_prepush.sh)
# before pushing, since CI runs them after.
#
# A range can when it changes the native code, the files that pin Lota's
# dependencies, or anything of Windows' own, or when a path it changes or
# a line it adds or removes names Windows, MinGW, Win32, or a DLL, in a
# file that is not prose. Any other change behaves on Windows as it does
# on Linux and macOS, where the gate checks it.
module WindowsAffected
  # Raised when git cannot read the range.
  class Failure < StandardError; end

  # What names Windows in a path or a line.
  WORDS = /windows|mingw|win32|\.dll/i

  # Prose, which can name Windows without changing how Lota builds or
  # runs there: the documentation, Markdown and RDoc files, the changelog,
  # and the license texts. Only the clauses that match names skip it.
  PROSE = %r{\A(?:doc/|LICENSES/|LICENSE\z|CHANGELOG)|\.(?:md|rdoc)\z}

  # The files that pin Lota's dependencies.
  DEPENDENCIES = %w[Gemfile Gemfile.lock lota.gemspec mise.toml].freeze

  # Each clause a changed path can meet, by the name the answer gives it.
  CLAUSES = {
    "ext/" => -> (path) { path.start_with?("ext/") },
    DEPENDENCIES.join(", ") => -> (path) { DEPENDENCIES.include?(path) },
    "tasks/windows*" => -> (path) { path.start_with?("tasks/windows") },
    ".github/windows*" => -> (path) { path.start_with?(".github/windows") },
    "test/native/windows*" => -> (path) { path.start_with?("test/native/windows") },
    "a path matching #{WORDS.source}" => -> (path) { WORDS.match?(path) && !PROSE.match?(path) },
  }.freeze

  # The clause a change met, and the path that met it.
  class Verdict < Data.define(:clause, :path)
    # The verdict as words.
    def to_s = "#{clause} (#{path})"
  end

  # The Verdict for +changes+ (each changed path, with the lines the range
  # adds or removes there), or nil when they cannot change Lota on Windows.
  # The path clauses come first, in CLAUSES' order, then the lines.
  def self.verdict(changes)
    CLAUSES.each do |clause, meets|
      path = changes.each_key.find(&meets)
      return Verdict.new(clause:, path:) if path
    end
    path, = changes.find { |path, lines| !PROSE.match?(path) && lines.any? { |line| WORDS.match?(line) } }
    Verdict.new(clause: "a changed line matching #{WORDS.source}", path:) if path
  end

  # Prints the answer for +verdict+ about +range+ to +out+, and returns the
  # task's exit status: 0 when the range can change Lota on Windows, 1 when
  # it cannot.
  def self.answer(verdict, range, out: $stdout)
    unless verdict
      out.puts "windows:affected: #{range} cannot change Lota on Windows"
      return 1
    end

    out.puts "windows:affected: #{range} can change Lota on Windows: #{verdict}"
    0
  end

  # The paths the commits of +range+ (OLD..NEW, as git takes it) change in
  # the repository at +root+ since they left OLD, each with the lines they
  # add or remove.
  def self.changes(root, range)
    old, new = range.split(/\.{2,3}/, 2)
    since = "#{old}...#{new || 'HEAD'}"
    names = git(root, "diff", "--name-only", "--no-renames", "-z", since, range:)
    changes = names.split("\0").to_h { |path| [path, []] }
    changed_lines(git(root, "diff", "--no-color", "--no-ext-diff", "--no-renames", "--unified=0", since, range:))
      .each { |path, lines| (changes[path] ||= []).concat(lines) }
    changes
  end

  # The lines a unified +diff+ adds or removes, by the path they are in.
  def self.changed_lines(diff)
    path = nil
    diff.b.each_line.with_object(Hash.new { |hash, key| hash[key] = [] }) do |line, lines|
      if (header = line[%r{\A(?:---|\+\+\+) [ab]/(.*?)\n?\z}, 1])
        path = header.dup.force_encoding(Encoding::UTF_8)
      elsif line.start_with?("+", "-") && !line.start_with?("+++ ", "--- ")
        lines[path] << line[1..].chomp.force_encoding(Encoding::UTF_8) if path
      end
    end
  end

  private_class_method def self.git(root, *, range:)
    output, error, status = Open3.capture3("git", "-c", "core.quotePath=false", *, chdir: root)
    raise Failure, "git cannot read #{range}: #{error.strip}" unless status.success?

    output
  end
end
