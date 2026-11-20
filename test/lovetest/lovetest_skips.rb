# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lovetest_lua"
require_relative "held_foreground"

# Where Lövetest's translated tests (test/lovetest/tests) may skip: where
# Lövetest's own Lua skips them (LovetestLua.skips), under the same
# condition and with the same reason, and where EXCEPTIONS, the one place
# that names a skip Lövetest does not have, says why Lota needs it. Every
# test of Lövetest's asks after it runs (Lovetest::TestMethod#
# after_teardown), so a test turned into a skip, or one that skips under
# a condition Lövetest does not skip under, fails; and so does a test that
# runs where Lövetest skips it. The tasks and tests that count a run's
# skips ask expected, which counts the skips the run's environment alone
# decides, and add those only the machine can tell (the sensors, GLSL 4).
#
# It needs nothing loaded, so tasks/package.rake asks it as the tests do.
module LovetestSkips
  # A condition a skip holds under: +lota+ says in words what Lota asks,
  # +machine+ is true when only the engine, in the tests' own process, can
  # tell, and +holds+ answers for an environment and a RUBY_PLATFORM.
  Condition = Data.define(:lota, :machine, :holds)

  # A skip a test may make: the test, by Lövetest's name, the +reason+ it
  # gives, the Condition it holds under, and, for a skip Lövetest does not
  # have, +why+ Lota needs it.
  Allowed = Data.define(:test, :reason, :condition, :why)

  # Lövetest's GITHUB_RUNNER (vendor/love/testing/main.lua:86-111), which
  # LÖVE's CI sets with --isRunner and GitHub sets for Lota's with
  # GITHUB_ACTIONS (Lovetest::GITHUB_RUNNER).
  def self.github_runner?(env) = env["GITHUB_ACTIONS"] == "true"

  # Whether this is a GitHub runner on Linux, by Lövetest's own test
  # (GITHUB_RUNNER and test:isOS('Linux')).
  def self.linux_runner?(env: ENV, platform: RUBY_PLATFORM)
    github_runner?(env) && platform.include?("linux")
  end

  # Whether OpenAL Soft, as the run's ALSOFT_CONF sets it, plays through a
  # driver that cannot record: its wave file writer, as test/alsoft.conf
  # has it play, or its null driver, as tasks/alsoft.conf has it play.
  def self.playback_only?(env)
    conf = env.fetch("ALSOFT_CONF", "")
    File.file?(conf) && File.read(conf).match?(/^\s*drivers\s*=\s*(?:wave|null)\s*$/)
  end

  # What each condition Lövetest skips under means in Lota, by its Lua.
  # Lövetest's own conditions are each ported where its test is; this
  # asks the same of the run, so a translation whose condition differs
  # from Lövetest's is caught by the test that skips, or by the test that
  # should have. A condition Lövetest gains when vendor/love moves has no
  # entry, and test/lovetest/lovetest_skips_test.rb fails until it does.
  CONDITIONS = {
    "" => Condition.new("always", false, -> (_env, _platform) { true }),
    "GITHUB_RUNNER" => Condition.new("on a GitHub runner", false, -> (env, _platform) { github_runner?(env) }),
    "GITHUB_RUNNER and test:isOS('Linux')" =>
      Condition.new("on a GitHub runner on Linux", false, -> (env, platform) { linux_runner?(env:, platform:) }),
    "#devices == 0" => Condition.new("where Lota lists no recording device", true,
      -> (_env, _platform) { Lota::Audio.recording_devices.empty? }),
    "not love.graphics.getSupported().glsl4" => Condition.new("where the renderer lacks GLSL 4", true,
      -> (_env, _platform) { !Lota::Graphics.supported.glsl4 }),
    "string.match(name, 'OpenGL ES')" => Condition.new("on OpenGL ES", true,
      -> (_env, _platform) { Lota::Graphics.renderer_info.first.include?("OpenGL ES") }),
    "not (love.mouse.isCursorSupported())" => Condition.new("where the cursor is not supported", true,
      -> (_env, _platform) { !Lota::Mouse.cursor_supported? }),
    "not (accelerometer or gyroscope)" => Condition.new("where the machine has neither an accelerometer nor a gyroscope",
      true, -> (_env, _platform) { %i[accelerometer gyroscope].none? { |type| Lota::Sensor.sensor?(type) } }),
    "love.test.windowmode == false" => Condition.new("without a window, which never happens in Lota", false,
      -> (_env, _platform) { false }),
  }.freeze

  # The skips Lövetest does not have, each with why Lota needs it. A skip
  # belongs here only once its cause is found and nothing in Lota can
  # remove it; each is a deviation from LÖVE's suite, for the maintainer
  # to review.
  EXCEPTIONS = [
    Allowed.new(
      test: "love.test.audio.RecordingDevice",
      reason: "cant emulate recording devices in CI",
      condition: Condition.new("where OpenAL Soft plays through a driver that cannot record", false,
        -> (env, _platform) { playback_only?(env) }),
      why: "Lota's tests play into OpenAL Soft's wave writer, or its null driver, everywhere, " \
        "where Lövetest's do only on its CI's runners (doc/contributors/upstream/009.md)"
    ),
    Allowed.new(
      test: "love.test.mouse.setGrabbed",
      reason: HeldForeground::REASON,
      condition: Condition.new("where LOTA_FOREGROUND_HELD=1 on Windows", false,
        -> (env, platform) { HeldForeground.on?(env:, platform:) }),
      why: "on GitHub's windows-11-arm runner a window of the shell's holds the foreground, and LÖVE's CI " \
        "runs Lövetest on no Windows ARM64 runner (test/lovetest/held_foreground.rb)"
    ),
  ].freeze

  class << self
    # Every skip a test may make: Lövetest's, each under the Condition its
    # Lua's means, and EXCEPTIONS.
    def allowed
      @allowed ||= (LovetestLua.skips.map do |skip|
        Allowed.new(test: skip.test.to_s, reason: skip.reason, condition: CONDITIONS.fetch(skip.condition), why: nil)
      end + EXCEPTIONS).freeze
    end

    # The tests a run of the whole suite in +env+ on +platform+ skips, by
    # Lövetest's names, beside those only the machine can tell
    # (Condition#machine): those Lövetest always skips, those it skips on
    # a GitHub runner or one on Linux, and EXCEPTIONS', where each holds.
    def expected_tests(env: ENV, platform: RUBY_PLATFORM)
      allowed.reject { |skip| skip.condition.machine }.select { |skip| skip.condition.holds.call(env, platform) }
        .map(&:test).uniq
    end

    # How many tests expected_tests names.
    def expected(env: ENV, platform: RUBY_PLATFORM) = expected_tests(env:, platform:).size

    # Why the test +test+, by Lövetest's name, which skipped with +message+
    # or ran when +message+ is nil, did not do as Lövetest does in +env+
    # on +platform+, or nil when it did: a skip must be one of +skips+
    # whose condition holds, and a test one of Lövetest's skips holds for
    # must skip.
    def verdict(test, message, env: ENV, platform: RUBY_PLATFORM, skips: allowed.select { |skip| skip.test == test })
      holding = skips.select { |skip| skip.condition.holds.call(env, platform) }
      if message
        return if holding.any? { |skip| skip.reason == message }

        "#{test} skipped (#{message}), a skip Lövetest does not make here: it skips this test " \
          "#{skips.empty? ? 'nowhere' : skips.map { |skip| "#{skip.condition.lota} (#{skip.reason})" }.join(', ')}"
      elsif (skip = holding.find { |each| each.why.nil? })
        "#{test} ran, where Lövetest skips it #{skip.condition.lota} (#{skip.reason})"
      end
    end
  end
end
