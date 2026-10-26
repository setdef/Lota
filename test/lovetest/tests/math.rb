# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.math tests (vendor/love/testing/tests/math.lua),
# translated to Ruby by ADR 001's rules, for the functions Lota binds. Like
# the graphics tests, they run in the test suite's own process
# (test/lovetest/math_test.rb) and under lota run (test/lovetest/game).
# setRandomSeed's test reads the seed back with getRandomSeed, which Lota
# does not bind yet, so it waits for it.
class MathTest < Lovetest::TestMethod
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.math.random
  # (vendor/love/testing/tests/math.lua:336-342): setRandomSeed becomes the
  # writer random_seed= (rule 5), and random keeps its name (rule 13).
  # Lövetest's assertRange (classes/TestMethod.lua:126-140) asserts that a
  # value lies within a range, as Minitest's assert_includes does for a
  # Range.
  def test_random
    # check some random ranges
    Lota::Math.random_seed = 123
    assert_includes(0.37068322251462..0.37068322251464, Lota::Math.random, "check random algorithm")
    assert_equal(4, Lota::Math.random(10), "check single random param")
    assert_equal(92, Lota::Math.random(15, 100), "check two random params")
  end
  # SPDX-SnippetEnd
end
