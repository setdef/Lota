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
  # (ext/lota/native_test/answer_dialogs_linux.cpp and
  # answer_dialogs_macos.cpp). The system shows a dialog and waits for a
  # button no one in an unattended run can press, so a test whose game
  # fails to start would hold the run until its timeout. The build puts it
  # beside the extensions.
  DIALOGS = File.expand_path(
    "../tmp/engine/build/lib/liblota_dialogs.#{RUBY_PLATFORM.include?('linux') ? 'so' : 'dylib'}", __dir__
  )

  # The environment a test run starts in: once the build has made DIALOGS,
  # the library loaded into the run first, after whatever +env+ already
  # loads (a sanitizer's runtime has to come first), so every program the
  # tests start inherits it. Nothing on Windows, which has no way to load a
  # library into a program before it starts: the test extension refuses
  # dialogs there as it loads (ext/lota/native_test/dialogs_windows.cpp).
  def self.environment(env: ENV, library: DIALOGS, platform: RUBY_PLATFORM)
    return {} if platform.match?(/mingw|mswin/) || !File.exist?(library)

    variable, separator = platform.include?("linux") ? ["LD_PRELOAD", " "] : ["DYLD_INSERT_LIBRARIES", ":"]
    { variable => [env.fetch(variable, nil), library].compact.reject(&:empty?).join(separator) }
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
