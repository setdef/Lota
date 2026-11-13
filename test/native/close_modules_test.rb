# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Native.close_modules closes the engine as lua_close closes LÖVE's
# main Lua state (src/love.cpp:291), so that a game can start again in the
# same process. Each test closes the engine in a Ruby of its own
# (NativeHelper#ruby_of_its_own), since the tests that share this process
# need theirs open: under rake test:native, under the sanitizers, which
# catch an object that outlives a module it needs.
class CloseModulesTest < Minitest::Test
  include NativeHelper

  # Opens the window and every module, as Lota::Boot does for a game, and
  # keeps the window in the background, as the tests' own does
  # (EngineHelper).
  SETUP = <<~RUBY
    require "lota"
    require "lota_native_test"
    $stdout.sync = true
    def boot
      Lota::Boot.new(#{EngineHelper::CONF.dump}).init
      LotaNativeTest.stay_in_background
    end
    def still_open
      names = [*Lota::Boot::MODULES.keys, :filesystem].select { |name| Lota::Native.const_get(name.capitalize).open? }
      names.map(&:to_s)
    end
    boot
  RUBY

  def run_script(script)
    native_test = File.dirname(loaded("lota_native_test"))
    output, status = ruby_of_its_own("-I#{native_test}", "-e", SETUP + script)

    assert_predicate status, :success?, output
    output.lines(chomp: true).grep_v("love.conf")
  end

  def test_closing_releases_every_object_and_module_and_the_engine_opens_again
    output = run_script(<<~RUBY)
      font = Lota::Graphics::Font.new(12)
      objects = [
        Lota::Graphics::Image.new(Lota::Image::ImageData.new(16, 16)),
        Lota::Graphics::Canvas.new(16, 16),
        font,
        Lota::Graphics::TextBatch.new(font, "text"),
        Lota::Audio::Source.new(Lota::Sound::SoundData.new(441, 44_100, 16, 1)).tap(&:play),
        Lota::Physics::World.new(0, 9.81).tap { |world| Lota::Physics.new_circle_body(world, :dynamic, 0, 0, 5) },
      ]
      Lota::Thread.channel("kept").push(1)
      p Lota::Native.close_modules
      p still_open
      p objects.map(&:release)
      begin
        objects.first.width
      rescue RuntimeError => e
        puts e.message
      end
      GC.start(full_mark: true, immediate_sweep: true)
      boot
      p still_open.size == Lota::Boot::MODULES.size + 1
      p Lota::Thread.channel("kept").count
      image = Lota::Graphics::Image.new(Lota::Image::ImageData.new(16, 16))
      Lota::Graphics.draw(image, 1, 1)
      Lota::Graphics.present
      p Lota::Graphics.dimensions
      p Lota::Native.close_modules
    RUBY

    assert_equal [
      "[]",
      "[]",
      "[false, false, false, false, false, false]",
      "Cannot use object after it has been released.",
      "true",
      "0",
      "[360, 240]",
      "[]",
], output
  end

  # A running thread holds the thread module, and its named channels, as
  # each of LÖVE's threads holds love.thread, until it ends. The thread's
  # object stays alive for the thread, which holds it, though this
  # Ractor's wrapper of it is released.
  def test_a_running_thread_keeps_the_thread_module_and_its_channels_until_it_ends
    output = run_script(<<~RUBY)
      thread = Lota::Thread::Thread.new(<<~CODE)
        Lota::Thread.channel("go").demand
        Lota::Thread.channel("done").push(true)
      CODE
      thread.start
      Lota::Thread.channel("kept").push(1)
      p Lota::Native.close_modules
      p Lota::Thread.channel("kept").count
      p thread.release
      Lota::Thread.channel("go").push(true)
      p Lota::Thread.channel("done").demand(30)
      100.times { Lota::Native.close_modules.empty? ? break : sleep(0.05) }
      p Lota::Native.close_modules
      p Lota::Native::Thread.open?
    RUBY

    assert_equal ['["thread"]', "1", "false", "true", "[]", "false"], output
  end
end
