# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "timeout"
require_relative "../test_helper"
require_relative "native_helper"

# A run of the tests has no one to press a button on a message box, and
# the system waits for one as long as the run lasts: SDL's zenity, its
# window of its own, an NSAlert or a task dialog never closes by itself.
# So every dialog but those a test asks to answer is refused, written with
# its title and message to standard error, and fails as SDL fails when it
# can show none, so a game that fails to start fails at once. On Linux
# liblota_dialogs does it (ext/lota/native_test/answer_dialogs_linux.cpp),
# loaded into every program the tests start (tasks/test_files.rb). On
# macOS and Windows the test extension does it in each Ruby process that
# loads it: the test process, and every Ruby a test starts
# (test/dialog_guard.rb), and no other program.
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

  def test_the_library_refuses_a_dialog_with_its_message_on_standard_error
    skip "liblota_dialogs is Linux's" unless TestHome::LINUX

    library = NativeHelper.dialogs(File.dirname(loaded("lota_native_test")))
    output, status = run_bounded(NativeHelper.preload(*library))

    assert_predicate status, :success?, output
    assert_includes output, "refused a message box"
    assert_includes output, "Initialization error: The window failed to start"
    assert_includes output, "Quit?: Really?"
    assert_includes output, "shown: false"
    assert_includes output, "buttons: 0"
  end

  def test_a_ruby_a_test_starts_refuses_dialogs_without_asking
    output, status = run_bounded({})

    assert_predicate status, :success?, output
    assert_includes output, "refused a message box"
    assert_includes output, "Initialization error: The window failed to start"
    assert_includes output, "Quit?: Really?"
    assert_includes output, "shown: false"
    assert_includes output, "buttons: 0"
  end

  # On Linux liblota_dialogs refuses them in every process, this one too.
  unless TestHome::LINUX
    def test_the_test_process_refuses_dialogs
      assert_predicate LotaNativeTest, :refusing_dialogs?
    end
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
