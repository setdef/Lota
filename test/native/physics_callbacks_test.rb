# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# A World's contact callbacks and contact filter beyond what Lövetest's
# tests check (test/lovetest/tests/physics.rb): what World:getCallbacks
# gives back, when each callback runs within World:update and with what,
# as World::ContactCallback::process passes it (ext/lota/engine/
# physics.patch, World.cpp), the Contact destroyed after endContact
# (World::EndContact), destruction deferred to the end of the step
# (World::update), an error raised from a callback, and the garbage
# collector's view of the callables a World holds.
class PhysicsCallbacksTest < Minitest::Test
  include NativeHelper

  Physics = Lota::Physics

  # Something that answers call and is neither a Proc nor a Method, as a
  # game's own callback object may be.
  class Recorder
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(*arguments)
      @calls << arguments
      true
    end
  end

  def setup
    EngineHelper.open_window
    Physics.meter = 30
    @world = Physics::World.new(0, 0, false)
    @body1 = Physics::Body.new(@world, 0, 0, :dynamic)
    @body2 = Physics::Body.new(@world, 5, 0, :dynamic)
    @shape1 = Physics::RectangleShape.new(@body1, 10, 10)
    @shape2 = Physics::RectangleShape.new(@body2, 10, 10)
  end

  # Moves the bodies apart and steps, so their contact ends.
  def separate
    @body2.position = 100, 100
    @world.update(1 / 60.0)
  end

  def test_a_world_has_no_callbacks_or_filter_at_first
    assert_equal [nil, nil, nil, nil], @world.callbacks
    assert_nil @world.contact_filter
  end

  # luax_refif keeps each function given, and getCallbacks pushes each
  # back as it was (World.cpp, setCallbacks and getCallbacks), nil for
  # those not given.
  def test_callbacks_gives_back_exactly_what_was_set
    begin_contact = -> {}
    recorder = Recorder.new
    post_solve = method(:separate)
    @world.callbacks = begin_contact, nil, recorder, post_solve

    assert_same begin_contact, @world.callbacks[0]
    assert_nil @world.callbacks[1]
    assert_same recorder, @world.callbacks[2]
    assert_equal post_solve, @world.callbacks[3]

    @world.callbacks = recorder
    assert_equal [recorder, nil, nil, nil], @world.callbacks
    @world.callbacks = nil
    assert_equal [nil, nil, nil, nil], @world.callbacks
    @world.contact_filter = recorder
    assert_same recorder, @world.contact_filter
    @world.contact_filter = nil
    assert_nil @world.contact_filter
  end

  # setCallbacks checks every function before it replaces any.
  def test_a_callback_that_answers_no_call_raises_and_changes_nothing
    kept = -> {}
    @world.callbacks = kept
    error = assert_raises(TypeError) { @world.callbacks = -> {}, 5 }

    assert_equal "wrong argument type Integer (expected an object that answers call)", error.message
    assert_same kept, @world.callbacks.first
    assert_raises(TypeError) { @world.contact_filter = "no" }
    assert_nil @world.contact_filter
  end

  # Box2D begins a contact and presolves it in the step's collision pass,
  # postsolves it after the solver, and ends it in a later step's pass,
  # once the shapes part; each gets the two Shapes and the Contact, and
  # postsolve each contact point's normal and tangent impulse.
  def test_each_callback_runs_in_the_step_with_the_shapes_and_the_contact
    events = []
    record = -> (name) { -> (*arguments) { events << [name, @world.locked?, *arguments] } }
    @world.callbacks = record.(:begin), record.(:end), record.(:pre), record.(:post)
    @world.update(1 / 60.0)

    assert_equal %i[begin pre post], events.map(&:first).uniq
    assert(events.all? { |event| event[1] }, "the World is locked while they run")
    _, _, a, b, contact, *impulses = events.find { |event| event.first == :post }
    assert_equal [@shape1, @shape2].to_set, [a, b].to_set
    assert_instance_of Physics::Contact, contact
    refute_empty impulses
    assert_predicate impulses.size, :even?
    assert(impulses.all?(Float))
    assert_equal [5, 5], events.first(2).map(&:size)
    assert_same events[0][4], events[1][4], "one Contact while it lives"

    events.clear
    separate

    assert_equal [:end], events.map(&:first)
  end

  # ADR 003, section 3: each callback receives as many arguments as it
  # declares, nil for a required one LÖVE does not pass.
  def test_a_callback_receives_only_the_arguments_it_declares
    received = {}
    recorder = Recorder.new
    @world.callbacks = [
      -> { received[:begin] = true },
      proc { |a, b| received[:end] = [a, b] },
      -> (_a, _b, contact, extra) { received[:pre] = [contact, extra] },
      recorder,
]
    @world.update(1 / 60.0)

    assert received[:begin]
    assert_instance_of Physics::Contact, received[:pre][0]
    assert_nil received[:pre][1]
    refute_empty recorder.calls
    assert(recorder.calls.all? { |arguments| arguments.size.odd? && arguments.size >= 5 }, "every impulse")
    separate

    assert_equal [@shape1, @shape2].to_set, received[:end].to_set
  end

  def test_post_solve_receives_nil_for_impulses_beyond_the_contact_points
    received = nil
    @world.callbacks = nil, nil, nil, -> (_a, _b, _contact, n1, t1, n2, t2, n3) { received = [n1, t1, n2, t2, n3] }
    @world.update(1 / 60.0)

    assert_kind_of Float, received[0]
    assert_nil received[4]
  end

  # World::EndContact invalidates the Contact once endContact returns, so
  # a Contact kept from then on raises LÖVE's error.
  def test_a_contact_is_destroyed_after_end_contact
    ended = nil
    friction = nil
    @world.callbacks =
      nil,
      lambda { |_a, _b, contact|
        ended = contact
        friction = contact.friction
      }
    @world.update(1 / 60.0)
    separate

    assert_kind_of Float, friction
    error = assert_raises(RuntimeError) { ended.friction }
    assert_equal "Attempt to use destroyed contact.", error.message
  end

  # Body::destroy and World::destroy wait for the step to end while the
  # World is locked, and World::update carries them out.
  def test_what_a_callback_destroys_is_destroyed_once_the_step_ends
    during = nil
    @world.callbacks = lambda {
      @body2.destroy
      @world.destroy
      during = [@body2.destroyed?, @world.destroyed?]
    }
    @world.update(1 / 60.0)

    assert_equal [false, false], during
    assert_predicate @body2, :destroyed?
    assert_predicate @world, :destroyed?
    assert_equal "Attempt to use destroyed world.", assert_raises(RuntimeError) { @world.callbacks }.message
  end

  # A callback that replaces the callbacks deletes the function the World
  # is running; the new ones run from then on.
  def test_a_callback_may_replace_the_callbacks
    calls = []
    replacement = -> { calls << :replacement }
    @world.callbacks =
      nil,
      nil,
      lambda {
        calls << :first
        @world.callbacks = nil, nil, replacement
      }
    @world.update(1 / 60.0)
    @world.update(1 / 60.0)

    assert_equal :first, calls.first
    assert_includes calls, :replacement
    assert_same replacement, @world.callbacks[2]
  end

  # A Lua error in a callback leaves the step where it is raised and comes
  # out of World:update, and the World, whose step never finished, stays
  # locked; so does a Ruby error.
  def test_an_error_a_callback_raises_comes_out_of_update
    failure = Class.new(StandardError)
    calls = 0
    @world.callbacks = lambda {
      calls += 1
      raise failure, "from begin_contact"
    }
    error = assert_raises(failure) { @world.update(1 / 60.0) }

    assert_equal "from begin_contact", error.message
    assert_equal 1, calls
    assert_predicate @world, :locked?
  end

  # World::ShouldCollide asks the filter after LÖVE's group and mask
  # rules, with the two Shapes, and they collide only when it returns a
  # true value, as Lua's truth decides it: 0 is true.
  def test_the_contact_filter_decides_which_shapes_collide
    asked = []
    began = 0
    @world.callbacks = -> { began += 1 }
    @world.contact_filter = lambda { |a, b|
      asked << [a, b]
      nil
    }
    @world.update(1 / 60.0)

    assert_equal 0, began
    assert_equal [@shape1, @shape2].to_set, asked.first.to_set

    world = Physics::World.new(0, 0, false)
    Physics::CircleShape.new(Physics::Body.new(world, 0, 0, :dynamic), 5)
    Physics::CircleShape.new(Physics::Body.new(world, 1, 0, :dynamic), 5)
    world.callbacks = -> { began += 1 }
    world.contact_filter = -> { 0 }
    world.update(1 / 60.0)

    assert_equal 1, began
  end

  # A Lua reference keeps its function in the registry while the World
  # holds it, however long nothing else refers to it; one the World
  # replaced, or let go of when destroyed, is the collector's.
  def test_a_world_keeps_its_callables_alive_until_it_lets_them_go
    held = Class.new(Recorder)
    replaced = Class.new(Recorder)
    on_a_finished_fiber do
      @world.callbacks = Array.new(4) { held.new }
      @world.contact_filter = held.new
    end
    collect_garbage
    GC.compact if GC.respond_to?(:compact)

    assert_equal 5, ObjectSpace.each_object(held).count
    @world.update(1 / 60.0)
    refute_empty @world.callbacks.first.calls

    on_a_finished_fiber do
      20.times { @world.callbacks = Array.new(4) { replaced.new } }
      @world.callbacks = nil
    end
    collect_garbage

    assert_operator ObjectSpace.each_object(replaced).count, :<, 40, "replaced callables are released"
    assert_operator ObjectSpace.each_object(held).count, :<, 5, "the four replaced first are released"
  end

  # World::destroy lets go of every callback and the filter.
  def test_a_destroyed_world_lets_its_callables_go
    held = Class.new(Recorder)
    on_a_finished_fiber do
      20.times do
        world = Physics::World.new(0, 0, false)
        world.callbacks = Array.new(4) { held.new }
        world.contact_filter = held.new
        world.destroy
      end
    end
    collect_garbage

    assert_operator ObjectSpace.each_object(held).count, :<, 50, "a destroyed World's callables are released"
  end
end
