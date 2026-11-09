# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"

# The test-only extension (ext/lota/native_test) is never copied into lib;
# it stays in the build tree that compiled it. It goes last on the load
# path, so under rake test:native the sanitized tree, which comes first,
# provides it.
$LOAD_PATH.push(File.expand_path("../../tmp/engine/build/lib", __dir__))
require "lota_native_test"

# Helpers for tests of the extensions.
module NativeHelper
  ROOT = File.expand_path("../..", __dir__)

  # The environment for build tools the tests run. Under rake test:native
  # this process carries DYLD_INSERT_LIBRARIES, or LD_PRELOAD on Linux,
  # which would load ASan into the compiler and nm too; they are not built
  # for it.
  TOOL_ENV = { "DYLD_INSERT_LIBRARIES" => nil, "LD_PRELOAD" => nil }.freeze

  # The environment that loads +libraries+ into a program before anything
  # else: with DYLD_INSERT_LIBRARIES on macOS, and LD_PRELOAD on Linux,
  # after a sanitizer runtime this process was started with, which ASan
  # needs first on Linux (tasks/sanitized_build.rb).
  def self.preload(*libraries)
    return { "DYLD_INSERT_LIBRARIES" => libraries.join(":") } unless TestHome::LINUX

    { "LD_PRELOAD" => [ENV.fetch("LD_PRELOAD", nil), *libraries].compact.join(" ") }
  end

  # On Linux, the libraries in the build tree's +lib+ that a program which
  # calls LotaNativeTest.press_return_on_dialogs, or whose Lua presses
  # Return on dialogs, needs loaded (ext/lota/native_test/
  # answer_dialogs_linux.cpp). On macOS the test extension presses it
  # through AppKit, and needs none.
  def self.dialogs(lib)
    TestHome::LINUX ? [File.join(lib, "liblota_dialogs.so")] : []
  end

  # Runs +command+ and returns its standard output and standard error,
  # interleaved, and its Process::Status, as Open3.capture2e does.
  # +environment+ changes this process's environment for the command, and
  # a nil value removes a variable. Open3 forks, and under rake test:native
  # a forked child can die before it runs the command (LotaNativeTest.spawn,
  # ext/lota/native_test/native_test.cpp), so this starts it with
  # posix_spawn instead.
  def capture2e(environment, *command)
    variables = ENV.to_h.merge(environment).compact.map { |name, value| "#{name}=#{value}" }
    reader, writer = IO.pipe
    begin
      pid = NativeHelper.spawn(command, writer, variables)
    ensure
      writer.close
    end
    output = reader.read
    [output, Process.wait2(pid).last]
  ensure
    reader&.close
  end

  # Starts +command+ with exactly +variables+ (NAME=value strings), its
  # standard input reading nothing and its standard output and error
  # writing to the IO +output+, and returns its process ID. Ruby forks to
  # start a process on macOS and Linux, so there the test extension starts
  # it with posix_spawn (LotaNativeTest.spawn); Windows has no fork, and
  # Ruby starts it there with CreateProcess, as LotaNativeTest.spawn would.
  def self.spawn(command, output, variables)
    return LotaNativeTest.spawn(command, output.fileno, variables) unless TestHome::WINDOWS

    environment = variables.to_h { |variable| variable.split("=", 2) }
    Process.spawn(environment, *command, unsetenv_others: true, in: File::NULL, out: output, err: output)
  end

  # Where the running process loaded a bundle from.
  def loaded(feature)
    $LOADED_FEATURES.find { |path| path.end_with?("/#{feature}.#{RbConfig::CONFIG['DLEXT']}") } or
      flunk "#{feature} is not loaded"
  end

  # Runs the block on a thread of its own and waits for it. Ruby's
  # collector also treats any word on a thread's machine stack that looks
  # like an object as a reference, so an object the block made can outlive
  # the block on this thread's stack; a finished thread's stack is gone.
  def on_a_finished_thread(&)
    Thread.new(&).join
    nil
  end

  # Runs the block in a Fiber of its own, on this thread, and waits for it
  # to finish. Graphics objects can be made only on the main thread, so
  # on_a_finished_thread cannot make them; a finished Fiber's stack is gone
  # too, and the collector no longer scans it.
  def on_a_finished_fiber(&block)
    Fiber.new do
      block.call
      nil
    end.resume
    nil
  end

  # How many wrappers of +klass+ from +generation+ are still alive. Ruby's
  # collector reads every thread's machine stack conservatively: a word
  # left there by earlier work that happens to hold the address of a slot
  # a new wrapper has since taken keeps that wrapper alive, as it must. A
  # test that drops many wrappers can find a few of them still alive, so
  # it counts the survivors rather than expecting none.
  def live_wrappers(klass, generation)
    ObjectSpace.each_object(klass).count { |wrapper| wrapper.generation == generation }
  end

  # The namespaces of the classes that wrap engine objects, in Lota::Native
  # and in the test extension.
  WRAPPER_NAMESPACES = %w[Lota::Native:: LotaNativeTest::].freeze

  # Every wrapper of an engine object that is alive now, from either
  # bundle. A test that holds them knows that a collection it runs frees
  # only wrappers it made itself. They are gathered on a finished Fiber,
  # so no word the search leaves on this thread's machine stack keeps a
  # wrapper made later alive (on_a_finished_fiber).
  def engine_wrappers
    wrappers = []
    on_a_finished_fiber do
      ObjectSpace.each_object(Object) do |object|
        wrappers << object if object.class.name&.start_with?(*WRAPPER_NAMESPACES)
      end
    end
    wrappers
  end

  # A full collection that sweeps before it returns.
  def collect_garbage
    GC.start(full_mark: true, immediate_sweep: true)
  end

  # Asserts that +read+, which returns the wrapper of one engine object
  # each time, never returns a wrapper Ruby's collector has found dead.
  #
  # Each round reads the object once on a finished Fiber, which drops the
  # wrapper, then runs a full collection that marks and leaves the sweep
  # for later, as Ruby's collector does between frames of a game, and
  # reads the object again. A wrapper the marking found dead is freed
  # whenever the sweep reaches its page, even if Ruby holds it again by
  # then, so a read that returns it hands Ruby an object about to be
  # freed. The round knows the first wrapper by its object_id and asks an
  # ObjectSpace::WeakMap, which the collector clears of the objects it
  # finds dead before it sweeps, whether it survived the marking.
  def assert_never_reads_back_a_dead_wrapper(rounds: 100, &read)
    rounds.times do |round|
      dropped = ObjectSpace::WeakMap.new
      id = nil
      on_a_finished_fiber do
        wrapper = read.call
        id = wrapper.object_id
        dropped[0] = wrapper
      end
      GC.start(full_mark: true, immediate_sweep: false)
      returned_dropped = read.call.object_id == id
      survived = dropped.key?(0)
      collect_garbage
      refute returned_dropped && !survived,
        "round #{round} read back the wrapper the collector had found dead and would then free"
    end
  end

  # A full collection on a thread that is not the main thread, so every
  # wrapper it frees is freed off the main thread. The collector stays off
  # until then, so nothing frees those wrappers on this thread first.
  def collect_garbage_off_the_main_thread
    GC.disable
    yield if block_given?
    Thread.new { collect_garbage }.join
  ensure
    GC.enable
  end
end
