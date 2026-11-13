# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# Lota::Thread's threads run in Ractors, and so do these tests, each in a
# Ruby of its own (NativeHelper#ruby_of_its_own), which runs the engine's
# native layer from Ractors other than the main one: under rake
# test:native, under the sanitizers. Each script prints what the test
# compares, one line at a time.
class ThreadModuleTest < Minitest::Test
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
    %i[Data Thread Timer Event Math Physics Image Sound Font].each { |name| Lota::Native.const_get(name).open }
    Lota::Native::Audio.open
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
        out.push(Lota::Filesystem.new_file_data("abc", "a.txt").first.string)
        out.push(Lota::Timer.time.class)
        world = Lota::Physics::World.new(0, 10)
        body = Lota::Physics::Body.new(world, 0, 0, :dynamic)
        Lota::Physics::CircleShape.new(body, 1)
        world.callbacks = ->(a, b, contact) {}, nil, nil, nil
        world.update(1)
        GC.start
        out.push(body.y > 0)
        source = Lota::Audio::Source.new(Lota::Sound::SoundData.new(441, 44_100, 16, 1))
        out.push([Lota::Audio.volume, source.play, Lota::Native::Font.open?])
        source.stop
      CODE
      Lota::Math.random_seed = 3
      puts CHANNEL.pop == Lota::Math.random(1000)
      p CHANNEL.pop
      puts CHANNEL.pop == File.binread(#{File.join(GAME, 'conf.rb').dump}).bytesize
      p CHANNEL.pop, CHANNEL.pop, CHANNEL.pop, CHANNEL.pop
    RUBY

    assert_equal "true\n[3.0, 4.0]\ntrue\n\"abc\"\nFloat\ntrue\n[1.0, true, true]\n", output
  end

  # LÖVE keeps love.graphics and love.window off its threads
  # (LuaThread.cpp:71-73): lota.graphics and lota.window are nil in a
  # thread's code, and their functions raise ThreadError, as on any thread
  # but the main one. lota.thread is there.
  def test_graphics_and_window_stay_on_the_main_thread
    output = run_script(<<~RUBY)
      run_thread(<<~CODE)
        out = Lota::Thread.channel("out")
        out.push([Lota.graphics, Lota.window, Lota.thread == Lota::Thread])
        begin
          Lota::Graphics.dimensions
        rescue ThreadError => e
          out.push(e.message)
        end
      CODE
      2.times { p CHANNEL.pop }
    RUBY

    assert_equal "[nil, nil, true]\n\"Lota::Graphics runs only on the main thread\"\n", output
  end

  # LÖVE requires love.filesystem in each thread before its code runs, so
  # that the thread's require finds the game's files
  # (LuaThread::threadFunction, LuaThread.cpp:78-82). A Lota thread's
  # require finds them on the game's $LOAD_PATH, where Lota::Boot puts the
  # game's folder, and Ruby 4.1 loads them in the main Ractor.
  def test_a_threads_require_finds_the_games_files
    Dir.mktmpdir do |game|
      File.write(File.join(game, "helper.rb"), "module ThreadHelper\n  ANSWER = 42\nend\n")
      output = run_script(<<~RUBY)
        $LOAD_PATH.unshift(#{game.dump})
        run_thread("require 'helper'\\nLota::Thread.channel('out').push(ThreadHelper::ANSWER)\\n")
        p CHANNEL.pop
      RUBY

      assert_equal "42\n", output
    end
  end

  # LÖVE lets a thread load every module but love.window and love.graphics
  # (LuaThread.cpp:71-73), the input modules among them, which answer there
  # as on the main thread: the same engine module, read from another
  # thread.
  def test_the_input_and_system_modules_answer_in_a_thread_as_on_the_main_one
    output = run_script(<<~RUBY)
      %i[Keyboard Joystick Mouse Touch Sensor System].each { |name| Lota::Native.const_get(name).open }
      CALLS = <<~CODE
        [Lota::Keyboard.down?(:a), Lota::Keyboard.key_repeat?, Lota::Joystick.joystick_count,
          Lota::Mouse.down?(1), Lota::Touch.touches, Lota::Sensor.sensor?(:accelerometer), Lota::System.os,
          Lota::System.processor_count, [Lota.keyboard, Lota.joystick, Lota.mouse, Lota.touch, Lota.sensor,
          Lota.system].map(&:name)]
      CODE
      p eval(CALLS)
      run_thread("Lota::Thread.channel('out').push(eval(ARGV.first))\\n", CALLS)
      p CHANNEL.pop
    RUBY

    main, thread = output.lines

    assert_equal main, thread
    assert_match(/\A\[false, false, 0, false, \[\], (?:true|false), "[^"]+", \d+, \["Lota::Keyboard", /, main)
  end

  # A Channel carries a copy of what was pushed, as LÖVE's carries a
  # Variant, and each pop, demand, or peek hands back a fresh value the
  # receiver may change, as LÖVE pushes a new table each time: a String,
  # an Array, or a Hash, all through, arrives unfrozen, whatever thread
  # pops it. Numbers, Symbols, nil, and booleans arrive as themselves.
  # Lota's objects arrive as the same engine objects, as LÖVE passes its
  # objects, through wrappers of the receiver's own. Pushing a Proc raises
  # ArgumentError, as LÖVE refuses a Lua function.
  def test_a_channel_hands_back_fresh_values_the_receiver_may_change
    output = run_script(<<~RUBY)
      text = +"text"
      list = [1, [2], "three", { "key" => ["value"] }]
      data = Lota::Filesystem.new_file_data("bytes", "b.bin").first
      inner = Lota::Thread::Channel.new
      [3, :symbol, 1.5, nil, true, text, list, data, inner].each { |value| CHANNEL.push(value) }
      p CHANNEL.pop, CHANNEL.pop, CHANNEL.pop, CHANNEL.pop, CHANNEL.pop
      copy = CHANNEL.pop
      p [copy, copy.frozen?, copy.equal?(text), text.frozen?]
      first = CHANNEL.peek
      copy = CHANNEL.pop
      p [copy, first.equal?(copy), [copy, copy[1], copy[2], copy[3], copy[3]["key"]].map(&:frozen?), list.frozen?]
      p CHANNEL.pop == data, CHANNEL.pop == inner, Ractor.shareable?(data), data.frozen?
      [-> {}, method(:puts)].each do |value|
        CHANNEL.push(value)
      rescue ArgumentError => e
        puts e.message
      end
      p CHANNEL.count
      Lota::Thread.channel("in").push(["from", "main"])
      run_thread(<<~CODE, "argument")
        message = Lota::Thread.channel("in").pop
        message << "changed"
        message.first << "!"
        ARGV.first << "!"
        Lota::Thread.channel("out").push([message, ARGV, ARGV.frozen?])
      CODE
      p CHANNEL.pop
    RUBY

    assert_equal <<~OUTPUT, output
      3
      :symbol
      1.5
      nil
      true
      ["text", false, false, false]
      [[1, [2], "three", {"key" => ["value"]}], false, [false, false, false, false, false], false]
      true
      true
      false
      true
      bad argument #1 to 'push' (boolean, number, string, love type, or table expected)
      bad argument #1 to 'push' (boolean, number, string, love type, or table expected)
      0
      [["from!", "main", "changed"], ["argument!"], false]
    OUTPUT
  end

  # LÖVE's Channel carries any of its objects as itself (Variant), with no
  # lock of its own, and the thread that pops one gets a userdata of its
  # own Lua state for the same object. So a Transform, whose wrapper
  # Ractors do not share, crosses as itself, alone, in an Array, or in a
  # Hash, and as a thread's argument: what the thread does to it, the main
  # thread sees, and what comes back is the main thread's own wrapper of
  # the same object.
  def test_an_engine_object_crosses_threads_as_itself
    output = run_script(<<~RUBY)
      transform = Lota::Math::Transform.new
      Lota::Thread.channel("in").push([transform, { "again" => transform }])
      run_thread(<<~CODE, transform)
        message = Lota::Thread.channel("in").pop
        alone, held = message
        alone.translate(5, 0)
        ARGV.first.translate(0, 2)
        out = Lota::Thread.channel("out")
        out.push([alone.object_type, alone == held["again"], alone == ARGV.first, held["again"].transform_point(0, 0)])
        out.push(alone)
      CODE
      p CHANNEL.pop
      p transform.transform_point(0, 0)
      back = CHANNEL.pop
      p [back.class, back == transform]
    RUBY

    assert_equal <<~OUTPUT, output
      ["Transform", true, true, [5.0, 2.0]]
      [5.0, 2.0]
      [Lota::Math::Transform, true]
    OUTPUT
  end

  # Each thread holds an object it receives through a wrapper of its own,
  # as each of LÖVE's Lua states holds a userdata of its own, so a release
  # in one thread ends only that thread's use of the object, as w__release
  # clears only its own Proxy (runtime.cpp:170-197): the main thread's
  # ByteData still reads the same bytes, and the thread, handed the object
  # again, gets a new wrapper, as LÖVE pushes a new userdata.
  def test_a_release_in_one_thread_leaves_the_object_to_the_others
    output = run_script(<<~RUBY)
      data = Lota::Data::ByteData.new("abc")
      2.times { Lota::Thread.channel("in").push(data) }
      run_thread(<<~CODE)
        theirs = Lota::Thread.channel("in").pop
        out = Lota::Thread.channel("out")
        out.push([theirs.string, theirs.release, theirs.release])
        begin
          theirs.string
        rescue RuntimeError => e
          out.push(e.message)
        end
        again = Lota::Thread.channel("in").pop
        out.push(again.string)
      CODE
      3.times { p CHANNEL.pop }
      p data.string, data.size
    RUBY

    assert_equal <<~OUTPUT, output
      ["abc", true, false]
      "Cannot use object after it has been released."
      "abc"
      "abc"
      3
    OUTPUT
  end

  # A World, a Body, a Shape, or a Joint crosses to another thread as the
  # same engine object, but the Ruby values the game set on it, its user
  # data and a World's callbacks, stay with the thread that set them: Ruby
  # lets no other Ractor touch them, as in LÖVE they live in the registry
  # of the Lua state that set them. Another thread that reads them, or
  # whose World#update would call them, meets Ractor::IsolationError, and
  # what it sets is its own. The update that meets it stays locked, as a
  # World does in LÖVE after an error in a callback, so another World is
  # stepped there; the first is destroyed, with the values set in both
  # threads, in the main one.
  def test_ruby_values_set_on_an_engine_object_stay_with_the_thread_that_set_them
    output = run_script(<<~RUBY)
      world = Lota::Physics::World.new(0, 0)
      body = Lota::Physics::Body.new(world, 1, 2, :dynamic)
      body.user_data = { "set" => "in main" }
      world.callbacks = [-> {}]
      stepped = Lota::Physics::World.new(0, 0)
      2.times { Lota::Physics::CircleShape.new(Lota::Physics::Body.new(stepped, 1, 2, :dynamic), 1) }
      stepped.callbacks = [-> {}]
      Lota::Thread.channel("in").push([world, body, stepped])
      run_thread(<<~CODE)
        world, body, stepped = Lota::Thread.channel("in").pop
        out = Lota::Thread.channel("out")
        out.push(body.position)
        [-> { body.user_data }, -> { world.callbacks }, -> { stepped.update(0.1) }].each do |read|
          read.call
          out.push(:read)
        rescue Ractor::IsolationError => e
          out.push(e.message)
        end
        body.user_data = "set in the thread"
        out.push(body.user_data)
      CODE
      5.times { p CHANNEL.pop }
      begin
        body.user_data
      rescue Ractor::IsolationError => e
        p e.message
      end
      3.times { GC.start(full_mark: true, immediate_sweep: true) }
      world.destroy
      3.times { GC.start(full_mark: true, immediate_sweep: true) }
      p world.destroyed?
    RUBY

    elsewhere = "this Ruby value was set in another thread, whose Ractor alone may use it"
    assert_equal <<~OUTPUT, output
      [1.0, 2.0]
      #{elsewhere.dump}
      #{elsewhere.dump}
      #{elsewhere.dump}
      "set in the thread"
      #{elsewhere.dump}
      true
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
      bad = Lota::Thread::Thread.new(Lota::Filesystem.new_file_data("x = 1\\nraise ArgumentError, 'bad'\\n", "worker.rb").first)
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

  # A thread's error is kept as Ruby prints it, and printing an error
  # first fires the autoloads of the gems that decorate the message
  # (error.c, require_decoration_gems). An autoload fired in a Ractor
  # other than the main one, after $LOAD_PATH changed, as Lota::Boot
  # changes it, rebuilt the expanded load path that every Ractor shares
  # from that Ractor's own objects, and the next collection after the
  # Ractor ended marked them, freed, and crashed Ruby, whether $LOAD_PATH
  # changed before the thread started or while it ran.
  def test_a_thread_that_raises_after_load_path_changes_leaves_nothing_freed_behind
    output = run_script(<<~RUBY)
      $LOAD_PATH.unshift(Dir.pwd)
      thread = Lota::Thread::Thread.new("raise 'early'\\n")
      thread.start
      thread.wait
      later = Lota::Thread::Thread.new("Lota::Thread.channel('gate').demand\\nraise 'later'\\n")
      later.start
      $LOAD_PATH.unshift(File.join(Dir.pwd, "elsewhere"))
      Lota::Thread.channel("gate").push(:go)
      later.wait
      3.times { GC.start }
      puts thread.error.lines.first, later.error.lines.first
    RUBY

    assert_match(/\Astring:1:in .*: early \(RuntimeError\)\nstring:2:in .*: later \(RuntimeError\)\n\z/, output)
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
