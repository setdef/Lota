# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require "fileutils"

# Lota::Filesystem's save directory and the files in it, through LÖVE's
# PhysicsFS filesystem. The tests run in a home of their own
# (test/test_helper.rb), so the save directory is under it, and each test
# saves under an identity of its own, which it puts back afterward.
class SaveDirectoryTest < Minitest::Test
  IDENTITY = "lota-filesystem-test"

  def setup
    EngineHelper.open_window
    @identity = Lota::Filesystem.identity
    Lota::Filesystem.identity = IDENTITY
  end

  def teardown
    FileUtils.rm_rf(save_directory)
    Lota::Filesystem.identity = @identity
  end

  # Where LÖVE's getFullCommonPath puts the save directory of a game that
  # is not fused (physfs/Filesystem.cpp:608-616), with Lota's folder in
  # place of LÖVE's (ADR 003, section 8).
  def save_directory
    File.join(File.realpath(ENV.fetch("CFFIXED_USER_HOME")), "Library/Application Support/Lota", IDENTITY)
  end

  # Writes +contents+ to +name+ in the save directory, as an earlier run
  # of the game would have saved it, and names the save directory again,
  # as the next run does when it starts: LÖVE mounts a save directory that
  # exists when it is named, and one that does not only when the game first
  # writes (physfs/Filesystem.cpp:226-236 and 357-376).
  def saved(name, contents)
    path = File.join(save_directory, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, contents)
    Lota::Filesystem.identity = IDENTITY
    path
  end

  def test_a_game_that_is_not_fused_saves_in_a_lota_folder_under_its_identity
    refute_predicate Lota::Filesystem, :fused?
    assert_equal IDENTITY, Lota::Filesystem.identity
    assert_equal save_directory, Lota::Filesystem.save_directory
  end

  def test_an_identity_takes_whether_saves_come_after_the_game_folder
    Lota::Filesystem.identity = "#{IDENTITY}-appended", true

    assert_equal "#{IDENTITY}-appended", Lota::Filesystem.identity
    assert Lota::Filesystem.save_directory.end_with?("/Lota/#{IDENTITY}-appended")
  end

  # w_setIdentity raises when Filesystem::setIdentity refuses an empty name
  # (wrap_Filesystem.cpp:80-89, physfs/Filesystem.cpp:184-185).
  def test_an_empty_identity_cannot_name_the_save_directory
    error = assert_raises(RuntimeError) { Lota::Filesystem.identity = "" }

    assert_equal "Could not set write directory.", error.message
    assert_equal IDENTITY, Lota::Filesystem.identity
  end

  def test_a_directory_is_made_in_the_save_directory_and_removed_when_empty
    assert Lota::Filesystem.create_directory("replays/2026")
    assert File.directory?(File.join(save_directory, "replays/2026"))

    refute Lota::Filesystem.remove("replays")
    assert Lota::Filesystem.remove("replays/2026")
    assert Lota::Filesystem.remove("replays")
    refute File.exist?(File.join(save_directory, "replays"))
  end

  def test_removing_what_is_not_there_fails
    Lota::Filesystem.create_directory("")

    refute Lota::Filesystem.remove("nothing.txt")
  end

  def test_a_saved_file_is_removed
    path = saved("scores.txt", "1\n")

    assert Lota::Filesystem.remove("scores.txt")
    refute File.exist?(path)
  end

  # w_File_lines_i (wrap_File.cpp:241-347) takes "\n" and a "\r" before it
  # off each line, and gives the text after the last "\n" as a line of its
  # own, which an empty last line is not.
  def test_lines_split_at_newlines_without_their_endings
    saved("settings.txt", "10\r\n6\n\nlast")

    assert_equal ["10", "6", "", "last"], Lota::Filesystem.lines("settings.txt").to_a
  end

  def test_lines_end_with_the_last_newline
    saved("settings.txt", "10\n6\n")

    assert_equal %w[10 6], Lota::Filesystem.lines("settings.txt").to_a
  end

  # LÖVE reads a kilobyte at a time until it has a whole line.
  def test_a_line_longer_than_a_read_is_whole
    long = "x" * 2500
    saved("long.txt", "#{long}\nshort")

    assert_equal [long, "short"], Lota::Filesystem.lines("long.txt").to_a
  end

  def test_lines_go_to_a_block_and_return_nil
    saved("settings.txt", "a\nb")
    seen = []

    assert_nil(Lota::Filesystem.lines("settings.txt") { |line| seen << line })
    assert_equal %w[a b], seen
  end

  # w_lines opens the file when it is called, through luax_catchexcept
  # (wrap_Filesystem.cpp:727-744), and the file closes once its last line
  # is read, after which the iterator raises (wrap_File.cpp:252-254).
  def test_lines_open_the_file_at_once_and_read_it_once
    saved("settings.txt", "a\nb")
    lines = Lota::Filesystem.lines("settings.txt")
    File.delete(File.join(save_directory, "settings.txt"))

    assert_equal %w[a b], lines.to_a
    error = assert_raises(RuntimeError) { lines.to_a }
    assert_equal "File needs to stay in read mode.", error.message
    error = assert_raises(RuntimeError) { Lota::Filesystem.lines("settings.txt") }
    assert_equal "Could not open file settings.txt. Does not exist.", error.message
  end

  # The game's folder is searched too: the tests' is test/lovetest, whose
  # resources are Lövetest's.
  def test_lines_read_a_file_in_the_game_folder_when_none_was_saved
    lines = Lota::Filesystem.lines("resources/test.txt").to_a

    assert_equal ["helloworld"], lines
  end
end
