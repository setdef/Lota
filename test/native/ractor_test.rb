# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# Ractors other than the main one reach the engine as LÖVE's threads do
# (ADR 007; doc/contributors/design/engine.md, "Threads and Ractors"):
# every module but those Lota keeps on the main Ractor answers there, and
# graphics and window raise ThreadError, as on any thread but the main
# one. Each test runs its script in a Ruby of its own
# (NativeHelper#ruby_of_its_own), under rake test:native under the
# sanitizers, and compares what the script prints.
class RactorTest < Minitest::Test
  include NativeHelper

  # Opens the modules a script uses, without a window, and turns off
  # Ruby's warning that Ractors are experimental.
  SETUP = <<~RUBY
    require "lota"
    Warning[:experimental] = false
    Lota::Native::Filesystem.open
    Lota::Native::Filesystem.init($PROGRAM_NAME)
    %i[Data Timer Event Math Physics Image Sound].each { |name| Lota::Native.const_get(name).open }
    $stdout.sync = true
  RUBY

  def run_script(script, timeout: 120)
    output, status = ruby_of_its_own("-e", SETUP + script, timeout:)
    assert_predicate status, :success?, output
    output
  end

  # A Ractor uses the modules LÖVE lets a thread use: the math module's
  # generator, a Transform, a FileData, the timer, and a World that steps
  # and calls back a contact callback the engine holds as a root of Ruby's
  # collector, made from that Ractor and kept through a collection.
  def test_the_modules_loves_threads_may_use_answer_in_another_ractor
    output = run_script(<<~RUBY)
      p(Ractor.new do
        world = Lota::Physics::World.new(0, 10)
        body = Lota::Physics::Body.new(world, 0, 0, :dynamic)
        Lota::Physics::CircleShape.new(body, 1)
        Lota::Physics::Body.new(world, 0, 3, :static).then { |ground| Lota::Physics::RectangleShape.new(ground, 10, 1) }
        touched = []
        world.callbacks = ->(*) { touched << :begin }, nil, nil, nil
        GC.start
        60.times { world.update(1.0 / 60) }
        [Lota::Native::Math.random_generator.object_type,
          Lota::Math::Transform.new.translate(2, 3).transform_point(1, 1),
          Lota::Filesystem.new_file_data("abc", "a.txt").first.string,
          Lota::Timer.time.class, body.y > 0, touched.first]
      end.value)
    RUBY

    assert_equal %(["RandomGenerator", [3.0, 4.0], "abc", Float, true, :begin]\n), output
  end

  # LÖVE keeps love.graphics and love.window off its threads
  # (vendor/love/src/modules/thread/LuaThread.cpp:71-73): in another
  # Ractor, which runs on a thread of its own, their functions raise
  # ThreadError, as on any thread but the main one. Every other module
  # answers there, as keyboard does, which LÖVE lets a thread load.
  def test_graphics_and_window_stay_on_the_main_thread
    output = run_script(<<~RUBY)
      Ractor.new do
        [-> { Lota::Native::Graphics.open? }, -> { Lota::Native::Window.open },
          -> { Lota::Native::Keyboard.open? }].map do |call|
          call.call
          :called
        rescue ThreadError => e
          [e.class.name, e.message]
        end
      end.value.each { |result| p result }
    RUBY

    assert_equal <<~OUTPUT, output
      ["ThreadError", "Lota::Graphics runs only on the main thread"]
      ["ThreadError", "Lota::Window runs only on the main thread"]
      :called
    OUTPUT
  end

  # Each Ractor keeps the wrappers of the engine objects it reads: one for
  # each object while it lives, as on the main Ractor, so the math module's
  # generator read twice is one Ruby object in a Ractor, and another one,
  # never the main Ractor's, which Ractors may not share. Ractors that wrap
  # objects at once, and collect them, leave every map whole, and the
  # roots Rice keeps for the values it holds too, which Ruby 4.1 keeps for
  # each Ractor (ADR 013).
  def test_each_ractor_has_one_wrapper_of_its_own_for_each_object
    output = run_script(<<~RUBY)
      main = Lota::Native::Math.random_generator
      first, again, frozen = Ractor.new do
        generator = Lota::Native::Math.random_generator
        [generator.object_id, generator.equal?(Lota::Native::Math.random_generator), generator.frozen?]
      end.value
      p [first == main.object_id, again, frozen, main.equal?(Lota::Native::Math.random_generator)]
      p(4.times.map do
        Ractor.new do
          2000.times.count do |i|
            world = Lota::Native::Physics.new_world(0.0, 0.0, true)
            body = Lota::Native::Physics.new_body(world, 0.0, 0.0, "dynamic")
            GC.start if (i % 500).zero?
            !body.world.equal?(world)
          end
        end
      end.map(&:value))
    RUBY

    assert_equal "[false, true, false, true]\n[0, 0, 0, 0]\n", output
  end

  # Lota::Timer.sleep lets go of its GVL, so a collection the main Ractor
  # starts while another Ractor sleeps, which waits for every Ractor that
  # holds its GVL, ends long before the sleep does.
  def test_a_sleeping_ractor_does_not_hold_up_the_collector
    output = run_script(<<~RUBY)
      port = Ractor::Port.new
      sleeper = Ractor.new(port) do |started|
        started << :sleeping
        Lota::Timer.sleep(1)
      end
      port.receive
      sleep 0.1
      start = Lota::Timer.time
      GC.start
      p Lota::Timer.time - start < 0.5
      sleeper.join
    RUBY

    assert_equal "true\n", output
  end

  # Every Data guards its bytes with LÖVE's own lock, so its wrapper is
  # frozen and Ractors share it, as love.thread's channels pass LÖVE's
  # objects: another Ractor reads and changes the same bytes.
  def test_a_data_crosses_ractors_as_itself
    output = run_script(<<~RUBY)
      data = Lota::Data::ByteData.new("hello")
      p Ractor.shareable?(data)
      p(Ractor.new(data) do |shared|
        shared.uint8 = 0, 106
        shared.string
      end.value)
      p data.string
    RUBY

    assert_equal "true\n\"jello\"\n\"jello\"\n", output
  end

  # Two threads that hold one Data with perform_atomic take turns, and a
  # block that sleeps or collects garbage while the other waits ends: the
  # waiting thread waits without its GVL, which the holder needs to run
  # on in its own Ractor, and which a collection waits for in another.
  def test_perform_atomic_takes_turns_without_holding_up_the_holder
    output = run_script(<<~RUBY, timeout: 30)
      data = Lota::Data::ByteData.new(1)
      order = Thread::Queue.new
      holder = Thread.new do
        data.perform_atomic do
          order << :holding
          sleep 0.2
          GC.start
          order << :first
        end
      end
      order.pop
      waiter = Thread.new { data.perform_atomic { order << :second } }
      [holder, waiter].each(&:join)
      other = Ractor.new(data) { |shared| shared.perform_atomic { :other } }
      data.perform_atomic { sleep 0.2; GC.start }
      p [order.pop, order.pop, other.value]
    RUBY

    assert_equal "[:first, :second, :other]\n", output
  end
end
