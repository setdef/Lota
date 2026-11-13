# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Thread
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # Translated from LÖVE's Channel (src/modules/thread/wrap_Channel.cpp
    # and Channel.cpp).

    # A queue of messages between threads, translated from LÖVE's
    # Channel.
    #
    # Any thread may push a message and any may pop it, first in, first
    # out. Each message gets a number as it is pushed, so the pusher can
    # ask whether it was read. The queue keeps a copy of each message, as
    # LÖVE's keeps a Variant, so what the pusher changes after pushing is
    # not what arrives, and #pop, #demand, and #peek each hand back a fresh
    # copy the receiver may change, as LÖVE hands back a new table: its
    # Strings, Arrays, and Hashes unfrozen. Integers stay Integers, and
    # Symbols Symbols. Lota's objects arrive as the same objects, through
    # wrappers of the receiving thread's own.
    #
    # A Channel goes to another thread as itself too, so it can be passed
    # to a thread's start, or pushed through another Channel. Lota::Thread.channel
    # gives the channel of a name; Channel.new makes one with none.
    #
    # === Example
    #
    #   results = Lota::Thread::Channel.new
    #   worker.start(results)
    #   result = results.demand(1.0)
    class Channel < Object
      # Wraps a Channel the engine made. :nodoc:
      private_class_method def self.from_native(native)
        channel = allocate
        channel.instance_variable_set(:@native, native)
        channel.freeze
      end

      # A new Channel, matching love.thread.newChannel
      # (wrap_ThreadModule.cpp, w_newChannel), with no name, which reaches
      # another thread only when given to it. Raises RuntimeError when the
      # thread module is not open.
      #
      # === Example
      #
      #   channel = Lota::Thread::Channel.new
      def self.new
        from_native(Native::Thread.new_channel)
      end

      # Adds +value+ to the end of the queue, matching Channel:push, and
      # returns its number, an Integer, which #read? takes.
      #
      # Any of Lota's objects goes as itself, as LÖVE's Channel carries its
      # objects, and the thread that pops it gets a wrapper of its own of
      # the same object, a Transform's or a Body's as much as a Data's.
      # Raises ArgumentError, with LÖVE's message, for a value that cannot
      # be carried, as a Proc cannot.
      #
      # === Example
      #
      #   id = channel.push("hello")
      def push(value)
        native.push(Lota::Thread.share(value, 1, "push", CHANNEL_EXPECTED))
      end

      # Pushes +value+ and waits until another thread reads it, matching
      # Channel:supply: forever, or for +timeout+ seconds at most, after
      # which +value+ stays queued. Returns +true+ once it is read, and
      # +false+ when the time runs out first. A +timeout+ that is not a
      # number waits forever, as LÖVE reads only a number there.
      #
      # === Example
      #
      #   channel.supply(:go, 1) # => true
      def supply(value, timeout = nil)
        native.supply(Lota::Thread.share(value, 1, "supply", CHANNEL_EXPECTED), seconds(timeout))
      end

      # Takes the first message off the queue and returns it, or +nil+
      # when the queue is empty, matching Channel:pop.
      #
      # === Example
      #
      #   while (message = channel.pop)
      #     handle(message)
      #   end
      def pop
        Lota::Thread.receive(native.pop)
      end

      # Takes the first message off the queue, waiting for one: forever,
      # or for +timeout+ seconds at most, matching Channel:demand. Returns
      # +nil+ when the time runs out first.
      #
      # === Example
      #
      #   message = channel.demand(0.5)
      def demand(timeout = nil)
        Lota::Thread.receive(native.demand(seconds(timeout)))
      end

      # The first message, left on the queue, or +nil+, matching
      # Channel:peek.
      #
      # === Example
      #
      #   channel.peek # => "hello"
      def peek
        Lota::Thread.receive(native.peek)
      end

      # How many messages wait in the queue, matching Channel:getCount.
      #
      # === Example
      #
      #   channel.count # => 1
      def count
        native.count
      end

      # Whether the message numbered +id+, which #push returned, was read,
      # matching Channel:hasRead. Raises TypeError for an +id+ that is not
      # a number.
      #
      # === Example
      #
      #   channel.read?(id) # => false
      def read?(id)
        raise TypeError, "wrong argument type #{id.class} (expected Numeric)" unless id.is_a?(Numeric)

        native.read?(id)
      end

      # Empties the queue, matching Channel:clear; a thread waiting in
      # #supply for one of its messages to be read stops waiting.
      #
      # === Example
      #
      #   channel.clear
      def clear
        native.clear
        nil
      end

      # Runs the block while this thread holds the channel, matching
      # Channel:performAtomic, whose function becomes the block (rule 12 of
      # doc/contributors/design/translation.md): every other thread that
      # calls one of its methods meanwhile waits until the block returns.
      # The block receives the channel and the arguments, and its value is
      # returned. Raises ArgumentError without a block.
      #
      # === Example
      #
      #   channel.perform_atomic("ping") do |channel, value|
      #     channel.clear
      #     channel.push(value)
      #   end
      def perform_atomic(*)
        raise ArgumentError, "no block given" unless block_given?

        native.lock
        begin
          yield(self, *)
        ensure
          native.unlock
        end
      end

      # The timeout LÖVE reads when it is a number (lua_isnumber), as a
      # Float, or +nil+.
      private def seconds(timeout)
        Float(timeout) if timeout.is_a?(Numeric)
      end
    end

    # SPDX-SnippetEnd
  end
end
