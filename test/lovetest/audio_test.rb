# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runs Lövetest's love.audio tests, translated in tests/audio.rb, in the
# test suite's own process.
require_relative "../test_helper"
require_relative "tests/audio"

# Lövetest's audio tests set the listener's volume, position, orientation,
# and velocity, and the distance model, and leave them set. AudioTest ends
# each test with the listener it began with, so that a suite that runs
# after one of them, in the same process, hears through the listener LÖVE
# starts with. Without that, this fails with the last test's settings.
class AudioListenerTest < Minitest::Test
  LISTENER = %i[volume position orientation velocity doppler_scale distance_model].freeze
  LEAVING = %w[
    test_set_volume
    test_get_position
    test_get_orientation
    test_get_velocity
    test_set_distance_model
].freeze

  def test_an_audio_test_leaves_the_listener_as_it_found_it
    EngineHelper.open_window
    skip("audio is not open") unless Lota.audio

    Lota::Audio.distance_model = :inverseclamped
    before = listener

    LEAVING.each { |name| assert_predicate AudioTest.new(name).run, :passed?, name }

    assert_equal before, listener
  ensure
    before&.each { |name, value| Lota::Audio.public_send(:"#{name}=", value) }
  end

  private def listener = LISTENER.to_h { |name| [name, Lota::Audio.public_send(name)] }
end
