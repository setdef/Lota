# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "package_check"
require_relative "../test/lovetest/lovetest_lua"
require_relative "../test/lovetest/lovetest_skips"

# What the delivery check (tasks/package.rake) expects of Lövetest's run
# from the installed gem, test/lovetest/game: every one of Lövetest's
# tests run, none failing, and exactly the skips this system and its
# machine call for, counted as the gate's own Lövetest test counts them
# (test/native/lota_run_test.rb), from Lövetest's Lua. What only the
# machine knows, whether its renderer has GLSL 4 and how many of an
# accelerometer and a gyroscope it has, the check's window game prints
# from the installed gem first (#facts).
module LovetestDelivery
  # How the window game prints the machine's facts.
  FACTS = /^glsl4 (true|false)\nsensors (\d+)$/

  # How many tests Lövetest's run must run: every test of Lövetest's Lua
  # (vendor/love/testing/tests).
  def self.runs
    LovetestLua.tests.size
  end

  # The machine's facts from what the window game +printed+, as keywords
  # for #skips. Raises ArgumentError when it printed none.
  def self.facts(printed)
    match = FACTS.match(printed) or raise ArgumentError, "the window game printed no facts:\n#{printed}"
    { glsl4: match[1] == "true", sensors: Integer(match[2]) }
  end

  # How many tests Lövetest's run skips: those LovetestSkips counts for
  # the run's environment, which plays through OpenAL Soft's null driver
  # (PackageCheck::SILENT), on +platform+, its ShaderStorageBuffer test
  # where the renderer lacks GLSL 4, and its isEnabled, getName, and
  # getData sensor tests where the machine has neither an accelerometer
  # nor a gyroscope (test/lovetest/tests/sensor.rb).
  def self.skips(glsl4:, sensors:, env: ENV, platform: RUBY_PLATFORM)
    LovetestSkips.expected(env: env.to_h.merge(PackageCheck::SILENT), platform:) +
      (glsl4 ? 0 : 1) + (sensors.zero? ? 3 : 0)
  end

  # What Lövetest's run must print: its conf.rb's line, then exactly +runs+
  # tests run, none failing or raising, and exactly +skips+ skipped.
  def self.output(runs:, skips:)
    /^love\.conf$.*^#{runs} runs, \d+ assertions, 0 failures, 0 errors, #{skips} skips$/m
  end
end
