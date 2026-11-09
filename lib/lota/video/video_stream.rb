# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Video
    # The decoded frames of a video file, matching LÖVE's VideoStream
    # class (src/modules/video/VideoStream.h).
    #
    # A stream decodes its file's frames on the video module's thread, a
    # little ahead of where it is, and keeps time to know which frame is
    # current: on its own clock, which runs while it plays, or by a
    # Lota::Audio::Source or another stream it follows (#sync=). A
    # Lota::Graphics::Video draws its stream's current frame.
    #
    # === Example
    #
    #   stream = Lota::Video::VideoStream.new("videos/intro.ogv")
    #   stream.play
    #   stream.seek(2.5)
    #   stream.tell # => 2.5
    class VideoStream < Object
      # Wraps a VideoStream the engine made, in the one Ruby object it
      # has while that lives, as LÖVE pushes one Lua userdata for each.
      # :nodoc:
      private_class_method def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        stream = allocate
        stream.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, stream)
        stream
      end

      # Makes a VideoStream of a video file, matching
      # love.video.newVideoStream (src/modules/video/wrap_Video.cpp,
      # w_newVideoStream).
      #
      # [file] String path of an Ogg Theora file, found in the game's
      #   folder or its save directory, or a Lota::Filesystem::File of
      #   one, which it opens for reading unless it is open.
      #
      # The stream starts paused, at 0 seconds, on its own clock.
      #
      # Raises TypeError for a +file+ of another kind, and RuntimeError,
      # with LÖVE's message, for a file the engine cannot open or that
      # holds no Theora video, and when the video or the filesystem module
      # is not open.
      #
      # === Examples
      #
      #   Lota::Video::VideoStream.new("videos/intro.ogv")
      #
      #   file, = Lota::Filesystem.open_file("videos/intro.ogv", :r)
      #   Lota::Video::VideoStream.new(file)
      def self.new(file)
        native = case file
        when String then Native::Video.new_video_stream(file)
        when Filesystem::File then Native::Video.new_video_stream_from_file(file.__send__(:native))
        else raise TypeError, "wrong argument type #{file.class} (expected String or Lota::Filesystem::File)"
        end
        from_native(native)
      end

      # Sets what the stream keeps time by, matching VideoStream:setSync
      # (src/modules/video/wrap_VideoStream.cpp, w_VideoStream_setSync).
      #
      # [sync] A Lota::Audio::Source, whose position and playback the
      #   stream then follows, so that the picture keeps to its sound;
      #   another VideoStream, whose time the stream then shares; or
      #   +nil+, for its own clock again, which starts where the stream
      #   was, playing or paused as it was.
      #
      # Raises TypeError for anything else, as LÖVE does.
      #
      # === Examples
      #
      #   stream.sync = Lota::Audio::Source.new("videos/intro.ogv", :stream)
      #   stream.sync = nil
      def sync=(sync)
        case sync
        when Audio::Source then @native.set_sync_to_source(sync.__send__(:native))
        when VideoStream then @native.set_sync_to_stream(sync.native)
        when nil then @native.set_sync_to_delta
        else raise TypeError, not_a_sync(sync)
        end
      end

      # The message for a +sync+ that sync= cannot keep time by, as
      # luax_typerror words what LÖVE expected.
      private def not_a_sync(sync)
        "wrong argument type #{sync.class} (expected Lota::Audio::Source, Lota::Video::VideoStream, or nil)"
      end

      # The path the stream was made from, as a String, matching
      # VideoStream:getFilename (src/modules/video/wrap_VideoStream.cpp,
      # w_VideoStream_getFilename).
      #
      # === Example
      #
      #   stream.filename # => "videos/intro.ogv"
      def filename
        @native.filename
      end

      # Starts the stream's time running, matching VideoStream:play
      # (src/modules/video/wrap_VideoStream.cpp, w_VideoStream_play). It
      # plays what it keeps time by: its own clock, or the Source or
      # stream it follows.
      #
      # === Example
      #
      #   stream.play
      def play
        @native.play
      end

      # Stops the stream's time where it is, matching VideoStream:pause
      # (src/modules/video/wrap_VideoStream.cpp, w_VideoStream_pause).
      #
      # === Example
      #
      #   stream.pause
      def pause
        @native.pause
      end

      # Moves the stream to +offset+, a Float or Integer number of seconds
      # from its start, matching VideoStream:seek
      # (src/modules/video/wrap_VideoStream.cpp, w_VideoStream_seek).
      #
      # === Example
      #
      #   stream.seek(2.5)
      def seek(offset)
        @native.seek(offset)
      end

      # Moves the stream back to its start, matching VideoStream:rewind
      # (src/modules/video/wrap_VideoStream.cpp, w_VideoStream_rewind).
      #
      # === Example
      #
      #   stream.rewind
      def rewind
        @native.rewind
      end

      # Where the stream is, as a Float number of seconds from its start,
      # matching VideoStream:tell (src/modules/video/wrap_VideoStream.cpp,
      # w_VideoStream_tell).
      #
      # === Example
      #
      #   stream.tell # => 0.0
      def tell
        @native.tell
      end

      # Whether the stream's time is running and its file not yet decoded
      # to the end, matching VideoStream:isPlaying
      # (src/modules/video/wrap_VideoStream.cpp, w_VideoStream_isPlaying).
      #
      # === Example
      #
      #   stream.playing? # => false
      def playing?
        @native.playing?
      end
    end
  end
end
