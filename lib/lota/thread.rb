# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "thread/channel"
require_relative "thread/thread"

module Lota
  # Code that runs beside the game, translated from love.thread.
  #
  # A game that loads a level, decodes sounds, or searches a path while it
  # keeps drawing needs that work off the game loop, and a way to hand
  # results back without two pieces of code changing one object at once.
  #
  # Lota::Thread runs each thread's code in a Ruby Ractor of its own, as
  # LÖVE runs each in a Lua state of its own, and threads talk through
  # Channels, queues any of them may push to and pop from. A Channel
  # carries only values Ractors share: a value that is not one goes as a
  # frozen copy, so what arrives is what was pushed, and no two threads
  # ever change one value. Lota's Data objects (FileData, ImageData,
  # SoundData, and the rest), Channels, and Threads go as themselves,
  # shared, as LÖVE passes its objects.
  #
  # A thread's code may use every module but Lota::Graphics and
  # Lota::Window, which LÖVE keeps on the main thread: in a thread
  # <tt>lota.graphics</tt> and <tt>lota.window</tt> are +nil+, and their
  # functions raise ThreadError. Lota also keeps Lota::Joystick,
  # Lota::Keyboard, Lota::Mouse, Lota::Sensor, Lota::System, and
  # Lota::Touch on the main thread, which LÖVE lets threads use: they call
  # SDL functions SDL allows only on the main thread, or read state LÖVE
  # keeps without a lock and the main thread's event pump changes.
  # Calling one from a thread raises Ractor::UnsafeError.
  #
  # Ruby calls Ractors experimental and warns once, as a program makes its
  # first; Lota turns that warning off while it makes a thread's Ractor,
  # and back on after, so a game's threads print nothing Lua's would not.
  #
  # === Example
  #
  #   # main.rb
  #   def Lota.load
  #     @loader = Lota::Thread::Thread.new("loader.rb")
  #     @loader.start("level1.txt")
  #   end
  #
  #   def Lota.update(dt)
  #     level = Lota::Thread.channel("levels").pop
  #     @level = level if level
  #   end
  #
  #   # loader.rb
  #   name = ARGV.first
  #   contents, = Lota::Filesystem.read(name)
  #   Lota::Thread.channel("levels").push(contents)
  module Thread
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # What LÖVE's Channel says it carries when it is given something else
    # (src/modules/thread/wrap_Channel.cpp:39 and 53). :nodoc:
    CHANNEL_EXPECTED = "boolean, number, string, love type, or table expected"

    # What LÖVE's Thread:start says it passes (wrap_LuaThread.cpp:48).
    # :nodoc:
    START_EXPECTED = "boolean, number, string, love type, or flat table expected"

    # SPDX-SnippetEnd

    # Whether this Ruby lets a thread's Ractor call into Lota's engine:
    # Ruby 4.1 and newer. Ruby 4.0's rb_gc_register_address, which the
    # engine's bindings call for every Ruby value they hold, changes one
    # list for the whole VM without a lock, so two Ractors in the engine at
    # once crash Ruby; Ruby 4.1 keeps one for each Ractor (Feature #22277).
    # :nodoc:
    RACTORS = RUBY_VERSION >= "4.1"

    # What Thread#start raises on a Ruby without RACTORS. :nodoc:
    NEEDS_RUBY_41 = "Lota::Thread needs Ruby 4.1 or newer: on Ruby 4.0 two Ractors cannot use Lota's engine at once " \
      "(Feature #22277)"

    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib

    # The Channel named +name+, matching love.thread.getChannel
    # (src/modules/thread/wrap_ThreadModule.cpp, w_getChannel): the same
    # channel each time, in every thread, made the first time any thread
    # asks for the name.
    #
    # [name] String name of the channel.
    #
    # Two calls return Channels that are <tt>==</tt>, as LÖVE's are.
    # Raises RuntimeError when the thread module is not open.
    #
    # === Example
    #
    #   Lota::Thread.channel("progress").push(0.5)
    def self.channel(name)
      Channel.__send__(:from_native, Native::Thread.channel(name))
    end

    # +value+ as a value Ractors share, for the argument at +position+ of
    # the method +name+: itself when it is one, and otherwise a frozen
    # copy, as Ractor.make_shareable copies it. Raises ArgumentError, with
    # LÖVE's message +expected+, for a value that cannot be one, such as a
    # Proc, which LÖVE refuses as it refuses a Lua function, and for an
    # engine object that stays in the Ractor that made it, as a Transform
    # does, which LÖVE would pass. :nodoc:
    def self.share(value, position, name, expected)
      return value if Ractor.shareable?(value)

      if value.is_a?(Lota::Object)
        raise ArgumentError, "bad argument ##{position} to '#{name}' (#{value.object_type} stays in the thread that made it)"
      end

      begin
        Ractor.make_shareable(value, copy: true)
      rescue Ractor::Error, TypeError, ArgumentError
        raise ArgumentError, "bad argument ##{position} to '#{name}' (#{expected})"
      end
    end

    # SPDX-SnippetEnd
  end
end
