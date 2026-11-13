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
      # A thread of a file is named for it, as LÖVE names it, and its
      # backtraces, +__FILE__+, +__dir__+, and +require_relative+ use the
      # file's real path; one of a String of code is "string"; one of
      # a FileData is its filename; one of another Data is "Thread code". Raises RuntimeError, with LÖVE's
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

          [chunk_name(code), Filesystem::FileData.__send__(:from_native, Native::Filesystem.file_data(code)).string]
        when Filesystem::File
          _, text = source(code.read(:data).first)
          [chunk_name(code.filename), text]
        when Filesystem::FileData then ["@#{code.filename}", code.string]
        when Lota::Data then ["Thread code", code.string]
        else raise TypeError, "wrong argument type #{code.class} (expected Lota::Data)"
        end
      end

      # The name of the chunk of the file +filename+ of the game's, as
      # LÖVE names it, "@" and the file's name (w_newThread,
      # wrap_ThreadModule.cpp:70). Lua shows that name as the file; Ruby
      # needs the file's real path for +__FILE__+, +__dir__+, and
      # +require_relative+, so it is the path the game's folder or save
      # directory holds the file at, or, for a file in an archive, the
      # path of its copy in the folder Lota::Archive unpacked the archive
      # into, or the name alone for one in any other archive, which has
      # none. :nodoc:
      private_class_method def self.chunk_name(filename)
        directory, = Filesystem.real_directory(filename)
        directory = Archive.unpacked(directory) || directory if directory
        path = directory && ::File.join(directory, filename)
        "@#{(path && ::File.file?(path)) ? path : filename}"
      end

      # Starts the thread, matching Thread:start: runs its code in a new
      # Ractor, with +arguments+ in its +ARGV+, and returns +true+, or
      # returns +false+ when the thread already runs. Each argument goes as
      # a value Ractors share, as a Channel carries it.
      #
      # Raises ArgumentError, with LÖVE's message, for an argument that
      # cannot be shared, as a Channel's #push does.
      #
      # === Example
      #
      #   thread.start("level1.txt", 3)
      def start(*arguments)
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
          load_decorations
          quietly { ractor(thread, arguments) }
          started = true
        ensure
          # A Ractor that never started never ends its run.
          thread.__send__(:native).finish unless started
        end

        # The gems Ruby decorates an error's message with, which it loads
        # by autoload the first time it prints an error (error.c,
        # require_decoration_gems). :nodoc:
        DECORATIONS = %i[ErrorHighlight DidYouMean SyntaxSuggest].freeze

        # Loads DECORATIONS on the main Ractor, before a thread can print an
        # error, which #error keeps as Ruby prints it. Ruby 4.1 fires an
        # autoload in another Ractor by first asking, in that Ractor,
        # whether its file is loaded, which rebuilds the expanded load path
        # that every Ractor shares, after $LOAD_PATH has changed, out of
        # that Ractor's own objects; once the Ractor ends, the next
        # collection marks them, freed, and Ruby stops with "[BUG] try to
        # mark T_NONE object". Loaded once, they fire no autoload in any
        # Ractor, whenever $LOAD_PATH changes. :nodoc:
        private_class_method def self.load_decorations
          return unless Ractor.main?

          DECORATIONS.each { |name| ::Object.const_get(name) if ::Object.autoload?(name) }
        end

        # Runs the block with Ruby's warnings of experimental features off,
        # on the main Ractor, and then as they were. Ruby warns once, as
        # the main Ractor makes a program's first Ractor, that Ractors are
        # experimental (ractor.rb, Ractor.new); a LÖVE game's
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

        # The Ractor itself, which receives +thread+ as its own wrapper of
        # the same engine object (Lota::Thread.carry). :nodoc:
        private_class_method def self.ractor(thread, arguments)
          carried = Ractor.make_shareable(Lota::Thread.carry(thread))
          Ractor.new(carried, arguments, name: thread.__send__(:native).name) do |started, values|
            # @type var own: Lota::Thread::Thread
            own = Lota::Thread.receive(started)
            Lota::Thread::Thread::Body.run(own, values)
          end
        end

        # The files a thread requires before its code runs, as
        # LuaThread::threadFunction requires love, love.thread, and
        # love.filesystem (LuaThread.cpp:66-82), in that order. :nodoc:
        REQUIRES = %w[lota lota/thread lota/filesystem].freeze

        # Runs +thread+'s code with +arguments+ as its +ARGV+, in the
        # thread's Ractor, and reports how it ended, step for step as
        # LuaThread::threadFunction runs a thread's chunk and keeps its
        # error (LuaThread.cpp:50-115). The Ractor and an object of its own
        # stand for the new Lua state with Lua's libraries open. It then
        # requires REQUIRES, as LÖVE requires its modules there, and as
        # LÖVE requires love.filesystem so that a thread's require finds
        # the game's files; Ruby 4.1 runs a Ractor's require in the main
        # Ractor, whose $LOAD_PATH holds the game's folder (Lota::Boot).
        # LÖVE's window and graphics, which it preloads as errors, are
        # +nil+ through <tt>lota.window</tt> and <tt>lota.graphics</tt>
        # here, and raise ThreadError. Then the code runs, with a fresh
        # copy of +arguments+ in its +ARGV+ (Lota::Thread.receive), as
        # LÖVE pushes the arguments anew. The errors that end it with one
        # are those Lota's error handler takes from a game
        # (Lota::Callbacks::ERRORS), as Lua's pcall takes a chunk's
        # errors; an +exit+ in its code ends it without one. :nodoc:
        def self.run(thread, arguments)
          native = thread.__send__(:native)
          error = nil
          begin
            main = ::Object.new
            REQUIRES.each { |feature| require feature }
            main.singleton_class.const_set(:ARGV, Lota::Thread.receive(arguments))
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
