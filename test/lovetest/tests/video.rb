# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../lovetest_helper"

# Lövetest's love.video tests (vendor/love/testing/tests/video.lua), translated
# to Ruby by the rules of doc/contributors/design/translation.md, both of them.
# Like the graphics tests, they run in the test suite's own process
# (test/lovetest/video_test.rb) and under lota run (test/lovetest/game).
class VideoTest < Lovetest::TestMethod
  # The types whose tests Lövetest names by the type (love.test.video.VideoStream).
  TYPES = %w[VideoStream].freeze

  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib
  #
  # Translated to Ruby from love.test.video.VideoStream
  # (vendor/love/testing/tests/video.lua:12-32): newVideoStream becomes
  # VideoStream.new (rule 2), getFilename filename (rule 3), and
  # isPlaying playing? (rule 8); play, seek, tell, rewind, and pause keep
  # their names (rule 13). assertRange becomes assert_includes of a
  # Range, as test_source in tests/audio.rb has it.
  def test_video_stream
    # create obj
    video = Lota::Video::VideoStream.new("resources/sample.ogv")
    assert_object(video)

    # check def properties
    assert_equal("resources/sample.ogv", video.filename, "check filename")
    assert_false(video.playing?, "check not playing by def")

    # check playing and pausing states
    video.play
    assert_true(video.playing?, "check now playing")
    video.seek(0.3)
    assert_includes(0.3..0.4, video.tell, "check seek/tell")
    video.rewind
    assert_includes(0..0.1, video.tell, "check rewind")
    video.pause
    assert_false(video.playing?, "check paused")
  end

  # Translated to Ruby from love.test.video.newVideoStream
  # (vendor/love/testing/tests/video.lua:44-46), by the rule
  # test_video_stream names.
  def test_new_video_stream
    assert_object(Lota::Video::VideoStream.new("resources/sample.ogv"))
  end

  # SPDX-SnippetEnd
end
