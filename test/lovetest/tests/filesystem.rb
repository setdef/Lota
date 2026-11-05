# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.filesystem tests (vendor/love/testing/tests/
# filesystem.lua), translated to Ruby by ADR 001's rules, all but that of
# love.filesystem.load, which loads a Lua chunk and has no Ruby
# translation yet. Like the graphics tests, they run in the test suite's
# own process (test/lovetest/filesystem_test.rb) and under lota run
# (test/lovetest/game). The tests that write files write them to the
# runner's save directory, in the test's own home (test/test_helper.rb).
class FilesystemTest < Lovetest::TestMethod
  # The types whose tests Lövetest names by the type
  # (love.test.filesystem.File and love.test.filesystem.FileData).
  TYPES = %w[File FileData].freeze

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.filesystem.File
  # (vendor/love/testing/tests/filesystem.lua:12-78): openFile becomes
  # open_file (rule 13) and its modes symbols (rule 9), as are File's
  # modes and buffer modes; the getters drop get (rule 3), and isOpen and
  # isEOF become open? and eof? (rule 8). Every method that returns
  # luax_ioError's nil and message on failure returns an Array on every
  # path (rule 4), so where Lua compares the first result, Ruby takes
  # .first; setBuffer returns whether it could, so it stays set_buffer
  # (rule 7). openFile's File comes first of its Array, as Lua's local
  # takes only the first result. The iterator lines returns is an
  # Enumerator (rule 15). Lua's type(size) == 'string' is size.is_a?(String),
  # and its numeric for loop Ruby's each over a Range.
  def test_file
    # setup a file to play with
    file1, = Lota::Filesystem.open_file("data.txt", :w)
    file1.write("helloworld")
    assert_object(file1)
    file1.close

    # test read mode
    file1.open(:r)
    assert_equal(:r, file1.mode.first, "check read mode")
    contents, size = file1.read
    assert_equal("helloworld", contents)
    assert_equal(10, size, "check file read")
    assert_equal(10, file1.size.first)
    _ok1, err1 = file1.write("hello")
    refute_equal(nil, err1, "check cant write in read mode")
    iterator = file1.lines
    refute_equal(nil, iterator, "check can read lines")
    assert_equal("data.txt", file1.filename, "check filename matches")
    file1.close

    # test write mode
    file1.open(:w)
    assert_equal(:w, file1.mode.first, "check write mode")
    contents, size = file1.read
    assert_nil(contents, "check cant read file in write mode")
    assert_equal(true, size.is_a?(String), "check err message shown")
    ok2, err2 = file1.write("helloworld")
    assert_true(ok2, "check file write")
    assert_nil(err2, "check no err writing")

    # test open/closing
    file1.open(:r)
    assert_true(file1.open?, "check file is open")
    file1.close
    assert_false(file1.open?, "check file gets closed")
    file1.close

    # test buffering and flushing
    file1.open(:w)
    ok3, _err3 = file1.set_buffer(:full, 10000)
    assert_true(ok3)
    assert_equal(:full, file1.buffer.first)
    file1.write("replacedcontent")
    file1.flush
    file1.close
    file1.open(:r)
    contents, size = file1.read
    assert_equal("replacedcontent", contents, "check buffered content was written")
    file1.close

    # loop through file data with seek/tell until EOF
    file1.open(:r)
    counter = 0
    (1..100).each do |i|
      file1.seek(i)
      assert_equal(i, file1.tell.first)
      if file1.eof? == true
        counter = i
        break
      end
    end
    assert_equal(counter, 15)
    file1.close
  end

  # Translated to Ruby from love.test.filesystem.FileData
  # (filesystem.lua:82-100): newFileData becomes FileData.new (rule 2),
  # getFilename, getExtension, getString, and getSize filename,
  # extension, string, and size (rule 3), and clone Ruby's clone, which
  # makes LÖVE's copy (ADR 001, section 7).
  def test_file_data
    # create new obj
    fdata = Lota::Filesystem::FileData.new("helloworld", "test.txt")
    assert_object(fdata)
    assert_equal("test.txt", fdata.filename)
    assert_equal("txt", fdata.extension)

    # check properties match expected
    assert_equal("helloworld", fdata.string, "check data string")
    assert_equal(10, fdata.size, "check data size")

    # check cloning the bytedata
    clonedfdata = fdata.clone
    assert_object(clonedfdata)
    assert_equal("helloworld", clonedfdata.string, "check cloned data")
    assert_equal(10, clonedfdata.size, "check cloned size")
  end

  # Translated to Ruby from love.test.filesystem.append
  # (filesystem.lua:111-128): append's results, and read's, are an Array
  # (rule 4).
  def test_append
    # create a new file to test with
    Lota::Filesystem.write("filesystem.append.txt", "foo")
    # try appending text and check new file contents/size matches
    success, message = Lota::Filesystem.append("filesystem.append.txt", "bar")
    refute_equal(false, success, "check success")
    assert_nil(message, "check no error msg")
    contents, size = Lota::Filesystem.read("filesystem.append.txt")
    assert_equal(contents, "foobar", "check file contents")
    assert_equal(size, 6, "check file size")
    # check appending a specific no. of bytes
    Lota::Filesystem.append("filesystem.append.txt", "foobarfoobarfoo", 6)
    contents, size = Lota::Filesystem.read("filesystem.append.txt")
    assert_equal(contents, "foobarfoobar", "check appended contents")
    assert_equal(size, 12, "check appended size")
    # cleanup
    Lota::Filesystem.remove("filesystem.append.txt")
  end

  # Translated to Ruby from love.test.filesystem.areSymlinksEnabled
  # (filesystem.lua:133-135): areSymlinksEnabled becomes symlinks_enabled?
  # (rule 8).
  def test_are_symlinks_enabled
    assert_not_nil(Lota::Filesystem.symlinks_enabled?)
  end

  # Translated to Ruby from love.test.filesystem.getAppdataDirectory,
  # love.test.filesystem.getSourceBaseDirectory,
  # love.test.filesystem.getUserDirectory, and
  # love.test.filesystem.getWorkingDirectory (filesystem.lua:153-155 and
  # 252-268): each getter drops get (rule 3).
  def test_get_appdata_directory
    assert_not_nil(Lota::Filesystem.appdata_directory)
  end

  def test_get_source_base_directory
    assert_not_nil(Lota::Filesystem.source_base_directory)
  end

  def test_get_user_directory
    assert_not_nil(Lota::Filesystem.user_directory)
  end

  def test_get_working_directory
    assert_not_nil(Lota::Filesystem.working_directory)
  end

  # Translated to Ruby from love.test.filesystem.getCRequirePath,
  # love.test.filesystem.setCRequirePath,
  # love.test.filesystem.getRequirePath, and
  # love.test.filesystem.setRequirePath (filesystem.lua:159-162, 237-240,
  # 505-510, and 525-531): getCRequirePath becomes c_require_path, the C
  # of C cut from nothing, a word of its own (rule 13), and getRequirePath
  # require_path (rule 3); their setters become the writers
  # c_require_path= and require_path= (rule 5).
  def test_get_c_require_path
    # check default value from documentation
    assert_equal("??", Lota::Filesystem.c_require_path, "check default value")
  end

  def test_set_c_require_path
    # check setting path val is returned
    Lota::Filesystem.c_require_path = "/??"
    assert_equal("/??", Lota::Filesystem.c_require_path, "check crequirepath value")
    Lota::Filesystem.c_require_path = "??"
  end

  def test_get_require_path
    assert_equal("?.lua;?/init.lua", Lota::Filesystem.require_path, "check default value")
  end

  def test_set_require_path
    # check setting path val is returned
    Lota::Filesystem.require_path = "?.lua;?/start.lua"
    assert_equal("?.lua;?/start.lua", Lota::Filesystem.require_path, "check require path")
    # reset to default
    Lota::Filesystem.require_path = "?.lua;?/init.lua"
  end

  # Translated to Ruby from love.test.filesystem.getDirectoryItems
  # (filesystem.lua:166-187): getDirectoryItems becomes directory_items
  # (rule 3), whose table is an Array, which each walks as Lua's ipairs
  # does, and the file type a symbol (rule 9).
  def test_get_directory_items
    # create a dir + subdir with 2 files
    Lota::Filesystem.create_directory("foo/bar")
    Lota::Filesystem.write("foo/file1.txt", "file1")
    Lota::Filesystem.write("foo/bar/file2.txt", "file2")
    # check both the file + subdir exist in the item list
    files = Lota::Filesystem.directory_items("foo")
    hasfile = false
    hasdir = false
    files.each do |v|
      info = Lota::Filesystem.info("foo/#{v}")
      hasdir = true if v == "bar" && info.type == :directory
      hasfile = true if v == "file1.txt" && info.type == :file
    end
    assert_true(hasfile, "check file exists")
    assert_true(hasdir, "check directory exists")
    # cleanup
    Lota::Filesystem.remove("foo/file1.txt")
    Lota::Filesystem.remove("foo/bar/file2.txt")
    Lota::Filesystem.remove("foo/bar")
    Lota::Filesystem.remove("foo")
  end

  # Translated to Ruby from love.test.filesystem.getFullCommonPath
  # (filesystem.lua:191-208): getFullCommonPath becomes full_common_path
  # (rule 3), with the common paths symbols (rule 9). Lua's pcall, which
  # returns false when the call raised, becomes a rescue.
  def test_get_full_common_path
    # check standard paths
    appsavedir = Lota::Filesystem.full_common_path(:appsavedir)
    appdocuments = Lota::Filesystem.full_common_path(:appdocuments)
    userhome = Lota::Filesystem.full_common_path(:userhome)
    userappdata = Lota::Filesystem.full_common_path(:userappdata)
    userdesktop = Lota::Filesystem.full_common_path(:userdesktop)
    userdocuments = Lota::Filesystem.full_common_path(:userdocuments)
    assert_not_nil(appsavedir)
    assert_not_nil(appdocuments)
    assert_not_nil(userhome)
    assert_not_nil(userappdata)
    assert_not_nil(userdesktop)
    assert_not_nil(userdocuments)
    # check invalid path
    ok = begin
      Lota::Filesystem.full_common_path(:fakepath)
      true
    rescue ArgumentError
      false
    end
    assert_false(ok, "check invalid common path")
  end

  # Translated to Ruby from love.test.filesystem.getRealDirectory
  # (filesystem.lua:223-233): getRealDirectory becomes real_directory
  # (rule 3), which returns luax_ioError's nil and message when it cannot
  # find the file, so it returns an Array on every path, whose first
  # Lua's comparison takes (rule 4).
  def test_get_real_directory
    # make a test dir + file first
    Lota::Filesystem.create_directory("foo")
    Lota::Filesystem.write("foo/test.txt", "test")
    # check save dir matches the real dir we just wrote to
    assert_equal(Lota::Filesystem.save_directory,
      Lota::Filesystem.real_directory("foo/test.txt").first, "check directory matches")
    # cleanup
    Lota::Filesystem.remove("foo/test.txt")
    Lota::Filesystem.remove("foo")
  end

  # Translated to Ruby from love.test.filesystem.getSource and
  # love.test.filesystem.setSource (filesystem.lua:245-247 and 535-537),
  # which Lövetest skips because LÖVE's boot calls them first.
  def test_get_source
    skip("used internally")
  end

  def test_set_source
    skip("used internally")
  end

  # Translated to Ruby from love.test.filesystem.mount and
  # love.test.filesystem.unmount (filesystem.lua:356-371 and 541-554):
  # read's two results are an Array (rule 4), which write takes apart
  # again, and getInfo's type is a symbol (rule 9).
  def test_mount
    # write an example zip to savedir to use
    contents, size = Lota::Filesystem.read("resources/test.zip") # contains test.txt
    Lota::Filesystem.write("test.zip", contents, size)
    # check mounting file and check contents are mounted
    success = Lota::Filesystem.mount("test.zip", "test")
    assert_true(success, "check success")
    refute_equal(nil, Lota::Filesystem.info("test"), "check mount not nil")
    assert_equal(:directory, Lota::Filesystem.info("test").type, "check directory made")
    refute_equal(nil, Lota::Filesystem.info("test/test.txt"), "check file not nil")
    assert_equal(:file, Lota::Filesystem.info("test/test.txt").type, "check file type")
    # cleanup
    Lota::Filesystem.remove("test/test.txt")
    Lota::Filesystem.remove("test")
    Lota::Filesystem.remove("test.zip")
  end

  def test_unmount
    # create a zip file mounted to use
    contents, size = Lota::Filesystem.read("resources/test.zip") # contains test.txt
    Lota::Filesystem.write("test.zip", contents, size)
    Lota::Filesystem.mount("test.zip", "test")
    # check mounted, unmount, then check its unmounted
    refute_equal(nil, Lota::Filesystem.info("test/test.txt"), "check mount exists")
    Lota::Filesystem.unmount("test.zip")
    assert_nil(Lota::Filesystem.info("test/test.txt"), "check unmounted")
    # cleanup
    Lota::Filesystem.remove("test/test.txt")
    Lota::Filesystem.remove("test")
    Lota::Filesystem.remove("test.zip")
  end

  # Translated to Ruby from love.test.filesystem.mountFullPath and
  # love.test.filesystem.unmountFullPath (filesystem.lua:375-396):
  # getSource becomes source (rule 3), and the mount permissions symbols
  # (rule 9). Lövetest mounts its own tests folder and reads its
  # audio.lua through the mount; this suite's tests are Ruby, so it reads
  # their translation, tests/audio.rb, which the runner under lota run
  # finds through test/lovetest/game/tests, as it finds resources/.
  def test_mount_full_path
    # mount something in the working directory
    mount = Lota::Filesystem.mount_full_path("#{Lota::Filesystem.source}/tests", "tests", :read)
    assert_true(mount, "check can mount")
    # check reading file through mounted path label
    contents, = Lota::Filesystem.read("tests/audio.rb")
    refute_equal(nil, contents)
    unmount = Lota::Filesystem.unmount_full_path("#{Lota::Filesystem.source}/tests")
    assert_true(unmount, "reset mount")
  end

  def test_unmount_full_path
    # try unmounting something we never mounted
    unmount1 = Lota::Filesystem.unmount_full_path("#{Lota::Filesystem.source}/faker")
    assert_false(unmount1, "check not mounted to start with")
    # mount something to unmount after
    Lota::Filesystem.mount_full_path("#{Lota::Filesystem.source}/tests", "tests", :read)
    unmount2 = Lota::Filesystem.unmount_full_path("#{Lota::Filesystem.source}/tests")
    assert_true(unmount2, "check unmounted")
  end

  # Translated to Ruby from love.test.filesystem.mountCommonPath
  # (filesystem.lua:400-419): mountCommonPath becomes mount_common_path
  # (rule 13), with its paths and permissions symbols (rule 9), and Lua's
  # pcall a rescue. Lövetest runs a module's tests in the order of their
  # names (classes/TestModule.lua:68-71), so by this test love.test.
  # filesystem.append and the others before it have written to the save
  # directory, which LÖVE mounts when a game first writes
  # (physfs/Filesystem.cpp:357-376), and mount1 fails because it is
  # mounted already. Minitest runs them in random order, so this test
  # first writes and removes a file, as those tests leave the save
  # directory mounted.
  def test_mount_common_path
    Lota::Filesystem.write("filesystem.mountCommonPath.txt", "")
    Lota::Filesystem.remove("filesystem.mountCommonPath.txt")
    # check if we can mount all the expected paths
    mount1 = Lota::Filesystem.mount_common_path(:appsavedir, "appsavedir", :readwrite)
    mount2 = Lota::Filesystem.mount_common_path(:appdocuments, "appdocuments", :readwrite)
    mount3 = Lota::Filesystem.mount_common_path(:userhome, "userhome", :readwrite)
    mount4 = Lota::Filesystem.mount_common_path(:userappdata, "userappdata", :readwrite)
    # userdesktop isnt valid on linux
    unless Lovetest.os?("Linux")
      mount5 = Lota::Filesystem.mount_common_path(:userdesktop, "userdesktop", :readwrite)
      assert_true(mount5, "check mount userdesktop")
    end
    mount6 = Lota::Filesystem.mount_common_path(:userdocuments, "userdocuments", :readwrite)
    ok = begin
      Lota::Filesystem.mount_common_path(:fakepath, "fake", :readwrite)
      true
    rescue ArgumentError
      false
    end
    assert_false(mount1, "check mount appsavedir") # This is already mounted, we can't do it again.
    assert_true(mount2, "check mount appdocuments")
    assert_true(mount3, "check mount userhome")
    assert_true(mount4, "check mount userappdata")
    assert_true(mount6, "check mount userdocuments")
    assert_false(ok, "check mount invalid common path fails")
  end

  # Translated to Ruby from love.test.filesystem.openFile
  # (filesystem.lua:458-464): openFile becomes open_file (rule 13), whose
  # File comes in an Array (rule 4), never nil itself, as Lua's first
  # result is not when it opens. Lövetest leaves the four Files for its
  # collectgarbage after the test to close (classes/TestSuite.lua:
  # 109-110), and LÖVE refuses a new identity while one is open
  # (physfs/Filesystem.cpp:189-203). Ruby's collector scans the stack
  # conservatively, so a word left there can keep a File alive past it,
  # and the translation closes them itself once the test is done with
  # them.
  def test_open_file
    files = %i[w r a c].map { |mode| Lota::Filesystem.open_file("file2.txt", mode).first }
    files.each { |file| assert_not_nil(file) }
    Lota::Filesystem.remove("file2.txt")
  ensure
    files&.each { |file| file&.close }
  end

  # Translated to Ruby from love.test.filesystem.newFileData
  # (filesystem.lua:469-471): newFileData becomes FileData.new (rule 2).
  def test_new_file_data
    assert_not_nil(Lota::Filesystem::FileData.new("helloworld", "file1"))
  end

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
