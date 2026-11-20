# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "lovetest_lua"
require_relative "lovetest_skips"

# What Lota's translation of Lövetest must hold, read from Lövetest's own
# Lua (LovetestLua): every test of Lövetest's is translated, and no other,
# and each skips only where Lövetest skips it, or where
# LovetestSkips::EXCEPTIONS says why (LovetestSkips).
class LovetestSkipsTest < Minitest::Test
  TESTS = File.expand_path("tests", __dir__)
  MACOS = "arm64-darwin27"
  LINUX = "x86_64-linux"
  WINDOWS = "aarch64-mingw-ucrt"
  # OpenAL Soft's settings for the tests, which play into the wave writer.
  PLAYS_ONLY = { "ALSOFT_CONF" => File.expand_path("../alsoft.conf", __dir__) }.freeze

  # A file of Lövetest's, as its files are written, with what the reader
  # must see past: comments, strings and long strings that hold keywords,
  # one-line ifs, nested blocks, and an else.
  SOURCE = <<~LUA
    -- Ünïcode in a comment moves byte offsets from character ones
    local function helper(test) if true then return end end

    love.test.sample.always = function(test)
      test:skipTest('cant test this worked')
    end

    --love.test.sample.commented = function(test)
    --  test:skipTest('never read')
    --end

    love.test.sample.nested = function(test)
      local shader = [[
        if (x) { return; } end function do
      ]]
      local text = "if then end"
      for i = 1, 2 do
        if GITHUB_RUNNER and test:isOS('Linux') then
          return test:skipTest("xvfb on Linux doesn't support it")
        end
      end
      local f = function() return 1 end
      if love.mouse.isCursorSupported() then
        test:assertTrue(true)
      elseif other then
        test:skipTest('the elseif')
      else
        test:skipTest('cursor not supported on this system')
      end
    end

    love.test.sample.getVSync = function(test)
      test:assertTrue(true)
    end
  LUA

  def test_it_reads_lovetests_tests_and_skips_from_its_lua
    read = LovetestLua.parse(SOURCE)

    assert_equal %w[love.test.sample.always love.test.sample.nested love.test.sample.getVSync], read[:tests].map(&:to_s)
    assert_equal %w[test_always test_nested test_get_vsync], read[:tests].map(&:method_name)
    assert_equal [
      ["love.test.sample.always", "cant test this worked", ""],
      ["love.test.sample.nested", "xvfb on Linux doesn't support it", "GITHUB_RUNNER and test:isOS('Linux')"],
      ["love.test.sample.nested", "the elseif", "not (love.mouse.isCursorSupported()) and other"],
      [
        "love.test.sample.nested",
        "cursor not supported on this system",
        "not (love.mouse.isCursorSupported()) and not (other)",
],
    ], read[:skips].map { |skip| [skip.test.to_s, skip.reason, skip.condition] }
  end

  def test_it_refuses_lua_it_cannot_follow
    assert_raises(LovetestLua::Unreadable) { LovetestLua.parse("local function f(test)\n  test:skipTest('x')\nend\n") }
    assert_raises(LovetestLua::Unreadable) { LovetestLua.parse("love.test.a.b = function(test)\n") }
    assert_raises(LovetestLua::Unreadable) { LovetestLua.parse("love.test.a.b = function(test)\n  if x\nend\n") }
  end

  # Lövetest's 362 tests at the pinned commit, in 21 files.
  def test_it_reads_every_test_of_lovetests
    assert_equal 362, LovetestLua.tests.size
    assert_equal 21, LovetestLua.tests.map(&:module_name).uniq.size
  end

  # Each of Lövetest's files has a translation of the same name (love.lua's
  # is lota.rb, by rule 1), whose tests are Lövetest's, each by its name
  # in snake_case, and no other.
  def test_every_lovetest_test_is_translated_and_no_other
    translated = Dir[File.join(TESTS, "*.rb")].to_h do |file|
      [File.basename(file, ".rb"), File.read(file).scan(/^\s*def (test_\w+)/).flatten]
    end
    lovetest = LovetestLua.tests.group_by { |test| (test.module_name == "love") ? "lota" : test.module_name }
      .transform_values { |tests| tests.map(&:method_name) }

    assert_equal lovetest.keys.sort, translated.keys.sort
    lovetest.each do |file, methods|
      assert_empty methods - translated.fetch(file), "Lövetest's tests test/lovetest/tests/#{file}.rb does not translate"
      assert_empty translated.fetch(file) - methods, "tests of test/lovetest/tests/#{file}.rb Lövetest does not have"
      assert_equal methods.size, translated.fetch(file).size, "test/lovetest/tests/#{file}.rb defines a test twice"
    end
  end

  # A condition Lövetest gains when vendor/love moves has no meaning in
  # Lota until someone gives it one, and none is kept that Lövetest lost.
  def test_every_condition_lovetest_skips_under_has_a_meaning_in_lota
    assert_equal LovetestSkips::CONDITIONS.keys.sort, LovetestLua.skips.map(&:condition).uniq.sort
    assert_equal LovetestLua.skips.size + LovetestSkips::EXCEPTIONS.size, LovetestSkips.allowed.size
  end

  # Each skip Lövetest does not have is of one of its tests, and says why.
  def test_each_exception_names_a_test_of_lovetests_and_why
    names = LovetestLua.tests.map(&:to_s)

    LovetestSkips::EXCEPTIONS.each do |exception|
      assert_includes names, exception.test
      refute_empty exception.why
      refute exception.condition.machine, "#{exception.test}: a run's environment decides an exception"
    end
  end

  # Away from GitHub, Lövetest skips its discard, requestAttention,
  # showMessageBox, openURL, vibrate, pump, wait, getSource, and setSource
  # tests, and Lota its RecordingDevice test too, where OpenAL Soft plays
  # only.
  def test_a_run_skips_what_lovetest_always_skips
    always = %w[
      love.test.event.pump
      love.test.event.wait
      love.test.filesystem.getSource
      love.test.filesystem.setSource
      love.test.graphics.discard
      love.test.system.openURL
      love.test.system.vibrate
      love.test.window.requestAttention
      love.test.window.showMessageBox
    ]

    assert_equal always.sort, LovetestSkips.expected_tests(env: {}, platform: MACOS).sort
    assert_equal [*always, "love.test.audio.RecordingDevice"].sort,
      LovetestSkips.expected_tests(env: PLAYS_ONLY, platform: MACOS).sort
    assert_equal 10, LovetestSkips.expected(env: PLAYS_ONLY, platform: MACOS)
  end

  # On a GitHub runner Lövetest skips its recording test, and on one on
  # Linux its fullscreen, maximize, minimize, and restore tests too.
  def test_a_github_runner_skips_more
    runner = { "GITHUB_ACTIONS" => "true" }

    assert_equal 10, LovetestSkips.expected(env: runner, platform: MACOS)
    assert_equal 17, LovetestSkips.expected(env: runner, platform: LINUX)
    assert_equal 17, LovetestSkips.expected(env: runner.merge(PLAYS_ONLY), platform: LINUX)
  end

  def test_each_exception_counts_where_its_switch_is_on
    assert_equal 10, LovetestSkips.expected(env: { "LOTA_FOREGROUND_HELD" => "1" }, platform: WINDOWS)
    assert_equal 9, LovetestSkips.expected(env: { "LOTA_FOREGROUND_HELD" => "1" }, platform: MACOS)
    assert_equal 10, LovetestSkips.expected(env: { "LOTA_DESKTOP_UNSEEN" => "1" }, platform: MACOS)
  end

  def test_a_skip_lovetest_makes_passes
    assert_nil LovetestSkips.verdict("love.test.graphics.discard", "cant test this worked", env: {}, platform: MACOS)
    assert_nil LovetestSkips.verdict("love.test.window.maximize", "xvfb on Linux doesn't support window maximization",
      env: { "GITHUB_ACTIONS" => "true" }, platform: LINUX)
    assert_nil LovetestSkips.verdict("love.test.window.maximize", nil, env: {}, platform: LINUX)
  end

  def test_a_skip_lovetest_does_not_have_fails
    verdict = LovetestSkips.verdict("love.test.graphics.clear", "too slow", env: {}, platform: MACOS)

    assert_equal "love.test.graphics.clear skipped (too slow), a skip Lövetest does not make here: " \
      "it skips this test nowhere", verdict
  end

  def test_a_skip_under_another_condition_than_lovetests_fails
    verdict = LovetestSkips.verdict("love.test.window.maximize", "xvfb on Linux doesn't support window maximization",
      env: { "GITHUB_ACTIONS" => "true" }, platform: MACOS)

    assert_equal "love.test.window.maximize skipped (xvfb on Linux doesn't support window maximization), " \
      "a skip Lövetest does not make here: it skips this test on a GitHub runner on Linux " \
      "(xvfb on Linux doesn't support window maximization)", verdict
  end

  def test_a_skip_with_another_reason_than_lovetests_fails
    refute_nil LovetestSkips.verdict("love.test.graphics.discard", "cant", env: {}, platform: MACOS)
  end

  def test_a_test_that_runs_where_lovetest_skips_it_fails
    assert_equal "love.test.graphics.discard ran, where Lövetest skips it always (cant test this worked)",
      LovetestSkips.verdict("love.test.graphics.discard", nil, env: {}, platform: MACOS)
  end

  # A condition only the engine can tell is asked of it in the tests'
  # process; here a stand-in answers.
  def test_a_condition_of_the_machine_is_asked_as_the_test_runs
    skips = LovetestSkips.allowed.select { |skip| skip.test == "love.test.mouse.newCursor" }
    supported = skips.map { |skip| skip.with(condition: skip.condition.with(holds: -> (_env, _platform) { false })) }
    unsupported = skips.map { |skip| skip.with(condition: skip.condition.with(holds: -> (_env, _platform) { true })) }

    assert_nil LovetestSkips.verdict("love.test.mouse.newCursor", nil, skips: supported)
    refute_nil LovetestSkips.verdict("love.test.mouse.newCursor", "cursor not supported on this system", skips: supported)
    assert_nil LovetestSkips.verdict("love.test.mouse.newCursor", "cursor not supported on this system", skips: unsupported)
    refute_nil LovetestSkips.verdict("love.test.mouse.newCursor", nil, skips: unsupported)
  end

  # Where an exception's switch is on, its test may skip with its reason;
  # where it is off, the skip fails.
  def test_an_exception_holds_only_where_its_switch_is_on
    held = { "LOTA_FOREGROUND_HELD" => "1" }

    assert_nil LovetestSkips.verdict("love.test.mouse.setGrabbed", HeldForeground::REASON, env: held, platform: WINDOWS)
    refute_nil LovetestSkips.verdict("love.test.mouse.setGrabbed", HeldForeground::REASON, env: {}, platform: WINDOWS)
    assert_nil LovetestSkips.verdict("love.test.mouse.setGrabbed", nil, env: {}, platform: WINDOWS)
  end
end
