# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../callback_helper"
require "tmpdir"

# A file dropped on the window, or opened with the app on macOS, which
# SDL's Cocoa delegate sends as a drop, reaches a game as LÖVE gives it:
# LÖVE's event module opens the file closed on its path and puts the File
# in a filedropped message, and a folder's path in a directorydropped
# one (vendor/love/src/modules/event/sdl/Event.cpp:536-565). No test can
# drag a file, so each pushes into SDL's queue the event SDL would send
# (LotaNativeTest.push_drop), and LÖVE's own Event::convert turns it into
# the message.
class DropTest < Minitest::Test
  include CallbackHelper

  def setup
    super
    EngineHelper.open_window
    Lota::Event.pump
    nil while Lota::Callbacks.poll
  end

  # Records every call of +callback+, with every argument LÖVE passed,
  # while the block runs and one frame of Lota's loop after it.
  def calls(callback)
    received = []
    define_callback(callback) { |*arguments| received << arguments }
    yield
    Lota.run.call
    received
  end

  def test_a_dropped_file_reaches_filedropped_as_a_closed_file_of_its_path
    Dir.mktmpdir do |folder|
      path = File.join(folder, "Sample Game.lota")
      File.write(path, "a game")
      received = calls(:filedropped) { LotaNativeTest.push_drop(path) }

      assert_equal 1, received.size
      file, x, y = received.first

      assert_kind_of Lota::Filesystem::File, file
      assert_equal path, file.filename
      assert_equal [:c], file.mode
      assert_kind_of Numeric, x
      assert_kind_of Numeric, y
    end
  end

  def test_a_dropped_folder_reaches_directorydropped_as_its_path
    Dir.mktmpdir do |folder|
      received = calls(:directorydropped) { LotaNativeTest.push_drop(folder) }

      assert_equal [folder], received.map(&:first)
    end
  end
end
