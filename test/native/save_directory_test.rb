# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
  # place of LÖVE's (doc/contributors/design/game.md).
  def save_directory
    TestHome.system_path(File.join(TestHome.application_data(ENV.fetch("LOTA_TEST_HOME")), TestHome::LOTA_FOLDER,
      IDENTITY))
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
    assert Lota::Filesystem.save_directory.end_with?(TestHome.system_path("/#{TestHome::LOTA_FOLDER}/#{IDENTITY}-appended"))
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
    skip("Windows deletes no file a process holds open") if TestHome::WINDOWS
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

  # Rule 10: getInfo's table becomes a frozen Info with LÖVE's fields,
  # each as w_getInfo sets it (wrap_Filesystem.cpp:544-602): the type a
  # symbol, and the size and time Integers, as LÖVE's C++ holds them.
  def test_info_is_a_frozen_record_of_lovees_fields
    path = saved("scores.txt", "12345")
    info = Lota::Filesystem.info("scores.txt")

    assert_instance_of Lota::Filesystem::Info, info
    assert_predicate info, :frozen?
    assert_equal [:file, false, 5, File.mtime(path).to_i], [info.type, info.readonly, info.size, info.modtime]
    assert_equal :directory, Lota::Filesystem.info("", :directory).type
    assert_nil Lota::Filesystem.info("scores.txt", :directory)
    assert_nil Lota::Filesystem.info("missing.txt")
  end

  def test_info_raises_lovees_message_for_an_unknown_file_type
    error = assert_raises(ArgumentError) { Lota::Filesystem.info("scores.txt", :folder) }

    assert_equal "Invalid file type 'folder', expected one of: 'file', 'directory', 'symlink', 'other'", error.message
  end

  # Rule 4: read returns its two results in an Array on failure too, the
  # nil and message of luax_ioError (wrap_Filesystem.cpp:618-659), so the
  # shape never depends on whether it worked.
  def test_read_returns_nil_and_the_engines_message_when_it_cannot_read
    content, message = Lota::Filesystem.read("missing.txt")

    assert_nil content
    assert_equal "Could not open file missing.txt. Does not exist.", message
  end

  # A Lua string is bytes, so read gives back every byte the file holds,
  # as KleleAtoms' saved game holds bytes such as 255.
  def test_read_and_write_keep_every_byte
    bytes = "KSF\x0a\x06\xff\x00".b
    assert_equal [true], Lota::Filesystem.write("game.ksf", bytes)

    content, size = Lota::Filesystem.read("game.ksf")
    assert_equal bytes.bytes, content.bytes
    assert_equal 7, size
    assert_equal bytes, File.binread(File.join(save_directory, "game.ksf"))
  end

  def test_write_takes_a_file_data_and_writes_no_more_than_the_data_holds
    data = Lota::Filesystem.new_file_data("helloworld", "hello.txt").first

    assert_equal [true], Lota::Filesystem.write("hello.txt", data, 64)
    assert_equal "helloworld", File.binread(File.join(save_directory, "hello.txt"))
    assert_raises(TypeError) { Lota::Filesystem.write("hello.txt", 42) }
  end

  # write returns luax_ioError's nil and message when PhysicsFS cannot
  # open the file, here because a directory has its name.
  def test_write_returns_nil_and_the_engines_message_when_it_cannot_write
    Lota::Filesystem.create_directory("taken")
    ok, message = Lota::Filesystem.write("taken", "x")

    assert_nil ok
    assert_kind_of String, message
    refute_empty message
  end

  # Rules 11 and 30: open's block form is LÖVE's if file:open("r") then ...
  # file:close() end, so it yields the open File, closes it after, and
  # returns what the block returns, as push's block form does.
  def test_open_with_a_block_yields_the_open_file_closes_it_and_returns_the_blocks_value
    saved("scores.txt", "ada 120")
    file, = Lota::Filesystem.open_file("scores.txt", :c)

    value = file.open(:r) do |opened|
      assert_same file, opened
      assert_predicate file, :open?
      file.read.first
    end

    assert_equal "ada 120", value
    refute_predicate file, :open?
  end

  def test_open_with_a_block_closes_the_file_when_the_block_raises
    saved("scores.txt", "ada 120")
    file, = Lota::Filesystem.open_file("scores.txt", :c)

    assert_raises(ZeroDivisionError) { file.open(:r) { 1 / 0 } }
    refute_predicate file, :open?
  end

  # File::open throws for a file to read that does not exist
  # (physfs/File.cpp:107-109), which w_File_open returns as luax_ioError's
  # nil and message (wrap_File.cpp:84-91), so the block has no file.
  def test_open_with_a_block_returns_lovees_nil_and_message_without_yielding_when_it_cannot_open
    file, = Lota::Filesystem.open_file("missing.txt", :c)

    result = file.open(:r) { flunk "the block ran" }

    assert_equal [nil, "Could not open file missing.txt. Does not exist."], result
  end

  # File::open returns false for a file already open (physfs/File.cpp:
  # 115-117): the block form neither yields nor closes the file it did not
  # open.
  def test_open_with_a_block_returns_false_for_a_file_already_open_and_leaves_it_open
    file, = Lota::Filesystem.open_file("scores.txt", :w)

    result = file.open(:w) { flunk "the block ran" }

    assert_equal [false], result
    assert_predicate file, :open?
  ensure
    file&.close
  end

  # w_load reads the file through LÖVE's filesystem and compiles it without
  # running it (wrap_Filesystem.cpp:746-800); Lota compiles Ruby, and the
  # chunk is a Proc that runs it, giving the value of its last expression.
  def test_load_compiles_a_saved_file_and_runs_it_only_when_called
    saved("chunk.rb", "Lota::Filesystem.write('ran.txt', 'yes')\n6 * 7\n")

    chunk, message = Lota::Filesystem.load("chunk.rb")

    assert_nil message
    assert_kind_of Proc, chunk
    refute Lota::Filesystem.exists("ran.txt")
    assert_equal 42, chunk.call
    assert Lota::Filesystem.exists("ran.txt")
  end

  # A Lua chunk is called with its arguments as ..., as a Ruby file
  # receives its own as ARGV, which is the process's again after the call,
  # also when the code raises.
  def test_load_gives_a_chunk_its_arguments_as_argv_and_puts_the_process_argv_back
    saved("arguments.rb", "ARGV.dup")
    saved("raises.rb", "raise ArgumentError, ARGV.inspect")
    before = ARGV.dup

    assert_equal [1, "two"], Lota::Filesystem.load("arguments.rb").first.call(1, "two")
    assert_equal [], Lota::Filesystem.load("arguments.rb").first.call
    error = assert_raises(ArgumentError) { Lota::Filesystem.load("raises.rb").first.call(:three) }
    assert_equal "[:three]", error.message
    assert_equal before, ARGV
  end

  # LÖVE names the chunk after the file (wrap_Filesystem.cpp:777), so
  # its errors say where they are.
  def test_load_names_the_file_in_backtraces
    saved("boom.rb", "def lota_load_test_boom\n  raise 'boom'\nend\nlota_load_test_boom\n")

    error = assert_raises(RuntimeError) { Lota::Filesystem.load("boom.rb").first.call }

    assert_equal ["boom.rb", 2], [error.backtrace_locations.first.path, error.backtrace_locations.first.lineno]
  ensure
    Object.__send__(:remove_method, :lota_load_test_boom) if Object.private_method_defined?(:lota_load_test_boom)
  end

  # The code runs at Ruby's top level, as a file Ruby loads does, so what
  # it defines is the program's, as a Lua chunk's globals are.
  def test_load_runs_the_code_at_the_top_level
    saved("defines.rb", "class LotaLoadTestDefined; end\nself")

    assert_same TOPLEVEL_BINDING.receiver, Lota::Filesystem.load("defines.rb").first.call
    assert Object.const_defined?(:LotaLoadTestDefined, false)
  ensure
    Object.__send__(:remove_const, :LotaLoadTestDefined) if Object.const_defined?(:LotaLoadTestDefined, false)
  end

  # w_load raises luaL_error's "Syntax error: %s\n" when the chunk does not
  # compile (wrap_Filesystem.cpp:796-797), at once, before anything runs;
  # Lota raises Ruby's SyntaxError with that message about Ruby's.
  def test_load_raises_a_syntax_error_at_once_with_lovees_message
    saved("broken.rb", "def broken\n")

    error = assert_raises(SyntaxError) { Lota::Filesystem.load("broken.rb") }

    assert_match(/\ASyntax error: broken\.rb:\d+: /, error.message)
    assert error.message.end_with?("\n")
  end

  # w_load returns luax_ioError's nil and message when it cannot read the
  # file (wrap_Filesystem.cpp:760-768).
  def test_load_returns_nil_and_the_engines_message_for_a_missing_file
    assert_equal [nil, "Could not open file missing.rb. Does not exist."], Lota::Filesystem.load("missing.rb", :b)
  end

  # The mode is LÖVE's load mode (Filesystem.cpp:261-267), checked before
  # the file is read (wrap_Filesystem.cpp:750-758). Ruby source is text,
  # so "t" and "bt" load it and "b" refuses it, as LuaJIT refuses a text
  # chunk in mode "b" with a syntax error (lj_load.c, cpparser).
  def test_load_takes_lovees_load_modes_and_refuses_text_in_binary_mode
    saved("answer.rb", "42")

    assert_equal 42, Lota::Filesystem.load("answer.rb", :t).first.call
    assert_equal 42, Lota::Filesystem.load("answer.rb", "bt").first.call
    error = assert_raises(SyntaxError) { Lota::Filesystem.load("answer.rb", :b) }
    assert_equal "Syntax error: attempt to load chunk with wrong mode\n", error.message
    error = assert_raises(ArgumentError) { Lota::Filesystem.load("missing.rb", :x) }
    assert_equal "Invalid load mode 'x', expected one of: 'b', 't', 'bt'", error.message
  end

  # Ruby's compiled instruction sequence is Lota's binary chunk, as LuaJIT's
  # bytecode is Lua's: "b" and "bt" load it, "t" refuses it with LuaJIT's
  # message for a chunk of the wrong mode (lj_load.c, cpparser), and it keeps
  # the arguments a chunk takes as ARGV.
  def test_load_loads_a_compiled_instruction_sequence_in_binary_mode
    saved("answer.rbc", RubyVM::InstructionSequence.compile("ARGV.first * 2", "answer.rb").to_binary)

    assert_equal 42, Lota::Filesystem.load("answer.rbc", :b).first.call(21)
    assert_equal 42, Lota::Filesystem.load("answer.rbc", "bt").first.call(21)
    assert_equal 42, Lota::Filesystem.load("answer.rbc").first.call(21)
    error = assert_raises(SyntaxError) { Lota::Filesystem.load("answer.rbc", :t) }
    assert_equal "Syntax error: attempt to load chunk with wrong mode\n", error.message
  end

  # A binary chunk keeps the name it was compiled under, as bytecode does.
  def test_a_binary_chunk_keeps_the_name_it_was_compiled_under
    saved("named.rbc", RubyVM::InstructionSequence.compile("__FILE__", "compiled_as.rb").to_binary)

    assert_equal "compiled_as.rb", Lota::Filesystem.load("named.rbc", :b).first.call
  end

  # A binary file this Ruby cannot load is a syntax error with Ruby's message.
  def test_load_refuses_a_binary_chunk_another_ruby_compiled
    binary = RubyVM::InstructionSequence.compile("1", "one.rb").to_binary
    # The four bytes after the magic hold the major version.
    binary[4, 4] = [99].pack("L<")
    saved("other.rbc", binary)
    error = assert_raises(SyntaxError) { Lota::Filesystem.load("other.rbc", :b) }

    assert_match(/\ASyntax error: .*version.*\n\z/, error.message)
  end

  # Text that merely starts like a binary file is not one: only the magic
  # tells them apart, as the first byte of bytecode does.
  def test_text_is_not_binary_in_binary_mode
    saved("text.rb", "42")

    assert_raises(SyntaxError) { Lota::Filesystem.load("text.rb", :b) }
  end

  # Rule 17: newFileData can return nil and a message, so it stays a module
  # method that returns an Array, as every function of rule 4 does
  # (wrap_Filesystem.cpp:428-463).
  def test_new_file_data_copies_a_string_or_a_data_under_a_name
    from_string, = Lota::Filesystem.new_file_data("helloworld", "hello.txt")
    from_data, = Lota::Filesystem.new_file_data(Lota::Data::ByteData.new("byte data"), "bytes.bin")

    assert_equal ["helloworld", "hello.txt", "txt"], [from_string.string, from_string.filename, from_string.extension]
    assert_equal ["byte data", "bytes.bin"], [from_data.string, from_data.filename]
    assert_equal 1, Lota::Filesystem.new_file_data("x", "x").size
  end

  def test_new_file_data_with_one_argument_reads_a_file_a_file_or_returns_a_file_data
    saved("scores.txt", "ada 120\n")
    from_name, = Lota::Filesystem.new_file_data("scores.txt")
    file, = Lota::Filesystem.open_file("scores.txt", :r)
    from_file, = Lota::Filesystem.new_file_data(file)

    assert_equal ["ada 120\n", "scores.txt"], [from_name.string, from_name.filename]
    assert_equal "ada 120\n", from_file.string
    assert_same from_name, Lota::Filesystem.new_file_data(from_name).first
  ensure
    file&.close
  end

  # luax_getfiledata asked for an I/O error (wrap_Filesystem.cpp:332-373).
  def test_new_file_data_returns_nil_and_the_engines_message_for_a_file_it_cannot_read
    assert_equal [nil, "Could not open file missing.txt. Does not exist."], Lota::Filesystem.new_file_data("missing.txt")
  end

  def test_new_file_data_raises_for_arguments_of_the_wrong_type_or_number
    assert_raises(TypeError) { Lota::Filesystem.new_file_data(42) }
    assert_raises(TypeError) { Lota::Filesystem.new_file_data(42, "x") }
    assert_raises(TypeError) { Lota::Filesystem.new_file_data("x", 42) }
    assert_equal "wrong number of arguments (given 3, expected 1..2)",
      assert_raises(ArgumentError) { Lota::Filesystem.new_file_data("x", "y", "z") }.message
    refute_respond_to Lota::Filesystem::FileData, :new
  end

  # w_newFile, which LÖVE deprecated for openFile (wrap_Filesystem.cpp:278-306),
  # returns its File, closed unless given a mode, or nil and a message.
  def test_new_file_returns_a_file_or_nil_and_a_message
    saved("scores.txt", "ada 120\n")
    closed, = Lota::Filesystem.new_file("scores.txt")
    reading, = Lota::Filesystem.new_file("scores.txt", :r)

    refute_predicate closed, :open?
    assert_predicate reading, :open?
    assert_equal ["ada 120\n", 8], reading.read
    assert_equal [nil, "Could not open file missing.txt. Does not exist."], Lota::Filesystem.new_file("missing.txt", :r)
    assert_raises(ArgumentError) { Lota::Filesystem.new_file("scores.txt", :x) }
  ensure
    reading&.close
  end
end
