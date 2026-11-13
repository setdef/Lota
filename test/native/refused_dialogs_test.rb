# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "timeout"
require_relative "../test_helper"
require_relative "native_helper"

# A run of the tests has no one to press a button on a message box, and
# SDL waits for one as long as the run lasts: its zenity, or its window
# of its own, never closes by itself. On Linux liblota_dialogs refuses
# every dialog but those a test asks it to answer (ext/lota/native_test/
# answer_dialogs_linux.cpp), and the tests load it into every program
# they start (tasks/test_files.rb), so a game that fails to start fails
# at once, with what its dialog would have said on standard error. On
# macOS and Windows the harness presses the dialog's button on request
# (dialogs.mm, dialogs_windows.cpp) and nothing refuses one before then.
class RefusedDialogsTest < Minitest::Test
  # How long a program may take to show and refuse a dialog; a dialog
  # nobody answers takes the rest of the run.
  LIMIT = 30

  SCRIPT = <<~RUBY
    require "lota"
    Lota::Native::Window.open
    puts "shown: \#{Lota::Native::Window.show_message_box('Initialization error', 'The window failed to start', 'error', false)}"
    puts "buttons: \#{Lota::Native::Window.show_message_box_with_buttons('Quit?', 'Really?', %w[Yes No], nil, nil, 'warning', false)}"
  RUBY

  def setup
    skip "liblota_dialogs is Linux's" unless TestHome::LINUX
  end

  def test_the_library_refuses_a_dialog_with_its_message_on_standard_error
    library = NativeHelper.dialogs(File.dirname(loaded("lota_native_test")))
    output, status = run_bounded(NativeHelper.preload(*library))

    assert_predicate status, :success?, output
    assert_includes output, "refused a message box"
    assert_includes output, "Initialization error: The window failed to start"
    assert_includes output, "Quit?: Really?"
    assert_includes output, "shown: false"
    assert_includes output, "buttons: 0"
  end

  def test_a_program_a_test_starts_gets_the_library_without_asking_for_it
    output, status = run_bounded({})

    assert_predicate status, :success?, output
    assert_includes output, "Initialization error: The window failed to start"
    assert_includes output, "shown: false"
  end

  private def loaded(feature)
    $LOADED_FEATURES.find { |path| path.end_with?("/#{feature}.#{RbConfig::CONFIG['DLEXT']}") } or
      flunk "#{feature} is not loaded"
  end

  # Runs SCRIPT in a Ruby of its own with +environment+ added to this
  # process's, and fails the test, instead of hanging it, when a dialog
  # holds the program for LIMIT seconds.
  private def run_bounded(environment)
    native = File.dirname(File.dirname(loaded("lota/native")))
    load_path = [native, File.join(NativeHelper::ROOT, "lib")].join(File::PATH_SEPARATOR)
    variables = ENV.to_h.merge(environment).compact.map { |name, value| "#{name}=#{value}" }
    reader, writer = IO.pipe
    pid = NativeHelper.spawn([RbConfig.ruby, "-I#{load_path}", "-e", SCRIPT], writer, variables)
    writer.close
    begin
      Timeout.timeout(LIMIT) { [reader.read, Process.wait2(pid).last] }
    rescue Timeout::Error
      Process.kill("KILL", pid)
      Process.wait(pid)
      flunk "a message box held the program for #{LIMIT} seconds"
    end
  ensure
    reader&.close
  end
end
