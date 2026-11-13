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
  # Channels, queues any of them may push to and pop from. A Channel keeps
  # a copy of what was pushed, as LÖVE's keeps a Variant, so what the
  # pusher changes afterward never reaches the queue, and each pop, demand,
  # or peek hands back a fresh copy the receiver may change, as LÖVE hands
  # back a new table: Strings, Arrays, and Hashes arrive unfrozen, all
  # through. Every one of Lota's objects goes as itself, as LÖVE passes
  # its objects, and reaches the thread that pops it as a wrapper of that
  # thread's own, of the same object, as LÖVE gives each Lua state a
  # userdata of its own: a release in one thread ends only that thread's
  # use of it. The Ruby values a game sets on an object, a Body's user
  # data or a World's callbacks, stay with the thread that set them, which
  # alone may use them, as they stay in the Lua state that set them in
  # LÖVE; Ruby lets no other Ractor touch them, and another thread that
  # tries meets Ractor::IsolationError.
  #
  # A thread's code may use every module but Lota::Graphics and
  # Lota::Window, which LÖVE keeps on the main thread: in a thread
  # <tt>lota.graphics</tt> and <tt>lota.window</tt> are +nil+, and their
  # functions raise ThreadError.
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

    # An engine object a message holds: the class of Lota's that wrapped
    # it, and the engine's Carried, which keeps the object for whichever
    # Ractor receives it (ext/lota/native/thread.hpp), as LÖVE's Variant
    # keeps the object a channel carries. :nodoc:
    class Carried < ::Data.define(:lota_class, :carried)
    end

    # +value+ as a value Ractors share, for the argument at +position+ of
    # the method +name+: itself when it is one, and otherwise a frozen
    # copy, as Ractor.make_shareable copies it, with each engine object in
    # it carried as a Carried, as LÖVE's Variant carries any of its
    # objects. Raises ArgumentError, with LÖVE's message
    # +expected+, for a value that cannot be one, such as a Proc, which
    # LÖVE refuses as it refuses a Lua function. :nodoc:
    def self.share(value, position, name, expected)
      return value if Ractor.shareable?(value)

      begin
        Ractor.make_shareable(carry(value), copy: true)
      rescue Ractor::Error, TypeError, ArgumentError
        raise ArgumentError, "bad argument ##{position} to '#{name}' (#{expected})"
      end
    end

    # +value+ with each engine object in it, inside Arrays and Hashes too,
    # replaced by its Carried. :nodoc:
    def self.carry(value)
      case value
      when Lota::Object
        Carried.new(lota_class: value.class,
          carried: Ractor.make_shareable(Native::Thread.carry(value.__send__(:native))))
      when Array then value.map { |element| carry(element) }
      when Hash then value.to_h { |key, element| [carry(key), carry(element)] }
      else value
      end
    end

    # A fresh copy of +value+, a message a Channel kept or an argument a
    # thread was started with, which Ractors share, for the Ractor that
    # receives it to change, as LÖVE pushes a Variant's string and table
    # anew for the Lua state that pops it (luax_pushvariant): every String,
    # Array, and Hash in it is copied, unfrozen, and each engine object it
    # carried is wrapped for this Ractor, by this Ractor's wrapper of the
    # object, as LÖVE pushes a userdata of the Lua state that pops it.
    # Everything else comes back as itself: numbers, Symbols, nil, and
    # booleans, which Ruby never copies; and any other Ruby object, which
    # has no LÖVE counterpart, as the frozen copy Ractors share. :nodoc:
    def self.receive(value)
      case value
      when Carried then value.lota_class.__send__(:from_native, value.carried.object)
      when String then value.dup
      when Array then value.map { |element| receive(element) }
      when Hash then value.to_h { |key, element| [receive(key), receive(element)] }
      else value
      end
    end

    # SPDX-SnippetEnd
  end
end
