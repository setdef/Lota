# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"
require_relative "../callback_helper"

# When the audio device goes away, LÖVE's OpenAL pool stops every playing
# Source and queues an audiodisconnected message with a table of them
# (vendor/love/src/modules/audio/openal/Pool.cpp:126-133), and LÖVE's
# handler passes the table to the game's callback, then, unless the
# callback returned a truthy value, moves playback to the system's default
# device (vendor/love/src/modules/love/callbacks.lua:145-149).
class AudioDisconnectedTest < Minitest::Test
  include CallbackHelper

  def setup
    super
    EngineHelper.open_window
  end

  # Runs the block while Lota::Audio.set_playback_device records the
  # arguments of each call and passes the call on, and returns them.
  def playback_device_calls
    calls = []
    original = Lota::Audio.singleton_class.instance_method(:set_playback_device)
    Lota::Audio.singleton_class.remove_method(:set_playback_device)
    Lota::Audio.define_singleton_method(:set_playback_device) do |*arguments|
      calls << arguments
      original.bind_call(self, *arguments)
    end
    yield
    calls
  ensure
    Lota::Audio.singleton_class.remove_method(:set_playback_device)
    Lota::Audio.singleton_class.define_method(:set_playback_device, original)
  end

  # The message as Native::Event.poll gives it: the name, then the table
  # of Sources as Lota::Variant's tokens, its keys counting from 1.
  def disconnected(*sources)
    tokens = [:table, sources.size, *sources.each.with_index(1).flat_map { |s, key| [key.to_f, s.__send__(:native)] }]
    Lota::Callbacks.message(["audiodisconnected", tokens])
  end

  def source
    Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1))
  end

  def test_the_message_carries_the_stopped_sources_as_sources
    first = source
    second = source
    name, arguments = disconnected(first, second)

    assert_equal :audiodisconnected, name
    assert_equal [[first, second]], arguments
    assert_equal [Lota::Audio::Source, Lota::Audio::Source], arguments.first.map(&:class)
  end

  def test_the_callback_receives_the_sources
    stopped = source
    received = nil
    define_callback(:audiodisconnected) { |sources| received = sources }

    name, arguments = disconnected(stopped)
    Lota::Callbacks.handle(name, *arguments)

    assert_equal [stopped], received
  end

  def test_without_a_callback_playback_moves_to_the_default_device
    calls = playback_device_calls { Lota::Callbacks.handle(:audiodisconnected, []) }

    assert_equal [[]], calls
  end

  def test_a_callback_that_returns_a_falsy_value_lets_playback_move
    define_callback(:audiodisconnected) { |_sources| false }

    calls = playback_device_calls { Lota::Callbacks.handle(:audiodisconnected, []) }

    assert_equal [[]], calls
  end

  def test_a_callback_that_returns_a_truthy_value_keeps_playback_where_it_is
    define_callback(:audiodisconnected) { |_sources| true }

    calls = playback_device_calls { Lota::Callbacks.handle(:audiodisconnected, []) }

    assert_empty calls
  end
end
