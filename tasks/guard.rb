# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"
require "yaml"

# Keeps the games that use Lota, and particular agents, out of Lota's tracked
# files.
#
# Lota is a dependency of games, so nothing permanent in it may name or rely
# on one, as Fledge cannot depend on Lota. Agents come and go, so no file
# may point at one in particular. The list of what to keep out, and of the
# files the rule skips (each with its reason), is one file, tasks/guard.yml,
# so that a new game is one line.
#
# The files are those <tt>git ls-files</tt> lists, so a new file counts once
# it is staged. A word matches without regard to case and only as a whole:
# letters and digits on either side make it part of a longer word.
class Guard
  # The file the rule is read from.
  LIST = File.expand_path("guard.yml", __dir__)

  # One place a file breaks the rule: +rule+ names what was found.
  class Violation < Data.define(:file, :line, :rule, :text)
    # The line the gate prints.
    def to_s = "#{file}:#{line}: #{rule}: #{text.strip[0, 120]}"
  end

  # [root] The repository whose tracked files are read.
  # [list] The YAML file that holds the games, agent patterns, and exemptions.
  def initialize(root: Dir.pwd, list: LIST)
    @root = root
    @list = list
    config = YAML.safe_load_file(list)
    @exempt = config.fetch("exempt").map { |entry| entry.fetch("path") }
    @rules = game_rules(config.fetch("games")) + agent_rules(config.fetch("agents"))
  end

  # Every Violation in the tracked files that are not exempt.
  def violations
    files.flat_map { |file| scan(file) }
  end

  # The message a failing gate prints, or +nil+ when nothing was found.
  def report
    found = violations
    return if found.empty?

    "#{found.map(&:to_s).join("\n")}\n" \
      "#{found.size} place(s) break the rule that Lota's files name no game that uses Lota and no particular " \
      "agent; reword them, or, for temporary material, list the path under exempt: in #{File.basename(@list)}"
  end

  private def game_rules(names)
    names.map do |name|
      words = name.downcase.scan(/[a-z0-9]+/).map { |word| Regexp.escape(word) }
      [
        "names a game that uses Lota (#{name})",
        Regexp.new("(?<![a-z0-9])#{words.join("[ _'’-]*")}(?![a-z0-9])", Regexp::IGNORECASE),
      ]
    end
  end

  private def agent_rules(entries)
    entries.map do |entry|
      ["refers to #{entry.fetch('name')}", Regexp.new(entry.fetch("pattern"), Regexp::IGNORECASE)]
    end
  end

  private def files
    out, status = Open3.capture2("git", "ls-files", "-z", chdir: @root)
    raise "git ls-files failed in #{@root}" unless status.success?

    out.split("\0").reject { |file| exempt?(file) }
  end

  private def exempt?(file)
    @exempt.any? { |pattern| File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
  end

  private def scan(file)
    path = File.join(@root, file)
    return [] unless File.file?(path) && !File.symlink?(path)

    content = File.binread(path)
    return [] if content.include?("\0")

    content.force_encoding(Encoding::UTF_8).scrub.each_line.with_index(1).flat_map do |text, number|
      @rules.filter_map { |rule, pattern| Violation.new(file:, line: number, rule:, text:) if text.match?(pattern) }
    end
  end
end
