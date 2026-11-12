# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# The translation's one seam onto threads, and not a translation of any
# file of FLASH-BLIP's. The game makes threads in two places, music.lua,
# which generates its music's SoundData in one, and http_client.lua, which
# makes each HTTP request in one, and reads what each hands back from a
# channel. Lota's counterpart of love.thread, Lota::Thread, has not landed,
# so both call new_thread and channel here, and nowhere else, in place of
# Lota::Thread::Thread.new and Lota::Thread.channel.
#
# Once Lota has Lota::Thread, these return its Threads and Channels, and
# the thread code, which is written as Lota::Thread runs it, in a Ractor of
# its own with its arguments in ARGV, runs there. Until then a Thread here
# runs its code to its end, on the main thread, when it starts, which is
# what the parity harness makes every thread in both engines do anyway
# (test/parity/lua/conf.lua, wait_for_threads), and a Channel is a queue
# on the main thread.
module Threads
  # The Thread that runs the Ruby source +code+, matching
  # love.thread.newThread with code.
  def self.new_thread(code)
    lota_threads? ? Lota::Thread::Thread.new(code) : Inline.new(code)
  end

  # The Channel named +name+, the same each time, matching
  # love.thread.getChannel.
  def self.channel(name)
    lota_threads? ? Lota::Thread.channel(name) : (@channels[name] ||= Channel.new)
  end

  # Whether Lota has its counterpart of love.thread.
  def self.lota_threads?
    Lota.const_defined?(:Thread, false)
  end

  @channels = {}

  # A thread that runs its code when it starts, until Lota has threads.
  class Inline
    def initialize(code)
      @code = code
    end

    # Runs the code to its end with +arguments+ in ARGV, as a thread's code
    # gets them, in an object of its own, so the methods it defines stay
    # its own as they would in a Ractor of its own; returns true, as
    # Thread:start does when the thread was not running.
    def start(*arguments)
      saved = ARGV.dup
      ARGV.replace(arguments)
      ::Object.new.instance_eval(@code, "@string")
      true
    ensure
      ARGV.replace(saved)
    end

    def running?
      false
    end

    def wait
      nil
    end
  end

  # A queue of values, matching Channel's push, pop, and clear.
  class Channel
    def initialize
      @values = []
    end

    def push(value)
      @values.push(value)
      @values.size
    end

    def pop
      @values.shift
    end

    def clear
      @values.clear
      nil
    end
  end
end
