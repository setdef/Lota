# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
  # this process carries DYLD_INSERT_LIBRARIES, which would load ASan into
  # the compiler and nm too; they are not built for it.
  TOOL_ENV = { "DYLD_INSERT_LIBRARIES" => nil }.freeze

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
      pid = LotaNativeTest.spawn(command, writer.fileno, variables)
    ensure
      writer.close
    end
    output = reader.read
    [output, Process.wait2(pid).last]
  ensure
    reader&.close
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

  # A full collection that sweeps before it returns.
  def collect_garbage
    GC.start(full_mark: true, immediate_sweep: true)
  end
end
