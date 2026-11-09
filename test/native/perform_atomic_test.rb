# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# Data#perform_atomic keeps out every other thread's perform_atomic of
# the Data while its block runs, as Data:performAtomic does
# (vendor/love/src/modules/data/wrap_Data.cpp:82-100), and a thread that
# waits for it waits without Ruby's GVL. The script runs in a Ruby of its
# own (NativeHelper#ruby_of_its_own), which is killed if it never ends.
class PerformAtomicTest < Minitest::Test
  include NativeHelper

  # Two threads that hold one Data take turns, and a block that sleeps or
  # collects garbage while the other waits ends: the waiting thread waits
  # without its GVL, which the holder needs to run again.
  def test_two_threads_take_turns_and_the_holder_runs_on
    output, status = ruby_of_its_own("-e", <<~RUBY, timeout: 30)
      require "lota"
      Lota::Native::Data.open
      data = Lota::Data::ByteData.new(1)
      order = Thread::Queue.new
      holder = Thread.new do
        data.perform_atomic do
          order << :holding
          sleep 0.2
          GC.start
          order << :first
        end
      end
      order.pop
      waiter = Thread.new { data.perform_atomic { order << :second } }
      [holder, waiter].each(&:join)
      p [order.pop, order.pop]
    RUBY

    assert_predicate status, :success?, output
    assert_equal "[:first, :second]\n", output
  end
end
