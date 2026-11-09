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
    # Translated from LÖVE's Thread (src/modules/thread/wrap_LuaThread.cpp
    # and LuaThread.cpp) and love.thread.newThread (wrap_ThreadModule.cpp,
    # w_newThread).

    # Ruby code that runs beside the game, in a Ractor of its own,
    # translated from LÖVE's Thread.
    #
    # Its code is a file of the game's, or a String of Ruby code, which
    # #start runs from the top, as LÖVE runs a thread's Lua chunk, with
    # +self+ an object of its own, so the methods it defines are its own,
    # and with the arguments #start was given in its +ARGV+, as a Ruby
    # script finds its own. What it raises ends it, and becomes #error,
    # and Lota's loop then calls Lota.threaderror with the thread and the
    # error, whose default raises it in the game
    # (Lota::DefaultCallbacks#threaderror).
    #
    # Its code reaches the rest of the game only through Channels and the
    # values it was started with, as a Ractor reaches other Ractors
    # (Lota::Thread). A thread may be started again once it has ended.
    #
    # === Example
    #
    #   thread = Lota::Thread::Thread.new(<<~RUBY)
    #     sum = (1..ARGV.first).sum
    #     Lota::Thread.channel("sums").push(sum)
    #   RUBY
    #   thread.start(100)
    #   thread.wait
    #   Lota::Thread.channel("sums").pop # => 5050
    class Thread < Object
      # Wraps a Thread the engine made. :nodoc:
      private_class_method def self.from_native(native)
        thread = allocate
        thread.instance_variable_set(:@native, native)
        thread.freeze
      end

      # A thread of +code+, matching love.thread.newThread
      # (wrap_ThreadModule.cpp, w_newThread), not yet started.
      #
      # [code] A String of Ruby code, when it is 1024 bytes or longer or
      #   holds a newline, as LÖVE reads Lua code; any other String is the
      #   name of a file of the game's (Lota::Filesystem) whose code it
      #   is. Or a Lota::Filesystem::File or Lota::Filesystem::FileData of
      #   the code, or any other Lota::Data.
      #
      # A thread of a file is named for it, one of a String of code
      # "string", as LÖVE names them, and its backtraces name that; one of
      # another Data is "Thread code". Raises RuntimeError, with LÖVE's
      # message, for a file that cannot be read, and when the thread module
      # is not open, and TypeError for any other +code+.
      #
      # === Examples
      #
      #   Lota::Thread::Thread.new("worker.rb")
      #   Lota::Thread::Thread.new("puts 1 + 1\n")
      def self.new(code)
        name, source = source(code)
        from_native(Native::Thread.new_thread(name, source))
      end

      # The name, as LÖVE gives a thread, and code, as a String, of the
      # thread +code+ makes (new). :nodoc:
      private_class_method def self.source(code)
        case code
        when String
          return ["@string", code] if code.bytesize >= 1024 || code.include?("\n")

          source(Filesystem::FileData.__send__(:from_native, Native::Filesystem.file_data(code)))
        when Filesystem::File then source(code.read(:data).first)
        when Filesystem::FileData then ["@#{code.filename}", code.string]
        when Lota::Data then ["Thread code", code.string]
        else raise TypeError, "wrong argument type #{code.class} (expected Lota::Data)"
        end
      end

      # Starts the thread, matching Thread:start: runs its code in a new
      # Ractor, with +arguments+ in its +ARGV+, and returns +true+, or
      # returns +false+ when the thread already runs. Each argument goes as
      # a value Ractors share, as a Channel carries it.
      #
      # Raises ArgumentError, with LÖVE's message, for an argument that
      # cannot be shared, as a Channel's #push does, and NotImplementedError
      # on Ruby 4.0, where a thread's Ractor cannot call into Lota's engine
      # (Lota::Thread).
      #
      # === Example
      #
      #   thread.start("level1.txt", 3)
      def start(*arguments)
        raise NotImplementedError, Lota::Thread::NEEDS_RUBY_41 unless Lota::Thread::RACTORS

        values = arguments.each.with_index(1).map do |argument, position|
          Lota::Thread.share(argument, position, "start", START_EXPECTED)
        end
        return false unless native.begin

        Body.start(self, Ractor.make_shareable(values))
        true
      end

      # Waits for the thread to end, matching Thread:wait; returns at once
      # when it is not running.
      #
      # === Example
      #
      #   thread.wait
      def wait
        native.wait
        nil
      end

      # The error its last run ended with, as a String: the error's
      # message, its class, and the backtrace, as Ruby prints it, or +nil+
      # when it ended without one or has not run, matching Thread:getError.
      #
      # === Example
      #
      #   thread.error # => nil
      def error
        native.error
      end

      # Whether the thread runs, matching Thread:isRunning: true from
      # #start until its code ends.
      #
      # === Example
      #
      #   thread.running? # => true
      def running?
        native.running?
      end

      # The Ractor a thread's code runs in. :nodoc:
      module Body
        # Starts the Ractor that runs +thread+ with +arguments+, which are
        # shareable. :nodoc:
        def self.start(thread, arguments)
          started = false
          quietly { ractor(thread, arguments) }
          started = true
        ensure
          # A Ractor that never started never ends its run.
          thread.__send__(:native).finish unless started
        end

        # Runs the block with Ruby's warnings of experimental features off,
        # on the main Ractor, and then as they were. Ruby warns once, as
        # the main Ractor makes a program's first Ractor, that Ractors are
        # experimental (Ruby 4.0.7, ractor.rb:229-239); a LÖVE game's
        # threads print nothing of the kind. Another Ractor makes no first
        # one, and may not change the setting. :nodoc:
        private_class_method def self.quietly
          return yield unless Ractor.main?

          experimental = Warning[:experimental]
          Warning[:experimental] = false
          begin
            yield
          ensure
            Warning[:experimental] = experimental
          end
        end

        # The Ractor itself. :nodoc:
        private_class_method def self.ractor(thread, arguments)
          Ractor.new(thread, arguments, name: thread.__send__(:native).name) do |started, values|
            Lota::Thread::Thread::Body.run(started, values)
          end
        end

        # Runs +thread+'s code with +arguments+ as its +ARGV+, in the
        # thread's Ractor, and reports how it ended, as
        # LuaThread::threadFunction runs a thread's chunk and keeps its
        # error (LuaThread.cpp:49-115). The errors that end it with one
        # are those Lota's error handler takes from a game
        # (Lota::Callbacks::ERRORS), as Lua's pcall takes a chunk's
        # errors; an +exit+ in its code ends it without one. :nodoc:
        def self.run(thread, arguments)
          native = thread.__send__(:native)
          error = nil
          begin
            main = ::Object.new
            main.singleton_class.const_set(:ARGV, arguments)
            main.instance_eval(native.code, native.name.delete_prefix("@"), 1)
          rescue *Callbacks::ERRORS => e
            error = e.full_message(highlight: false)
          ensure
            native.finish(error)
          end
          nil
        end
      end
    end

    # SPDX-SnippetEnd
  end
end
