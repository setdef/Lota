# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require "rbconfig"
require "tmpdir"

# A test that moves the pointer and reads it back, as Lövetest's mouse
# tests do, reads what the person at the computer did with the mouse
# instead whenever they moved it: love.mouse.setPosition warps the pointer,
# then pumps SDL's events (vendor/love/src/modules/mouse/sdl/Mouse.cpp,
# setPosition), and a movement macOS queued before the warp, or reported
# after it, is the place SDL then records. LotaNativeTest.hold_pointer,
# and liblota_still_pointer for a whole program, drop every movement the
# system reports, so a test reads back what it set
# (ext/lota/native_test/still_pointer.mm). Each test here queues a
# movement as macOS queues a person's.
#
# On Linux the tests run on CI's Xvfb, where no one moves the mouse.
class StillPointerTest < Minitest::Test
  include NativeHelper

  if RUBY_PLATFORM.include?("darwin")
    def setup
      EngineHelper.open_window
    end

    def teardown
      LotaNativeTest.release_pointer
    end

    # The failure the hold prevents: the person's movement, queued before
    # the warp, is what the pointer reads back after it.
    def test_a_movement_queued_before_a_warp_is_read_back_after_it
      assert LotaNativeTest.move_mouse_as_a_person_would(123, 45)
      Lota::Mouse.position = 0, 0

      assert_equal [123, 45], Lota::Mouse.position
    end

    def test_with_the_pointer_held_a_warp_reads_back_what_it_set
      LotaNativeTest.hold_pointer
      LotaNativeTest.move_mouse_as_a_person_would(123, 45)
      Lota::Mouse.position = 0, 0

      assert_equal [0, 0], Lota::Mouse.position
      Lota::Mouse.x = 30
      LotaNativeTest.move_mouse_as_a_person_would(200, 45)
      Lota::Event.pump

      assert_equal 30, Lota::Mouse.x
    end

    def test_released_the_pointer_follows_the_mouse_again
      LotaNativeTest.hold_pointer
      LotaNativeTest.release_pointer
      LotaNativeTest.move_mouse_as_a_person_would(77, 33)
      Lota::Event.pump

      assert_equal [77, 33], Lota::Mouse.position
    end

    # A game that queues a person's movement, then warps the pointer to
    # its top left and prints where it reads it.
    GAME = <<~RUBY
      require "lota_native_test"

      def Lota.update(_dt)
        LotaNativeTest.move_mouse_as_a_person_would(123, 45)
        Lota::Mouse.position = 0, 0
        puts Lota::Mouse.position.inspect
        Lota::Event.quit
      end
    RUBY

    # lota run on GAME, with +preload+ loaded into it first.
    def run_game(preload)
      Dir.mktmpdir("lota-still-pointer") do |game|
        File.write(File.join(game, "main.rb"), GAME)
        native = File.dirname(File.dirname(loaded("lota/native")))
        native_test = File.dirname(loaded("lota_native_test"))
        load_path = [native, File.join(ROOT, "lib"), native_test].uniq.join(File::PATH_SEPARATOR)
        inserted = [ENV.fetch("DYLD_INSERT_LIBRARIES", nil), *preload].compact
        capture2e({ "DYLD_INSERT_LIBRARIES" => inserted.empty? ? nil : inserted.join(":") }, RbConfig.ruby, "-w",
          "-I#{load_path}", File.join(ROOT, "exe/lota"), "run", game)
      end
    end

    # liblota_still_pointer holds the pointer in a whole program, from the
    # first events it handles, without the program asking.
    def test_the_library_holds_the_pointer_in_a_program_it_is_loaded_into
      library = File.join(File.dirname(loaded("lota_native_test")), "liblota_still_pointer.dylib")
      held, held_status = run_game(library)
      free, free_status = run_game(nil)

      assert_predicate held_status, :success?, held
      assert_equal "[0.0, 0.0]\n", held
      assert_predicate free_status, :success?, free
      assert_equal "[123.0, 45.0]\n", free
    end
  end
end
