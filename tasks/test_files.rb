# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/test_task"
require "shellwords"

# Which test files a test task runs. TEST, as Rake's own TestTask reads
# it, names files or globs, separated by commas, to run in place of the
# task's own; Minitest's TestTask, which Lota's test tasks are, never
# reads it, so without this rake test TEST=one_test.rb would run every
# test. A name that matches no file stops the task, rather than run
# nothing and pass.
module TestFiles
  def self.of(globs, env: ENV)
    named = env.fetch("TEST", "").split(",")
    return Dir[*globs].sort if named.empty?

    missing = named.select { |name| Dir[name].empty? }
    raise ArgumentError, "TEST names no test file: #{missing.join(', ')}" unless missing.empty?

    Dir[*named].sort
  end

  # The library that refuses the message boxes a test run shows
  # (ext/lota/native_test/answer_dialogs_linux.cpp). SDL shows a dialog
  # with zenity or a window of its own and waits for a button no one in an
  # unattended run can press, so a test whose game fails to start would
  # hold the run until its timeout. The build puts it beside the extensions.
  DIALOGS = File.expand_path("../tmp/engine/build/lib/liblota_dialogs.so", __dir__)

  # The variables that pick which tests a run runs: TEST above, and those
  # Minitest's TestTask reads (minitest/test_task.rb, make_test_cmd). A
  # task reads them as it starts its run, so the run itself starts without
  # them. A test that invokes a test task in its own process, as
  # test/tasks/rake_tasks_test.rb invokes test:native, would otherwise run
  # the files the outer run was told to: rake test:ruby
  # TEST=test/tasks/rake_tasks_test.rb ran that file again in test:native,
  # whose run ran it again, one process inside another, without end. A,
  # Minitest's options, still reaches the run, so A=--verbose names each
  # test of a nested run as well.
  SELECTION = %w[TEST TESTOPTS N I X E FILTER].to_h { |name| [name, nil] }.freeze

  # The environment a test run starts in: without SELECTION, and on Linux,
  # once the build has made DIALOGS, with the library loaded into the run
  # first, after whatever +env+ already preloads (a sanitizer's runtime has
  # to come first), so every program the tests start inherits it. On macOS
  # and Windows a library loaded into every program would reach the
  # system's programs too, which may not load it, so the test extension
  # refuses dialogs in the Ruby processes that load it instead
  # (test/dialog_guard.rb).
  def self.environment(env: ENV, library: DIALOGS, linux: RUBY_PLATFORM.include?("linux"))
    return SELECTION unless linux && File.exist?(library)

    SELECTION.merge("LD_PRELOAD" => [env.fetch("LD_PRELOAD", nil), library].compact.reject(&:empty?).join(" "))
  end

  # A Minitest::TestTask that runs the files TEST names, when it names
  # any. It reads TEST when it runs, not when the Rakefile loads. It runs
  # them in the environment above, which Minitest's own task, that calls
  # Rake's +ruby+, cannot give a program.
  class Task < Minitest::TestTask
    def define
      super
      defined = task(name)
      defined.clear_actions
      defined.enhance do
        sh(TestFiles.environment, RbConfig.ruby, *Shellwords.split(make_test_cmd), verbose:)
      end
    end

    def make_test_cmd(**option)
      super(**option, path: option.fetch(:path) { TestFiles.of(test_globs) })
    end
  end
end
