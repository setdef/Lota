# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require "rbconfig"

# On Linux the tests share one X display with the games they start, and
# SDL answers another program's request for the clipboard this program
# owns without guarding against that program's window being gone, which
# Xlib's default error handler turns into the end of the program
# (ext/lota/native_test/selections_linux.cpp). Each case runs in a Ruby of
# its own, since the one that is not tolerated ends it.
class SelectionsTest < Minitest::Test
  include NativeHelper

  # Boots the engine, takes the clipboard, has a window of another
  # connection ask for it and vanish, then lets SDL answer, in a Ruby of
  # its own, with the extension's handler or without it.
  def run_requestor(tolerate:)
    lib = File.dirname(loaded("lota_native_test"))
    native = File.dirname(File.dirname(loaded("lota/native")))
    capture2e({}, RbConfig.ruby, "-I#{native}", "-I#{File.join(ROOT, 'lib')}", "-I#{lib}", "-I#{File.join(ROOT, 'test')}",
      "-e", <<~RUBY)
        require "engine_helper"
        require "lota_native_test"
        Lota::Boot.new(EngineHelper::CONF).init
        LotaNativeTest.tolerate_vanished_requestors if #{tolerate}
        Lota::System.clipboard_text = "lota"
        Lota::Event.pump
        abort "no display" unless LotaNativeTest.request_clipboard_and_vanish
        10.times { Lota::Event.pump; sleep 0.05 }
        puts "survived"
      RUBY
  end

  if TestHome::LINUX
    def test_an_answer_to_a_vanished_requestor_ends_the_program_under_xlibs_handler
      output, status = run_requestor(tolerate: false)

      refute_predicate status, :success?, output
      assert_includes output, "BadWindow"
      refute_includes output, "survived"
    end

    def test_the_tests_let_an_answer_to_a_vanished_requestor_pass
      output, status = run_requestor(tolerate: true)

      assert_predicate status, :success?, output
      assert_includes output, "survived"
    end
  end
end
