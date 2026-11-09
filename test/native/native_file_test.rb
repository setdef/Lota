# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tmpdir"
require_relative "native_helper"
require_relative "../engine_helper"

# love.filesystem.openNativeFile (src/modules/filesystem/
# wrap_Filesystem.cpp:254-276) opens a file by its path on the computer,
# outside the game's folder and its save directory, as a NativeFile
# (src/modules/filesystem/NativeFile.cpp), which Lövetest does not test.
class NativeFileTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  def test_a_native_file_writes_and_reads_a_path_on_the_computer
    Dir.mktmpdir do |directory|
      path = File.join(directory, "note.txt")
      file, = Lota::Filesystem.open_native_file(path, :w)

      assert_instance_of Lota::Filesystem::File, file
      assert_equal [path, [:w]], [file.filename, file.mode]
      file.write("hello")
      file.close

      assert_equal "hello", File.binread(path)
      assert_equal [true], file.open(:r)
      assert_equal ["hello", 5], file.read
      file.close
    end
  end

  def test_a_file_that_cannot_open_returns_nil_and_loves_message
    Dir.mktmpdir do |directory|
      path = File.join(directory, "missing.txt")
      file, message = Lota::Filesystem.open_native_file(path, :r)

      assert_nil file
      assert_match(/\ACould not open file #{Regexp.escape(path)}: /, message)
    end
  end

  def test_an_unknown_mode_raises_loves_error
    error = assert_raises(ArgumentError) { Lota::Filesystem.open_native_file("note.txt", :x) }

    assert_match(/\AInvalid file open mode 'x', expected one of: /, error.message)
  end
end
