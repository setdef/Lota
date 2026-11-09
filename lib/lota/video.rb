# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "video/video_stream"

module Lota
  # The decoder that reads video files, translated from love.video.
  #
  # LÖVE plays Ogg Theora video, the <tt>.ogv</tt> files a free encoder
  # such as ffmpeg writes. Its video module decodes each file's frames on
  # a thread of its own while the game runs, a Lota::Video::VideoStream
  # for each file. Most games never touch a stream: a
  # Lota::Graphics::Video makes its own, and draws and plays it with its
  # sound. A stream on its own is for a game that wants the frames
  # without the drawing, or two videos kept in step.
  #
  # Lota opens it before Lota::Graphics, as LÖVE does, unless your
  # settings turn it off (<tt>t.modules.video = false</tt>), and then
  # neither Lota::Video::VideoStream.new nor Lota::Graphics::Video.new of
  # a file can read one.
  #
  # === Example
  #
  #   stream = Lota::Video::VideoStream.new("videos/intro.ogv")
  #   stream.play
  #   stream.playing? # => true
  module Video
  end
end
