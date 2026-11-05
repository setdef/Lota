# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
    # ask whether it was read. A message is a value Ractors share: one
    # that is not shareable is pushed as a frozen copy (Ractor.make_shareable
    # with <tt>copy: true</tt>), so a String or an Array pushed arrives
    # frozen, and what the pusher changes after pushing is not what
    # arrives. Integers stay Integers and Symbols Symbols.
    #
    # A Channel is itself shareable, so it can be passed to a thread's
    # start, or pushed through another Channel. Lota::Thread.channel
    # gives the channel of a name; Channel.new makes one with none.
    #
    # === Example
    #
    #   results = Lota::Thread::Channel.new
    #   worker.start(results)
    #   result = results.demand(1.0)
    class Channel
      include Object

      # The engine's Channel, for Lota's own modules. :nodoc:
      attr_reader :native

      # A Channel that wraps +native+. :nodoc:
      def self.from_native(native)
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
      def initialize
        @native = Native::Thread.new_channel
        freeze
      end

      # Adds +value+ to the end of the queue, matching Channel:push, and
      # returns its number, an Integer, which #read? takes.
      #
      # Raises ArgumentError, with LÖVE's message, for a value that cannot
      # be shared, as a Proc cannot, and for one of Lota's objects that
      # stays in the thread that made it, as a Texture does.
      #
      # === Example
      #
      #   id = channel.push("hello")
      def push(value)
        @native.push(Lota::Thread.share(value, 1, "push", CHANNEL_EXPECTED))
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
        @native.supply(Lota::Thread.share(value, 1, "supply", CHANNEL_EXPECTED), seconds(timeout))
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
        @native.pop
      end

      # Takes the first message off the queue, waiting for one: forever,
      # or for +timeout+ seconds at most, matching Channel:demand. Returns
      # +nil+ when the time runs out first.
      #
      # === Example
      #
      #   message = channel.demand(0.5)
      def demand(timeout = nil)
        @native.demand(seconds(timeout))
      end

      # The first message, left on the queue, or +nil+, matching
      # Channel:peek.
      def peek
        @native.peek
      end

      # How many messages wait in the queue, matching Channel:getCount.
      def count
        @native.count
      end

      # Whether the message numbered +id+, which #push returned, was read,
      # matching Channel:hasRead. Raises TypeError for an +id+ that is not
      # a number.
      def read?(id)
        raise TypeError, "wrong argument type #{id.class} (expected Integer)" unless id.is_a?(Numeric)

        @native.read?(id)
      end

      # Empties the queue, matching Channel:clear; a thread waiting in
      # #supply for one of its messages to be read stops waiting.
      def clear
        @native.clear
        nil
      end

      # Runs the block while this thread holds the channel, matching
      # Channel:performAtomic: every other thread that calls one of its
      # methods meanwhile waits until the block returns. The block
      # receives the channel and the arguments, and its value is returned.
      # Raises ArgumentError without a block.
      #
      # === Example
      #
      #   channel.perform_atomic("ping") do |channel, value|
      #     channel.clear
      #     channel.push(value)
      #   end
      def perform_atomic(*)
        raise ArgumentError, "no block given" unless block_given?

        @native.lock
        begin
          yield(self, *)
        ensure
          @native.unlock
        end
      end

      # Whether +other+ is a Channel of the same queue, as LÖVE's == asks
      # of two of its objects (src/common/runtime.cpp, w__eq).
      def ==(other)
        other.is_a?(Channel) && @native == other.native
      end

      alias eql? ==

      # A number that is the same for two Channels of the same queue.
      def hash
        @native.hash
      end

      # The channel's type and address, as LÖVE prints one of its objects
      # (w__tostring).
      def to_s
        @native.to_s
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
