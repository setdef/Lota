# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/guard"

# Guard reads the files git tracks and reports each line that names a game
# that uses Lota or one particular agent, except in the files the list
# exempts.
#
# The tests that use the real list write its names in two parts (+named+),
# so that this file, which the lint also reads, does not hold them whole.
class GuardTest < Minitest::Test
  include TreeHelper

  LIST = <<~YAML
    games:
      - star hopper
      - pip em
      - bramble
    agents:
      - name: a robot
        pattern: 'robots?\\b'
      - name: an agent's identifier
        pattern: 'agent[ -]a?(?=[0-9a-f]*\\d)[0-9a-f]{8,}'
    exempt:
      - path: guard.yml
        reason: names what it forbids
      - path: kit/**
        reason: temporary
      - path: CHANGELOG.md
        reason: release notes
  YAML

  # Writes +files+ (path => content) and the list into a staged tree, and
  # returns the violations' lines.
  def lines(list: LIST, **files)
    in_tree do |dir|
      files.each { |path, content| write(dir, path, content) }
      write(dir, "guard.yml", list)
      git_stage(dir)
      Guard.new(root: dir, list: File.join(dir, "guard.yml")).violations.map(&:to_s)
    end
  end

  # A name, written in two parts.
  def named(first, second) = "#{first}#{second}"

  # Whether the real list finds a violation in a file that holds +text+.
  def real_violations(text)
    in_tree do |dir|
      write(dir, "a.md", "#{text}\n")
      git_stage(dir)
      Guard.new(root: dir).violations
    end
  end

  def test_a_tracked_file_that_names_a_game_fails_with_its_file_line_and_rule
    found = lines("docs/a.md" => "fine\nPlay Star Hopper now\n")

    assert_equal ["docs/a.md:2: names a game that uses Lota (star hopper): Play Star Hopper now"], found
  end

  def test_the_failure_message_names_the_file_line_and_the_rule
    in_tree do |dir|
      write(dir, "a.rb", "# star_hopper\n")
      write(dir, "guard.yml", LIST)
      git_stage(dir)
      message = Guard.new(root: dir, list: File.join(dir, "guard.yml")).report

      assert_includes message, "a.rb:1: names a game that uses Lota (star hopper)"
      assert_includes message, "guard.yml"
    end
  end

  def test_an_exempt_path_and_the_changelog_do_not_fail
    assert_empty lines("kit/run.ps1" => "star hopper\n", "CHANGELOG.md" => "- bramble\n")
  end

  def test_a_clean_tree_has_no_report
    in_tree do |dir|
      write(dir, "a.md", "nothing here\n")
      write(dir, "guard.yml", LIST)
      git_stage(dir)

      assert_nil Guard.new(root: dir, list: File.join(dir, "guard.yml")).report
    end
  end

  def test_the_list_decides_what_is_forbidden
    assert_empty lines("a.md" => "star hopper\n", :list => LIST.sub("  - star hopper\n", ""))
    refute_empty lines("a.md" => "wombat\n", :list => LIST.sub("  - bramble", "  - wombat"))
  end

  def test_the_list_decides_what_is_exempt
    assert_empty lines("other/a.md" => "bramble\n", :list => LIST.sub("kit/**", "other/**"))
  end

  def test_a_name_matches_with_any_separator_and_any_case
    ["star-hopper", "STAR_HOPPER", "starhopper", "Star Hopper"].each do |text|
      refute_empty lines("a.md" => "see #{text}\n"), text
    end
    ["pip em", "pip 'em", "pip ’em", "pip_em", "pipem"].each do |text|
      refute_empty lines("a.md" => "see #{text}.\n"), text
    end
  end

  def test_a_part_of_a_name_and_a_longer_word_are_not_matches
    [
      "hopper alone",
      "a star",
      "brambles",
      "unbramble",
      "bramble2",
      "pipe",
      "pip embedded",
      "bramblestar",
].each do |text|
      assert_empty lines("a.md" => "#{text}\n"), text
    end
  end

  def test_a_name_among_punctuation_and_constants_is_a_match
    refute_empty lines("a.rb" => "BRAMBLE_VERSION = 1\n")
    refute_empty lines("a.rb" => "path = 'bramble/x'\n")
    refute_empty lines("a.rb" => "(Bramble)\n")
  end

  def test_what_the_agent_patterns_match_is_what_the_list_says
    ["a robot did it", "the Robots", named("agent a1b2", "c3d4e5 found"), named("agent-", "0123abcd45")].each do |text|
      refute_empty lines("a.md" => "#{text}\n"), text
    end
    ["an agent skill", "coding agents", "agent deadbeef is not an id", "agent installation", "robotic"].each do |text|
      assert_empty lines("a.md" => "#{text}\n"), text
    end
  end

  def test_each_violation_on_a_line_and_in_a_file_is_reported
    found = lines("a.md" => "bramble and star hopper\nbramble\n", "b.md" => "a robot\n")

    assert_equal 4, found.size
    assert_equal %w[a.md a.md a.md b.md], found.map { |line| line.split(":").first }.sort
  end

  def test_untracked_binary_and_missing_files_are_skipped
    in_tree do |dir|
      write(dir, "guard.yml", LIST)
      write(dir, "image.png", "bramble\0bramble")
      write(dir, "removed.md", "bramble\n")
      git_stage(dir)
      File.delete(File.join(dir, "removed.md"))
      write(dir, "untracked.md", "bramble\n")

      assert_empty Guard.new(root: dir, list: File.join(dir, "guard.yml")).violations
    end
  end

  def test_the_real_list_guards_the_known_games_and_agents_and_explains_each_exemption
    config = YAML.safe_load_file(Guard::LIST)
    games = [named("dot pop", "per"), named("cro", "ss em"), named("deck", "builder"), named("to", "kra")]
    agents = [named("sub", "agent"), named("agent a1b2", "c3d4e5f6"), named("the Fle", "dge agent")]

    assert_equal games, config.fetch("games")
    assert(config.fetch("exempt").all? { |entry| entry.fetch("reason").size > 10 })
    assert_equal games.size, real_violations(games.join("\n")).map(&:rule).uniq.size
    assert_equal agents.size, real_violations(agents.join("\n")).map(&:rule).uniq.size
  end

  def test_the_real_list_matches_the_games_as_written_in_a_path_a_constant_and_a_sentence
    [
      named("Dot Pop", "per's"),
      named("DOT_POP", "PER_RUNS"),
      named("dotpop", "per-shot"),
      named("Cross ’", "em"),
      named("cross", "_em"),
      named("Deck", "builder."),
].each do |form|
      refute_empty real_violations(form), form
    end
  end

  def test_the_real_list_does_not_match_the_words_inside_others
    assert_empty real_violations("A popper and a cross embedded in tokras and deckbuilders and a dot pop.")
  end

  def test_the_tracked_tree_names_no_game_and_no_particular_agent
    assert_nil Guard.new(root: ROOT).report
  end
end
