# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Run by test/native/file_dialog_test.rb in a Ruby of its own: opens the
# window, shows each dialog its argument lists, as JSON pairs of a type
# and its options, one at a time, pumps the events until the dialog's
# answer reaches its block, and prints the answer as a line of JSON.
require "json"
require_relative "../engine_helper"

EngineHelper.open_window
JSON.parse(ARGV.fetch(0)).each do |type, options|
  answer = nil
  Lota::Window.show_file_dialog(type.to_sym, **options.transform_keys(&:to_sym)) { |*values| answer = values }
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
  Lota::Event.pump(0.1) until answer || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  abort "no answer to the #{type} dialog" unless answer
  puts JSON.generate(answer)
end
