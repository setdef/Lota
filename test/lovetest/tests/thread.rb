# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.thread tests (vendor/love/testing/tests/thread.lua),
# translated to Ruby by ADR 001's rules, all five. Each thread runs in a
# Ractor, and a process that has made one stops ObjectSpace finding the
# objects other tests count (test/native/physics_callbacks_test.rb), so
# they run in a Ruby of their own (test/lovetest/thread_test.rb), and
# under lota run (test/lovetest/game). The thread code each test runs is
# Lua in Lövetest and Ruby here, translated by the same rules.
class ThreadTest < Lovetest::TestMethod
  # The types whose tests Lövetest names by the type
  # (love.test.thread.Channel).
  TYPES = %w[Channel Thread].freeze

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.thread.Channel
  # (vendor/love/testing/tests/thread.lua:12-79): getChannel becomes
  # channel (rule 3), getCount count (rule 3), hasRead read? (rule 8),
  # performAtomic perform_atomic, which takes the function as a block
  # (rule 12), and newThread Thread.new (rule 2). The threads' Lua
  # requires love.timer, which Ruby's require "lota" stands for, and a
  # local function becomes a lambda, passed as the block.
  def test_channel
    # create channel
    channel = Lota::Thread.channel("test")
    assert_object(channel)

    # setup thread to use
    threadcode1 = <<~RUBY
      require "lota"
      Lota::Timer.sleep(0.1)
      Lota::Thread.channel("test").push("hello world")
      Lota::Timer.sleep(0.1)
      Lota::Thread.channel("test").push("me again")
    RUBY
    thread1 = Lota::Thread::Thread.new(threadcode1)
    thread1.start

    # check message sent from thread to channel
    msg1 = channel.demand
    assert_equal("hello world", msg1, "check 1st message was sent")
    thread1.wait
    assert_equal(1, channel.count, "check still another message")
    assert_equal("me again", channel.peek, "check 2nd message pending")
    msg2 = channel.pop
    assert_equal("me again", msg2, "check 2nd message was sent")
    channel.clear

    # setup another thread for some ping pong
    threadcode2 = <<~RUBY
      set_channel = lambda do |channel, value|
        channel.clear
        channel.push(value)
      end
      channel = Lota::Thread.channel("test")
      waiting = true
      sent = nil
      while waiting == true
        if sent.nil?
          sent = channel.perform_atomic("ping", &set_channel)
        end
        if channel.read?(sent)
          msg = channel.demand
          if msg == "pong"
            channel.push(msg)
            waiting = false
          end
        end
      end
    RUBY

    # first we run a thread that will send 1 ping
    thread2 = Lota::Thread::Thread.new(threadcode2)
    thread2.start

    # we wait for that ping to be sent and then send a pong back
    msg3 = channel.demand
    assert_equal("ping", msg3, "check message recieved 1")

    # thread should be waiting for us, and checking is the ping was read
    channel.supply("pong", 1)

    # if it was then it should send back our pong and thread should die
    thread2.wait
    msg4 = channel.pop
    assert_equal("pong", msg4, "check message recieved 2")
    assert_equal(0, channel.count)
  end

  # Translated to Ruby from love.test.thread.Thread (thread.lua:83-109):
  # isRunning becomes running? (rule 8) and getError error (rule 3). The
  # bad thread's Lua adds a string to a number, which Ruby's raises
  # TypeError for, as Lua's raises its arithmetic error. assertEquals(nil,
  # ...) becomes assert_nil, which Minitest asks for nil.
  def test_thread
    # create thread
    threadcode = <<~RUBY
      b = 0
      (1..100000).each do |a|
        b = b + a
      end
    RUBY
    thread = Lota::Thread::Thread.new(threadcode)
    assert_object(thread)

    # check thread runs
    thread.start
    assert_true(thread.running?, "check started")
    thread.wait
    assert_false(thread.running?, "check finished")
    assert_nil(thread.error, "check no errors")

    # check an invalid thread
    badthreadcode = "b = 0\nreturn b + \"string\" + 10.to_s"
    badthread = Lota::Thread::Thread.new(badthreadcode)
    badthread.start
    badthread.wait
    assert_not_nil(badthread.error)
  end

  # Translated to Ruby from love.test.thread.getChannel (thread.lua:121-123).
  def test_get_channel
    assert_object(Lota::Thread.channel("test"))
  end

  # Translated to Ruby from love.test.thread.newChannel (thread.lua:128-130):
  # newChannel becomes Channel.new (rule 2).
  def test_new_channel
    assert_object(Lota::Thread::Channel.new)
  end

  # Translated to Ruby from love.test.thread.newThread (thread.lua:135-137).
  # Lövetest makes a thread of one of its own files, classes/TestSuite.lua;
  # Lota's runners have conf.rb, which LÖVE's filesystem finds as it finds
  # that file.
  def test_new_thread
    assert_object(Lota::Thread::Thread.new("conf.rb"))
  end
  # SPDX-SnippetEnd
end
