# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/restart"
require "tmpdir"

# A game that restarts in the same process starts again with what it
# defined taken away, as LÖVE's next run starts with a fresh Lua state.
# Each test loads a game's file from a folder of its own, as Lota::Boot
# loads main.rb, and restores the snapshot taken before it.
class RestartSnapshotTest < Minitest::Test
  def setup
    super
    @directory = Dir.mktmpdir("lota-snapshot-test")
    $LOAD_PATH.unshift(@directory)
  end

  def teardown
    $LOAD_PATH.delete(@directory)
    FileUtils.remove_entry(@directory)
    super
  end

  # Writes +code+ as the game's file +name+ and requires it.
  def load_game(code, name: "game_file")
    File.write(File.join(@directory, "#{name}.rb"), code)
    require name
  end

  def test_the_constants_methods_and_files_the_game_defined_go
    snapshot = Lota::Restart::Snapshot.new
    load_game(<<~RUBY)
      class SnapshotTestPlayer; end
      SNAPSHOT_TEST_SPEED = 3
      module Lota
        class SnapshotTestEnemy; end
      end
      def snapshot_test_helper = 1
    RUBY

    snapshot.restore(@directory)

    refute Object.const_defined?(:SnapshotTestPlayer)
    refute Object.const_defined?(:SNAPSHOT_TEST_SPEED)
    refute Lota.const_defined?(:SnapshotTestEnemy, false)
    refute Object.private_method_defined?(:snapshot_test_helper)
    assert require("game_file"), "the game's file loads again"
    snapshot.restore(@directory)
  end

  def test_the_callbacks_and_instance_variables_the_game_set_on_lota_go_back
    Lota.define_singleton_method(:snapshot_test_kept) { :lota }
    snapshot = Lota::Restart::Snapshot.new
    load_game(<<~RUBY)
      def Lota.snapshot_test_draw = :game
      def Lota.snapshot_test_kept = :game
      Lota.instance_variable_set(:@snapshot_test_level, 2)
    RUBY

    snapshot.restore(@directory)

    refute_respond_to Lota, :snapshot_test_draw
    assert_equal :lota, Lota.snapshot_test_kept, "a callback Lota had before is put back"
    refute Lota.instance_variable_defined?(:@snapshot_test_level)
  ensure
    Lota.singleton_class.remove_method(:snapshot_test_kept)
  end

  def test_the_games_globals_are_cleared
    snapshot = Lota::Restart::Snapshot.new
    load_game("$snapshot_test_score = 10\n")

    snapshot.restore(@directory)
    # This file names no global of the game's, which Ruby would make as it
    # read the file, before the snapshot.
    load_game("SNAPSHOT_TEST_SEEN = [$snapshot_test_score]\n", name: "reader")

    assert_equal [nil], Object.const_get(:SNAPSHOT_TEST_SEEN)
  ensure
    snapshot&.restore(@directory)
  end

  def test_what_was_defined_elsewhere_stays
    snapshot = Lota::Restart::Snapshot.new
    Object.const_set(:SnapshotTestElsewhere, 1)

    snapshot.restore(@directory)

    assert_equal 1, Object.const_get(:SnapshotTestElsewhere)
  ensure
    Object.__send__(:remove_const, :SnapshotTestElsewhere)
  end
end
