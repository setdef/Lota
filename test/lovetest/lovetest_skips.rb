# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# How many of Lövetest's translated tests (test/lovetest/tests) skip on
# this machine whatever its sensors, renderer, and desktop, counted from
# the tests' own source and the predicates they skip by, so that a count
# checked on one platform cannot hold another's: a skip added to the
# tests is counted everywhere it applies, and no platform's number is
# written down. The tasks and tests that check a run's skips add what
# depends on the machine to it (UnseenDesktop, HeldForeground, the
# sensors, GLSL 4).
#
# It needs nothing loaded, so tasks/package.rake asks it as the tests do.
module LovetestSkips
  # The translated tests.
  SOURCES = Dir[File.join(__dir__, "tests", "*.rb")].freeze

  # A skip that is a statement of a test's own body, in no condition and
  # with none, as the tests Lövetest skips everywhere have.
  ALWAYS = /^ {4}(?:return\s+)?skip\("[^"]*"\)\s*$/

  # A call of window.rb's skip_on_linux_runner, which skips on a GitHub
  # runner on Linux, as Lövetest does (test/lovetest/tests/window.rb).
  ON_LINUX_RUNNER = /^\s*skip_on_linux_runner\(/

  # The source of the RecordingDevice test's skip where OpenAL Soft
  # cannot record, which every run of the suite's sets up
  # (Lovetest::PLAYBACK_ONLY: test/alsoft.conf plays into the wave writer,
  # and tasks/alsoft.conf into the null driver).
  PLAYBACK_ONLY = /^\s*skip\("[^"]*"\) if Lovetest::GITHUB_RUNNER \|\| Lovetest::PLAYBACK_ONLY$/

  # Whether this is a GitHub runner on Linux, by Lövetest's own test
  # (Lovetest::GITHUB_RUNNER and Lovetest.os?("Linux")).
  def self.linux_runner?(env: ENV, platform: RUBY_PLATFORM)
    env["GITHUB_ACTIONS"] == "true" && platform.include?("linux")
  end

  # The skips of a run of the suite on a machine that has a sensor, GLSL
  # 4, and a desktop it draws: those that always skip, the recording
  # test, and on a GitHub runner on Linux the window tests xvfb cannot
  # pass.
  def self.expected(env: ENV, platform: RUBY_PLATFORM)
    count(ALWAYS) + count(PLAYBACK_ONLY) + (linux_runner?(env:, platform:) ? count(ON_LINUX_RUNNER) : 0)
  end

  # How many lines of the tests match +pattern+.
  def self.count(pattern) = SOURCES.sum { |file| File.read(file).scan(pattern).size }
end
