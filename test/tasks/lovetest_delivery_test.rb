# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/lovetest_delivery"

# What the delivery check expects of Lövetest's run from the installed
# gem: every one of Lota's translations of Lövetest's tests run, and
# exactly the skips this system and its machine call for, as the gate's
# own Lövetest test counts them.
class LovetestDeliveryTest < Minitest::Test
  MAC = { env: {}, platform: "arm64-darwin24" }.freeze
  # GitHub's Linux runners, where Lövetest skips the window tests xvfb
  # cannot pass.
  LINUX_RUNNER = { env: { "GITHUB_ACTIONS" => "true" }, platform: "x86_64-linux" }.freeze
  HELD = { env: { "LOTA_FOREGROUND_HELD" => "1" }, platform: "aarch64-mingw-ucrt" }.freeze

  def test_every_one_of_lovetests_tests_runs
    assert_operator LovetestDelivery.runs, :>, 300
    assert_equal LovetestLua.tests.size, LovetestDelivery.runs
  end

  def test_the_facts_are_what_the_window_game_printed
    printed = "window 800x600\nglsl4 false\nsensors 2\n"

    assert_equal({ glsl4: false, sensors: 2 }, LovetestDelivery.facts(printed))
  end

  def test_no_facts_is_a_failure_to_say_so
    assert_raises(ArgumentError) { LovetestDelivery.facts("window 800x600\n") }
  end

  def test_a_machine_without_sensors_skips_three_more
    with = LovetestDelivery.skips(glsl4: true, sensors: 1, **MAC)

    assert_equal with + 3, LovetestDelivery.skips(glsl4: true, sensors: 0, **MAC)
  end

  def test_a_renderer_without_glsl4_skips_one_more
    with = LovetestDelivery.skips(glsl4: true, sensors: 1, **MAC)

    assert_equal with + 1, LovetestDelivery.skips(glsl4: false, sensors: 1, **MAC)
  end

  # The run plays through the null driver, whatever this process was given.
  def expected(env:, platform:)
    LovetestSkips.expected(env: env.merge(PackageCheck::SILENT), platform:)
  end

  def test_the_skips_the_runs_environment_decides_are_counted
    assert_equal expected(**MAC), LovetestDelivery.skips(glsl4: true, sensors: 1, **MAC)
  end

  def test_a_linux_runner_and_a_held_foreground_are_counted_as_lovetest_skips_counts_them
    assert_equal expected(**LINUX_RUNNER), LovetestDelivery.skips(glsl4: true, sensors: 1, **LINUX_RUNNER)
    assert_operator expected(**LINUX_RUNNER), :>, expected(**MAC)
    assert_equal expected(**HELD), LovetestDelivery.skips(glsl4: true, sensors: 1, **HELD)
  end

  def test_the_output_pins_the_runs_and_the_skips_exactly
    output = LovetestDelivery.output(runs: 362, skips: 13)

    assert_match output, "love.conf\n\n362 runs, 1496 assertions, 0 failures, 0 errors, 13 skips\n"
    refute_match output, "love.conf\n\n361 runs, 1496 assertions, 0 failures, 0 errors, 13 skips\n"
    refute_match output, "love.conf\n\n1362 runs, 1496 assertions, 0 failures, 0 errors, 13 skips\n"
    refute_match output, "love.conf\n\n362 runs, 1496 assertions, 0 failures, 0 errors, 14 skips\n"
    refute_match output, "love.conf\n\n362 runs, 1496 assertions, 1 failures, 0 errors, 13 skips\n"
    refute_match output, "362 runs, 1496 assertions, 0 failures, 0 errors, 13 skips\n"
  end
end
