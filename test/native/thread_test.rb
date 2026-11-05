# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# Lota::Thread's threads run in Ractors, and so do these tests, each in a
# Ruby of its own (NativeHelper#ruby_of_its_own), which runs the engine's
# native layer from Ractors other than the main one: under rake
# test:native, under the sanitizers. Each script prints what the test
# compares, one line at a time.
class ThreadTest < Minitest::Test
  include NativeHelper

  # The game folder whose files the scripts read.
  GAME = File.join(ROOT, "test/lovetest")

  # Brings up the modules a script uses, without a window, as Lota::Boot
  # opens them, with the filesystem reading GAME.
  SETUP = <<~RUBY
    require "lota"
    Lota::Native::Filesystem.open
    Lota::Native::Filesystem.init($PROGRAM_NAME)
    Lota::Native::Filesystem.set_source(#{GAME.dump})
    %i[Data Thread Timer Event Math Physics Image Sound].each { |name| Lota::Native.const_get(name).open }
    $stdout.sync = true
    CHANNEL = Lota::Thread.channel("out")
    def run_thread(code, *arguments)
      thread = Lota::Thread::Thread.new(code)
      thread.start(*arguments)
      thread.wait
      raise thread.error if thread.error
      thread
    end
  RUBY

  def run_script(script)
    output, status = ruby_of_its_own("-e", SETUP + script)
    assert_predicate status, :success?, output
    output
  end

  # The modules LÖVE lets a thread use answer there as on the main thread:
  # love.math's generator, which every thread shares as in LÖVE, a
  # Transform, love.filesystem reading the game's files, FileData, the
  # timer, and a World that steps and keeps a contact callback, a Ruby
  # value the engine holds from that Ractor.
  def test_the_modules_loves_threads_may_use_answer_in_a_thread
    output = run_script(<<~RUBY)
      run_thread(<<~CODE)
        out = Lota::Thread.channel("out")
        Lota::Math.random_seed = 3
        out.push(Lota::Math.random(1000))
        out.push(Lota::Math::Transform.new.translate(2, 3).transform_point(1, 1))
        out.push(Lota::Filesystem.read("conf.rb").first.bytesize)
        out.push(Lota::Filesystem::FileData.new("abc", "a.txt").string)
        out.push(Lota::Timer.time.class)
        world = Lota::Physics::World.new(0, 10)
        body = Lota::Physics::Body.new(world, 0, 0, :dynamic)
        Lota::Physics::CircleShape.new(body, 1)
        world.callbacks = ->(a, b, contact) {}, nil, nil, nil
        world.update(1)
        GC.start
        out.push(body.y > 0)
      CODE
      Lota::Math.random_seed = 3
      puts CHANNEL.pop == Lota::Math.random(1000)
      p CHANNEL.pop
      puts CHANNEL.pop == File.binread(#{File.join(GAME, 'conf.rb').dump}).bytesize
      p CHANNEL.pop, CHANNEL.pop, CHANNEL.pop
    RUBY

    assert_equal "true\n[3.0, 4.0]\ntrue\n\"abc\"\nFloat\ntrue\n", output
  end

  # LÖVE keeps love.graphics and love.window off its threads
  # (LuaThread.cpp:72-73): lota.graphics and lota.window are nil there,
  # and their bindings, as those of a module Lota has not yet shown safe
  # for threads, raise Ractor::UnsafeError.
  def test_graphics_and_window_stay_on_the_main_thread
    output = run_script(<<~RUBY)
      run_thread(<<~CODE)
        out = Lota::Thread.channel("out")
        out.push([Lota.graphics, Lota.window, Lota.thread == Lota::Thread])
        [-> { Lota::Native::Graphics.open? }, -> { Lota::Native::Window.open? }, -> { Lota::Native::Keyboard.open? }].each do |call|
          call.call
          out.push(:called)
        rescue Ractor::UnsafeError => e
          out.push(e.class.name)
        end
      CODE
      4.times { p CHANNEL.pop }
    RUBY

    assert_equal "[nil, nil, true]\n#{%("Ractor::UnsafeError"\n) * 3}", output
  end

  # Each Ractor keeps the wrappers of its own engine objects: one for each
  # object while it lives, as on the main Ractor, so the generator read
  # twice is one Ruby object in the thread, and another on the main
  # Ractor. Wrappers the thread's collector frees leave the next it makes
  # whole.
  def test_each_ractor_has_one_wrapper_for_each_object
    output = run_script(<<~RUBY)
      run_thread(<<~CODE)
        out = Lota::Thread.channel("out")
        first = Lota::Native::Math.random_generator
        out.push(first.equal?(Lota::Native::Math.random_generator))
        out.push(first.object_id)
        3.times do
          10_000.times { Lota::Math::Transform.new }
          GC.start
        end
        out.push(Lota::Native::Math.random_generator.equal?(first))
      CODE
      main = Lota::Native::Math.random_generator
      p CHANNEL.pop, CHANNEL.pop != main.object_id, CHANNEL.pop, main.equal?(Lota::Native::Math.random_generator)
    RUBY

    assert_equal "true\ntrue\ntrue\ntrue\n", output
  end

  # A Channel carries values Ractors share as themselves, and copies and
  # freezes any other, so an Integer stays an Integer, a Symbol a Symbol,
  # and a String or an Array arrives frozen, as a copy of what was pushed.
  # Lota's Data objects, Channels, and Threads are shared, and pushing a
  # Proc, or an engine object that stays in its Ractor, raises
  # ArgumentError.
  def test_a_channel_carries_shareable_values_and_frozen_copies
    output = run_script(<<~RUBY)
      text = +"text"
      list = [1, [2], "three"]
      data = Lota::Filesystem::FileData.new("bytes", "b.bin")
      inner = Lota::Thread::Channel.new
      [3, :symbol, 1.5, nil, true, text, list, data, inner].each { |value| CHANNEL.push(value) }
      p CHANNEL.pop, CHANNEL.pop, CHANNEL.pop, CHANNEL.pop, CHANNEL.pop
      copy = CHANNEL.pop
      p [copy, copy.frozen?, copy.equal?(text), text.frozen?]
      copy = CHANNEL.pop
      p [copy, Ractor.shareable?(copy), list.frozen?]
      p CHANNEL.pop.equal?(data), CHANNEL.pop == inner, Ractor.shareable?(data), data.frozen?
      [-> {}, method(:puts), Lota::Math::Transform.new].each do |value|
        CHANNEL.push(value)
      rescue ArgumentError => e
        puts e.message
      end
      p CHANNEL.count
    RUBY

    assert_equal <<~OUTPUT, output
      3
      :symbol
      1.5
      nil
      true
      ["text", true, false, false]
      [[1, [2], "three"], true, false]
      true
      true
      true
      true
      bad argument #1 to 'push' (boolean, number, string, love type, or table expected)
      bad argument #1 to 'push' (boolean, number, string, love type, or table expected)
      bad argument #1 to 'push' (Transform stays in the thread that made it)
      0
    OUTPUT
  end

  # Channel's timed waits (Channel.cpp:51-66 and 95-113): demand returns
  # nil once its timeout passes, supply returns false and leaves its
  # message queued, a negative timeout waits not at all, and read? tells
  # which messages were read. clear ends the wait of a supply whose message
  # it empties.
  def test_timed_waits_end_and_clear_ends_a_supply
    output = run_script(<<~RUBY)
      start = Lota::Timer.time
      p CHANNEL.demand(0.2), (Lota::Timer.time - start).between?(0.15, 5)
      p CHANNEL.supply(:waiting, 0.05), CHANNEL.count, CHANNEL.demand(-1), CHANNEL.supply(:no, -1), CHANNEL.count
      CHANNEL.clear
      first = CHANNEL.push(:a)
      CHANNEL.pop
      p CHANNEL.read?(first), CHANNEL.read?(CHANNEL.push(:b))
      CHANNEL.clear
      supplier = Lota::Thread::Thread.new("Lota::Thread.channel('out').supply(:forever)\\nLota::Thread.channel('done').push(:returned)\\n")
      supplier.start
      sleep 0.01 until CHANNEL.count == 1
      CHANNEL.clear
      p Lota::Thread.channel("done").demand(5)
      supplier.wait
    RUBY

    assert_equal "nil\ntrue\nfalse\n1\nnil\nfalse\n2\ntrue\nfalse\n:returned\n", output
  end

  # While a thread holds a channel with perform_atomic, another thread's
  # push waits for it, so the block's messages come first, in order.
  def test_perform_atomic_keeps_other_threads_out
    output = run_script(<<~RUBY)
      pusher = Lota::Thread::Thread.new("Lota::Thread.channel('started').push(:ok)\\nLota::Thread.channel('out').push(:other)\\n")
      CHANNEL.perform_atomic(:first) do |channel, value|
        pusher.start
        Lota::Thread.channel("started").demand
        sleep 0.2
        channel.push(value)
        channel.push(:second)
      end
      pusher.wait
      p CHANNEL.pop, CHANNEL.pop, CHANNEL.pop
    RUBY

    assert_equal ":first\n:second\n:other\n", output
  end

  # A Ruby thread that waits in demand, supply, or wait waits without its
  # Ractor's lock, so Ruby can interrupt it, the main Ractor can run the
  # require a thread asks of it, and the collector, which stops every
  # running Ractor first, runs while it waits.
  def test_a_waiting_thread_can_be_interrupted_and_stops_nothing
    output = run_script(<<~RUBY)
      waiter = ::Thread.new do
        CHANNEL.demand
      rescue => e
        e.message
      end
      sleep 0.2
      waiter.raise("stopped")
      p waiter.value
      collector = Lota::Thread::Thread.new(<<~CODE)
        require "set"
        5.times { Array.new(100_000) { |i| i.to_s }; GC.start }
        Lota::Thread.channel("out").push(GC.count > 0)
      CODE
      collector.start
      p CHANNEL.demand(30)
      collector.wait
    RUBY

    assert_equal "\"stopped\"\ntrue\n", output
  end

  # Thread:start, wait, isRunning, and getError (wrap_LuaThread.cpp):
  # start returns false while the thread runs and true once it has ended,
  # its arguments arrive in its ARGV, a FileData's thread is named after
  # its file, which its errors name, and the threaderror message LÖVE
  # pushes (LuaThread::onError) carries the thread, which the default
  # Lota.threaderror raises in the game, as love.threaderror does
  # (callbacks.lua:211-213).
  def test_a_thread_runs_again_takes_arguments_and_reports_its_error
    output = run_script(<<~RUBY)
      thread = Lota::Thread::Thread.new("Lota::Thread.channel('gate').demand\\nLota::Thread.channel('out').push(ARGV)\\n")
      p thread.start(1, :two, "three"), thread.start, thread.running?
      Lota::Thread.channel("gate").push(:go)
      thread.wait
      p CHANNEL.pop, thread.running?, thread.error
      Lota::Thread.channel("gate").push(:again)
      p thread.start(4), (thread.wait; CHANNEL.pop)
      bad = Lota::Thread::Thread.new(Lota::Filesystem::FileData.new("x = 1\\nraise ArgumentError, 'bad'\\n", "worker.rb"))
      bad.start
      bad.wait
      puts bad.error.lines.first
      Lota::Event.pump
      name, failed, error = Lota::Event.poll.find { |message| message.first == :threaderror }
      p name, failed == bad, failed.to_s == bad.to_s, error == bad.error
      begin
        Lota::Callbacks.handle(name, failed, error)
      rescue RuntimeError => e
        puts e.message.lines.first(3).join
      end
    RUBY

    lines = output.lines
    assert_equal ["true\n", "false\n", "true\n", "[1, :two, \"three\"]\n", "false\n", "nil\n", "true\n", "[4]\n"], lines.first(8)
    assert_match(/\Aworker\.rb:2:in .*: bad \(ArgumentError\)$/, lines[8])
    assert_equal [":threaderror\n", "true\n", "true\n", "true\n"], lines[9, 4]
    assert_match(/\AThread error \(Thread: 0x\h+\)\n\nworker.rb:2/, lines[13..].join)
  end

  # Ruby warns once, as a process makes its first Ractor, that Ractors are
  # experimental. Lota turns that warning off while it starts a thread,
  # and puts the setting back as it was.
  def test_starting_a_thread_prints_no_warning_and_keeps_the_setting
    output = run_script(<<~RUBY)
      p Warning[:experimental]
      run_thread("1 + 1\\n")
      p Warning[:experimental]
    RUBY

    assert_equal "true\ntrue\n", output
  end
end
