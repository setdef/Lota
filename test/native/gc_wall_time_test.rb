# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# LotaNativeTest.gc_wall_time, the collector's time by the wall clock,
# which rake bench reads where GC.total_time advances only at Windows'
# clock tick (ext/lota/native_test/native_test.cpp, GcClock).
class GcWallTimeTest < Minitest::Test
  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
  end

  def test_it_counts_the_time_each_collection_takes_and_no_more
    LotaNativeTest.gc_wall_time
    before = LotaNativeTest.gc_wall_time
    start = clock
    5.times { GC.start }
    elapsed = clock - start
    spent = LotaNativeTest.gc_wall_time - before

    assert_operator spent, :>, 0
    assert_operator spent, :<=, elapsed
  end

  def test_it_stands_still_while_nothing_is_collected
    LotaNativeTest.gc_wall_time
    GC.disable
    before = LotaNativeTest.gc_wall_time
    10_000.times { Object.new }

    assert_equal before, LotaNativeTest.gc_wall_time
  ensure
    GC.enable
  end
end
