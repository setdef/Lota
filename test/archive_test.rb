# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/archive"

# Which entries of a .lota Lota refuses to unpack, and where it unpacks
# one (ADR 016). That lota run unpacks an archive through the engine's
# filesystem and plays it is test/native/lota_run_test.rb's to prove, in
# a process of its own.
class ArchiveTest < Minitest::Test
  ARCHIVE = File.expand_path("games/sample.lota")

  def archive
    Lota::Archive.new("games/sample.lota")
  end

  # The message Archive#check raises for +entries+, or nil.
  def refusal(*entries, destination: "/cache/game", path_limit: false)
    archive.check(entries.map { |entry| entry.is_a?(Array) ? entry : [entry, :file] }, destination, path_limit:)
    nil
  rescue Lota::Archive::Refused => e
    e.message
  end

  def assert_refused(reason, *entries, **)
    message = refusal(*entries, **)

    refute_nil message, "#{entries.inspect} should be refused"
    assert_match(/\ACannot play the game in '#{Regexp.escape(ARCHIVE)}': its entry ".*" #{Regexp.escape(reason)}/, message)
    message
  end

  def test_the_path_is_absolute
    assert_equal ARCHIVE, archive.path
  end

  def test_a_game_of_files_and_folders_is_unpacked
    assert_nil refusal(["data", :directory], "data/level 1.txt", "main.rb", "conf.rb", "lib/ünïcode.rb",
      "a.b.c", "bundle.rb", "so", "CONSOLE.rb", "COM10", ".hidden")
  end

  def test_an_entry_that_lands_outside_the_folder_is_refused
    ["..", "a/../../b.rb", "./main.rb", "a//b.rb", "/abs.rb", "a/"].each do |name|
      assert_includes assert_refused("would land outside the game's folder", name), name.inspect
    end
  end

  def test_entries_that_differ_only_by_case_are_refused_naming_both
    message = assert_refused("has the same name as \"Main.rb\" but for case", "Main.rb", "main.rb")

    assert_includes message, "its entry \"main.rb\""
    assert_refused("has the same name as \"Data\" but for case", ["Data", :directory], ["data", :directory])
    assert_refused("has the same name as \"STRASSE.rb\" but for case", "STRASSE.rb", "straße.rb")
    assert_refused("has the same name as \"caf\u00e9.rb\" but for case", "caf\u00e9.rb", "cafe\u0301.rb")
  end

  def test_a_character_windows_forbids_is_refused
    ["a<b", "a>b", "a:b", "a\"b", "a|b", "a?b", "a*b", "a\\b.rb", "dir\\..\\..\\x", "tab\there", "bell\a", "nul\0"].each do |name|
      assert_refused("has a character Windows forbids in a name", name)
    end
  end

  def test_a_name_ending_in_a_dot_or_space_is_refused
    ["main.rb.", "main.rb ", "folder./main.rb", "folder /main.rb"].each do |name|
      assert_refused("has a name ending in a dot or a space, which Windows drops", name)
    end
  end

  def test_a_name_windows_reserves_for_a_device_is_refused
    %w[CON prn aux.txt NUL.rb COM1 com9.dat LPT1 lpt9 COM¹ data/con/x.rb].each do |name|
      assert_refused("has a name Windows reserves for a device", name)
    end
  end

  def test_native_code_is_refused
    %w[ext.so lib/ext.bundle win.dll mac.dylib LIB.DLL libfoo.so.1.2].each do |name|
      assert_refused("is native code, which a game in one file cannot hold", name)
    end
    assert_nil refusal(["folder.so", :directory])
  end

  def test_a_symbolic_link_or_an_entry_that_cannot_be_read_is_refused
    assert_refused("is a symbolic link, which Lota does not unpack", ["link.rb", :symlink])
    assert_refused("cannot be read from the archive", ["odd", :other])
    assert_refused("cannot be read from the archive", ["odd", nil])
  end

  def test_a_name_that_is_not_utf_8_is_refused
    assert_refused("is not valid UTF-8, which Windows cannot name", (+"bad\xFF.rb").force_encoding(Encoding::UTF_8))
  end

  # MAX_PATH less its null for a file, and less 12 more for a folder
  # (CreateDirectoryW), counted in UTF-16 code units.
  def test_a_path_longer_than_windows_allows_is_refused_where_the_limit_applies
    destination = "C:/Users/player/AppData/Local/Lota/Cache/games/0123456789abcdef/game"
    room = 259 - destination.length - 1

    assert_nil refusal("a" * room, destination:, path_limit: true)
    message = assert_refused("makes a path of 260 characters, longer than the 259 Windows allows where long paths are " \
      "not enabled", "a" * (room + 1), destination:, path_limit: true)

    assert_includes message, "a" * (room + 1)
    assert_nil refusal("a" * (room + 1), destination:, path_limit: false)
    assert_nil refusal(["d" * (room - 12), :directory], destination:, path_limit: true)
    assert_refused("makes a path of 248 characters, longer than the 247", ["d" * (room - 11), :directory],
      destination:, path_limit: true)
    assert_refused("makes a path of 260 characters", "\u{1F3AE}#{'a' * (room - 1)}", destination:, path_limit: true)
  end

  def test_the_first_entry_refused_is_named
    message = refusal("main.rb", "ext.so", "CON")

    assert_includes message, "its entry \"ext.so\""
  end

  def test_the_cache_is_in_each_systems_folder_for_caches
    assert_equal "/home/you/.cache/lota/games", Lota::Archive.cache_directory("Linux", {}, "/home/you/")
    assert_equal "/xdg/lota/games", Lota::Archive.cache_directory("Linux", { "XDG_CACHE_HOME" => "/xdg" }, "/home/you")
    assert_equal "/home/you/.cache/lota/games",
      Lota::Archive.cache_directory("Linux", { "XDG_CACHE_HOME" => "relative" }, "/home/you")
    assert_equal "/Users/you/Library/Caches/Lota/games", Lota::Archive.cache_directory("OS X", {}, "/Users/you/")
    assert_equal "C:/Users/you/AppData/Local/Lota/Cache/games",
      Lota::Archive.cache_directory("Windows", { "LOCALAPPDATA" => "C:\\Users\\you\\AppData\\Local" }, "C:/Users/you")
    assert_equal "C:/Users/you/AppData/Local/Lota/Cache/games", Lota::Archive.cache_directory("Windows", {}, "C:/Users/you/")
  end
end
