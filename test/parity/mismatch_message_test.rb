# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# What a parity test says when a frame differs, and what of a run's
# output is the engine's: a failure shows the frame and the last lines
# both engines printed, with what the Metal watch reported in each, and
# the watch's lines are kept out of what the engines are compared on.
class MismatchMessageTest < Minitest::Test
  Status = Struct.new(:success?)

  def output(text, diagnostics = "")
    Parity::Output.new(text, Status.new(true), diagnostics)
  end

  def test_a_mismatch_shows_the_frame_and_what_both_engines_printed
    love = output("Thanks for playing!\n", "lota-metal-watch: 9 command buffers committed\n")
    lota = output("Thanks for playing!\nerror: no drawable", "")

    assert_equal <<~MESSAGE, Parity.mismatch_message({ "frame" => 31 }, love, lota)
      first differing frame: {"frame" => 31}
      The reference love printed:
      Thanks for playing!
      The reference love's Metal watch reported:
      lota-metal-watch: 9 command buffers committed
      Lota printed:
      Thanks for playing!
      error: no drawable
      Lota's Metal watch reported:
      (nothing)
    MESSAGE
  end

  def test_a_mismatch_shows_only_the_last_lines_of_a_long_output
    long = (1..(Parity::TAIL + 5)).map { |line| "line #{line}\n" }.join
    message = Parity.mismatch_message({ "frame" => 2 }, output(long), output(""))

    assert_includes message, "The reference love printed, last #{Parity::TAIL} of #{Parity::TAIL + 5} lines:\n" \
      "line 6\nline 7\n"
    assert_includes message, "line #{Parity::TAIL + 5}\nThe reference love's Metal watch reported:\n"
    refute_includes message, "line 5\n"
    assert_includes message, "Lota printed:\n(nothing)\n"
  end

  # The watch writes each line in one write, which may land inside a line
  # the engine had begun but not ended.
  def test_the_metal_watch_lines_are_kept_apart_from_what_the_engine_printed
    printed = "main\nThanks for plalota-metal-watch: a buffer ended with status 5\nying!\n" \
      "lota-metal-watch: 3 command buffers committed, 1 failed\n"
    run = Parity.output(printed, Status.new(true))

    assert_equal "main\nThanks for playing!\n", run.text
    assert_equal "lota-metal-watch: a buffer ended with status 5\n" \
      "lota-metal-watch: 3 command buffers committed, 1 failed\n", run.diagnostics
  end
end
