# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # A video the game draws and plays, matching LÖVE's Video class
    # (src/modules/graphics/Video.h).
    #
    # A cutscene or an intro is an Ogg Theora file played as the game
    # runs. A Video decodes it with a Lota::Video::VideoStream and plays
    # its sound with a Lota::Audio::Source, which the picture keeps time
    # to, and Lota::Graphics.draw shows its current frame wherever and at
    # whatever size the game draws it. Make it once, #play it, and draw it
    # every frame.
    #
    # === Example
    #
    #   intro = Lota::Graphics::Video.new("videos/intro.ogv")
    #   intro.play
    #
    #   def Lota.draw = Lota::Graphics.draw(intro, 0, 0)
    class Video < Object
      # Wraps a Video the engine made, in the one Ruby object it has while
      # that lives. :nodoc:
      private_class_method def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        video = allocate
        video.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, video)
        video
      end

      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib
      #
      # Ported from graphics.newVideo
      # (vendor/love/src/modules/graphics/wrap_Graphics.lua:30-52) and the Video
      # methods of wrap_Video.lua (lines 28-56), and changed to take the
      # settings table as keywords (rule 10 of
      # doc/contributors/design/translation.md).

      # Makes a Video, matching love.graphics.newVideo
      # (src/modules/graphics/wrap_Graphics.lua, graphics.newVideo, and
      # wrap_Graphics.cpp, w_newVideo).
      #
      # [file] String path of an Ogg Theora file, found in the game's
      #   folder or its save directory, a Lota::Filesystem::File of one,
      #   or a Lota::Video::VideoStream, which the Video then draws.
      # [audio] Whether to play the file's sound: +true+, which raises
      #   when it cannot; +false+, for none; or +nil+ or left out, to play
      #   it where the file has sound and Lota::Audio is open.
      # [dpiscale] Float or Integer DPI scale the Video is drawn at, 1 by
      #   default, so that a video of 1000 pixels across at a DPI scale of
      #   2 is 500 units wide.
      #
      # Its sound is a <tt>:stream</tt> Source of the file, which the
      # picture keeps time to; without one, the stream keeps time on its
      # own clock. The Video starts paused, at 0 seconds.
      #
      # Raises RuntimeError with LÖVE's message when no window is open, for
      # a file the engine cannot open or that holds no Theora video, and,
      # with +audio+ true, for a file with no sound, or when Lota::Audio is
      # not open ("Lota::Audio was not loaded"); TypeError for a +file+ of
      # another kind; and ThreadError off the main thread.
      #
      # === Examples
      #
      #   Lota::Graphics::Video.new("videos/intro.ogv")
      #   Lota::Graphics::Video.new("videos/intro.ogv", audio: false, dpiscale: 2)
      def self.new(file, audio: nil, dpiscale: nil)
        Native::Graphics.check_created
        stream = file.is_a?(Lota::Video::VideoStream) ? file : Lota::Video::VideoStream.new(file)
        video = from_native(Native::Graphics.new_video(stream.__send__(:native), dpiscale.nil? ? 1.0 : dpiscale))
        source = audio_source(video, audio)
        if source
          video.source = source
        elsif audio == true
          raise(Lota.audio ? "Video had no audio track" : "Lota::Audio was not loaded")
        else
          video.stream.sync = nil
        end
        video
      end

      # The Source that plays +video+'s sound, or +nil+ where +audio+ is
      # false, Lota::Audio is not open, or the file has none, which LÖVE
      # finds by trying to make one with pcall.
      private_class_method def self.audio_source(video, audio)
        return nil if audio == false || !Lota.audio

        begin
          Audio::Source.new(video.stream.filename, :stream, :file)
        rescue
          nil
        end
      end

      # Sets the Source that plays the Video's sound, matching
      # Video:setSource (src/modules/graphics/wrap_Video.lua,
      # Video:setSource): a Lota::Audio::Source, which the picture then
      # keeps time to, or +nil+ for none, after which the stream keeps time
      # on its own clock again.
      #
      # Raises TypeError for anything else, and ThreadError off the main
      # thread.
      #
      # === Example
      #
      #   video.source = Lota::Audio::Source.new("videos/intro.ogv", :stream)
      def source=(source)
        unless source.nil? || source.is_a?(Audio::Source)
          raise TypeError, "wrong argument type #{source.class} (expected Lota::Audio::Source)"
        end

        @native.set_source(source&.__send__(:native))
        stream.sync = source
      end

      # Plays the Video, matching Video:play
      # (src/modules/graphics/wrap_Video.lua): plays its stream, and so its
      # Source, which the stream keeps time to.
      #
      # === Example
      #
      #   video.play
      def play
        stream.play
      end

      # Pauses the Video where it is, matching Video:pause
      # (src/modules/graphics/wrap_Video.lua).
      #
      # === Example
      #
      #   video.pause
      def pause
        stream.pause
      end

      # Moves the Video to +offset+, a Float or Integer number of seconds
      # from its start, matching Video:seek
      # (src/modules/graphics/wrap_Video.lua).
      #
      # === Example
      #
      #   video.seek(2.5)
      def seek(offset)
        stream.seek(offset)
      end

      # Moves the Video back to its start, matching Video:rewind
      # (src/modules/graphics/wrap_Video.lua).
      #
      # === Example
      #
      #   video.rewind
      def rewind
        stream.rewind
      end

      # Where the Video is, as a Float number of seconds from its start,
      # matching Video:tell (src/modules/graphics/wrap_Video.lua).
      #
      # === Example
      #
      #   video.tell # => 0.0
      def tell
        stream.tell
      end

      # Whether the Video is playing, matching Video:isPlaying
      # (src/modules/graphics/wrap_Video.lua): whether its stream's time
      # runs and its file is not decoded to the end.
      #
      # === Example
      #
      #   video.playing? # => false
      def playing?
        stream.playing?
      end

      # SPDX-SnippetEnd

      # The Lota::Video::VideoStream the Video draws, matching
      # Video:getStream (src/modules/graphics/wrap_Video.cpp,
      # w_Video_getStream).
      #
      # === Example
      #
      #   video.stream.filename # => "videos/intro.ogv"
      def stream
        Lota::Video::VideoStream.__send__(:from_native, @native.stream)
      end

      # The Lota::Audio::Source that plays the Video's sound, or +nil+,
      # matching Video:getSource (src/modules/graphics/wrap_Video.cpp,
      # w_Video_getSource).
      #
      # === Example
      #
      #   video.source.volume = 0.5
      def source
        native = @native.source
        native && Audio::Source.__send__(:from_native, native)
      end

      # The Video's width in units, as an Integer: its pixels across
      # divided by its DPI scale, matching Video:getWidth
      # (src/modules/graphics/wrap_Video.cpp, w_Video_getWidth).
      #
      # === Example
      #
      #   video.width # => 496
      def width
        @native.width
      end

      # The Video's height in units, as an Integer, matching
      # Video:getHeight (src/modules/graphics/wrap_Video.cpp,
      # w_Video_getHeight).
      #
      # === Example
      #
      #   video.height # => 502
      def height
        @native.height
      end

      # The Video's width and height in units, as an Array of two Integers
      # (rule 4 of doc/contributors/design/translation.md), matching
      # Video:getDimensions (src/modules/graphics/wrap_Video.cpp,
      # w_Video_getDimensions).
      #
      # === Example
      #
      #   width, height = video.dimensions # => [496, 502]
      def dimensions
        @native.dimensions
      end

      # The pixels across each frame, as an Integer, matching
      # Video:getPixelWidth (src/modules/graphics/wrap_Video.cpp,
      # w_Video_getPixelWidth).
      #
      # === Example
      #
      #   video.pixel_width # => 496
      def pixel_width
        @native.pixel_width
      end

      # The pixels down each frame, as an Integer, matching
      # Video:getPixelHeight (src/modules/graphics/wrap_Video.cpp,
      # w_Video_getPixelHeight).
      #
      # === Example
      #
      #   video.pixel_height # => 502
      def pixel_height
        @native.pixel_height
      end

      # The pixels across and down each frame, as an Array of two Integers
      # (rule 4 of doc/contributors/design/translation.md), matching
      # Video:getPixelDimensions (src/modules/graphics/wrap_Video.cpp,
      # w_Video_getPixelDimensions).
      #
      # === Example
      #
      #   video.pixel_dimensions # => [496, 502]
      def pixel_dimensions
        @native.pixel_dimensions
      end

      # Sets how the Video is filtered when drawn smaller and larger,
      # matching Video:setFilter (src/modules/graphics/wrap_Video.cpp,
      # w_Video_setFilter), as Lota::Graphics::Texture#filter= takes it:
      # the filter when drawn smaller, +:linear+ or +:nearest+, alone or in
      # an Array with the filter when drawn larger (the first by default)
      # and the Integer maximum anisotropy (1 by default).
      #
      # A Video starts with Lota::Graphics.default_filter. Raises
      # ArgumentError for an unknown filter, TypeError for an anisotropy
      # that is not a number, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   video.filter = :nearest
      #   video.filter = :linear, :linear, 2
      def filter=(filter)
        min, mag, anisotropy = filter.is_a?(Array) ? filter : [filter]
        anisotropy = case anisotropy
        when Integer, Float then anisotropy
        when nil then 1
        else raise TypeError, "wrong argument type #{anisotropy.class} for anisotropy (expected Integer)"
        end
        @native.set_filter(EnumName.of(min), mag && EnumName.of(mag), anisotropy)
      end

      # The filters when drawn smaller and larger, as Symbols, and the Integer
      # maximum anisotropy, as an Array (rule 4 of
      # doc/contributors/design/translation.md), matching Video:getFilter
      # (src/modules/graphics/wrap_Video.cpp, w_Video_getFilter).
      #
      # === Example
      #
      #   min, mag, anisotropy = video.filter # => [:nearest, :nearest, 1]
      def filter
        min, mag, anisotropy = @native.filter
        [min.to_sym, mag.to_sym, anisotropy]
      end
    end
  end
end
