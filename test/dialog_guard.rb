# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# A message box nobody asked the tests to answer waits for a click that an
# unattended run cannot give: NSAlert's runModal on macOS, a task dialog on
# Windows. So a Ruby process the tests run refuses them: the test
# extension, as it loads, sends SDL's two message box functions to
# refusals of its own, which write the dialog's title and message to
# standard error and fail as SDL fails when it can show none, until
# LotaNativeTest.press_return_on_dialogs asks for them to be answered
# (ext/lota/native_test/dialogs.mm and dialogs_windows.cpp).
#
# It reaches only the Ruby processes that load it: the test process, whose
# test_helper.rb requires this file, and every Ruby a test starts through
# NativeHelper.spawn, which runs this file first (DialogGuard.command), so
# no other program a test starts is touched. On Linux liblota_dialogs
# refuses them in every program the tests start (tasks/test_files.rb), and
# this file does nothing.
module DialogGuard
  # Whether this system needs the guard in-process.
  NEEDED = !RUBY_PLATFORM.include?("linux")

  # Where the build tree keeps the test extension, which is never copied
  # into lib.
  BUILD = File.expand_path("../tmp/engine/build/lib", __dir__)

  # This file, which a Ruby the tests start runs first.
  FILE = File.expand_path(__FILE__)

  # Loads the test extension, which refuses dialogs as it loads, from the
  # build tree when nothing earlier on the load path has it, as the
  # sanitized tree does. The extension requires lota/error_message as it
  # loads (ext/lota/native/errors.hpp), so a process whose load path has
  # no Lota, which cannot show Lota's dialogs, goes without it, as does one
  # before the build. Windows finds the extension's DLLs only once Lota's
  # preloader has loaded them (lib/lota.rb).
  def self.install
    return unless NEEDED && $LOAD_PATH.resolve_feature_path("lota/error_message")

    $LOAD_PATH.push(BUILD) unless $LOAD_PATH.include?(BUILD)
    require "lota/preload" if RUBY_PLATFORM.include?("mingw")
    require "lota_native_test"
  rescue LoadError
    nil
  end

  # +command+, a Ruby that runs this file first when it is Ruby, or as it
  # is otherwise.
  def self.command(command)
    return command unless NEEDED && command.first == RbConfig.ruby

    [command.first, "-r#{FILE}", *command.drop(1)]
  end
end

DialogGuard.install
