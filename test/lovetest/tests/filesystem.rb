# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.filesystem tests (vendor/love/testing/tests/
# filesystem.lua), translated to Ruby by ADR 001's rules, for the functions
# Lota binds. Like the graphics tests, they run in the test suite's own
# process (test/lovetest/filesystem_test.rb) and under lota run
# (test/lovetest/game). The tests that write files write them to the
# runner's save directory, in the test's own home (test/test_helper.rb).
class FilesystemTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.filesystem.getIdentity and
  # love.test.filesystem.setIdentity (vendor/love/testing/tests/
  # filesystem.lua:212-219 and 514-521): getIdentity becomes identity
  # (rule 3), and setIdentity the writer identity= (rule 5).
  def test_get_identity
    # check setting identity matches
    original = Lota::Filesystem.identity
    Lota::Filesystem.identity = "lover"
    assert_equal("lover", Lota::Filesystem.identity, "check identity matches")
    # put back to original value
    Lota::Filesystem.identity = original
  end

  def test_set_identity
    # check setting identity val is returned
    original = Lota::Filesystem.identity
    Lota::Filesystem.identity = "lover"
    assert_equal("lover", Lota::Filesystem.identity, "check indentity value")
    # return value to original
    Lota::Filesystem.identity = original
  end

  # Translated to Ruby from love.test.filesystem.createDirectory
  # (filesystem.lua:139-150): createDirectory becomes create_directory
  # (rule 13), and getInfo info (rule 3), with its file type a symbol
  # (rule 9).
  def test_create_directory
    # try creating a dir + subdir and check both exist
    success = Lota::Filesystem.create_directory("foo/bar")
    refute_equal(false, success, "check success")
    refute_equal(nil, Lota::Filesystem.info("foo", :directory), "check directory created")
    refute_equal(nil, Lota::Filesystem.info("foo/bar", :directory), "check subdirectory created")
    # cleanup
    Lota::Filesystem.remove("foo/bar")
    Lota::Filesystem.remove("foo")
  end

  # Translated to Ruby from love.test.filesystem.getInfo
  # (filesystem.lua:279-293): getInfo becomes info (rule 3), and its table
  # a frozen Info, whose fields keep LÖVE's names (rule 10).
  def test_get_info
    # create a dir and subdir with a file
    Lota::Filesystem.create_directory("foo/bar")
    Lota::Filesystem.write("foo/bar/file2.txt", "file2")
    # check getinfo returns the correct values
    assert_nil(Lota::Filesystem.info("foo/bar/file2.txt", :directory), "check not directory")
    refute_equal(nil, Lota::Filesystem.info("foo/bar/file2.txt"), "check info not nil")
    assert_equal(Lota::Filesystem.info("foo/bar/file2.txt").size, 5, "check info size match")
    assert_false(Lota::Filesystem.info("foo/bar/file2.txt").readonly, "check readonly")
    # @TODO test modified timestamp from info.modtime?
    # cleanup
    Lota::Filesystem.remove("foo/bar/file2.txt")
    Lota::Filesystem.remove("foo/bar")
    Lota::Filesystem.remove("foo")
  end

  # Translated to Ruby from love.test.filesystem.lines
  # (filesystem.lua:304-316): the iterator for Lua's for becomes an
  # Enumerator (rule 15), and string.find's nil for no match Ruby's
  # String#index. Minitest refuses assert_equal with nil, so Lua's
  # assertEquals(nil, ...) becomes assert_nil.
  def test_lines
    # check lines returns the 3 lines expected
    Lota::Filesystem.write("file.txt", "line1\nline2\nline3")
    linenum = 1
    Lota::Filesystem.lines("file.txt").each do |line|
      assert_equal("line#{linenum}", line, "check line matches")
      # also check it removes newlines like the docs says it does
      assert_nil(line.index("\n"), "check newline removed")
      linenum += 1
    end
    # cleanup
    Lota::Filesystem.remove("file.txt")
  end

  # Translated to Ruby from love.test.filesystem.read
  # (filesystem.lua:475-486): its two results become an Array (rule 4).
  def test_read
    # check reading a full file
    content, size = Lota::Filesystem.read("resources/test.txt")
    refute_equal(nil, content, "check not nil")
    assert_equal("helloworld", content, "check content match")
    assert_equal(10, size, "check size match")
    # check reading partial file
    content, size = Lota::Filesystem.read("resources/test.txt", 5)
    refute_equal(nil, content, "check not nil")
    assert_equal("hello", content, "check content match")
    assert_equal(5, size, "check size match")
  end

  # Translated to Ruby from love.test.filesystem.remove
  # (filesystem.lua:490-501).
  def test_remove
    # create a dir + subdir with a file
    Lota::Filesystem.create_directory("foo/bar")
    Lota::Filesystem.write("foo/bar/file2.txt", "helloworld")
    # check removing files + dirs (should fail to remove dir if file inside)
    assert_false(Lota::Filesystem.remove("foo"), "check fail when file inside")
    assert_false(Lota::Filesystem.remove("foo/bar"), "check fail when file inside")
    assert_true(Lota::Filesystem.remove("foo/bar/file2.txt"), "check file removed")
    assert_true(Lota::Filesystem.remove("foo/bar"), "check subdirectory removed")
    assert_true(Lota::Filesystem.remove("foo"), "check directory removed")
    # cleanup not needed here hopefully...
  end

  # Translated to Ruby from love.test.filesystem.write
  # (filesystem.lua:558-571): where Lua compares read's first result,
  # Ruby takes .first (rule 4).
  def test_write
    # check writing a bunch of files matches whats read back
    Lota::Filesystem.write("test1.txt", "helloworld")
    Lota::Filesystem.write("test2.txt", "helloworld", 10)
    Lota::Filesystem.write("test3.txt", "helloworld", 5)
    assert_equal("helloworld", Lota::Filesystem.read("test1.txt").first, "check read file")
    assert_equal("helloworld", Lota::Filesystem.read("test2.txt").first, "check read all")
    assert_equal("hello", Lota::Filesystem.read("test3.txt").first, "check read partial")
    # cleanup
    Lota::Filesystem.remove("test1.txt")
    Lota::Filesystem.remove("test2.txt")
    Lota::Filesystem.remove("test3.txt")
  end

  # Translated to Ruby from love.test.filesystem.getSaveDirectory
  # (filesystem.lua:273-275): getSaveDirectory becomes save_directory
  # (rule 3).
  def test_get_save_directory
    assert_not_nil(Lota::Filesystem.save_directory)
  end

  # Translated to Ruby from love.test.filesystem.isFused
  # (filesystem.lua:297-300): isFused becomes fused? (rule 8).
  def test_is_fused
    # kinda assuming you'd run the testsuite in a non-fused game
    assert_equal(Lota::Filesystem.fused?, false, "check not fused")
  end
  # SPDX-SnippetEnd
end
