# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"
require_relative "frame_comparison"

module Parity
  # The parity harness's Ruby side, which test/parity/lua/conf.lua mirrors
  # for LÖVE: measurement code, loaded into <tt>lota run</tt> with
  # <tt>ruby -r</tt> before the game. It runs a translated game unchanged,
  # with the same fixed dt and scripted keys as the Lua side, and compares
  # every frame the game shows with the one LÖVE showed.
  #
  # It prepends Callbacks to Lota's singleton class, so the game's own
  # <tt>def Lota.update</tt> and <tt>def Lota.draw</tt> run inside the
  # harness's, as ADR 003 has a game-state library wrap callbacks.
  # Lota.update holds the scripted keys down or lets them up in SDL's
  # keyboard state, which Lota::Keyboard.down? reads, then calls the
  # game's update with 1 / LOTA_PARITY_FPS, then pushes the key events of
  # LOTA_PARITY_PRESS due at the start of the next frame into SDL's queue,
  # through LotaNativeTest.press_key, which does not depend on the window
  # having keyboard focus. Lota.draw calls the game's
  # draw, then asks for the frame Lota::Graphics.present will show, and
  # compares it with LOTA_PARITY_FRAMES_DIR/NNNN.png, the frame LÖVE showed,
  # by Lövetest's compareImg rule (FrameComparison). After frame
  # LOTA_PARITY_FRAMES it quits, as the Lua side does, unless a pressed key
  # comes up after it, which leaves quitting to the game; a game still
  # running a frame later did not quit, and the probe quits with status 1.
  # At exit it writes LOTA_PARITY_REPORT: how many frames it compared, and
  # the first that differed, whose pixels it also saves beside the report
  # as raw RGBA.
  #
  # Every dialog the game shows, such as LÖVE's version warning, which
  # boot.lua shows before the window opens, has Return pressed on it, as
  # the Lua side does (LotaNativeTest.press_return_on_dialogs), so both
  # engines show it and neither waits for a player.
  #
  # Time.now, called with no arguments, returns LOTA_PARITY_CLOCK seconds
  # after the epoch, as the Lua side's os.time() does, so a game that
  # seeds Lota::Math's generator from the clock draws the same numbers
  # LÖVE's does (Plan 001, "Random numbers"), and Lota.load seeds the
  # generator with it before the game's load, as the Lua side seeds
  # LÖVE's, for a game that draws numbers without seeding them.
  #
  # The mouse moves and clicks as the Lua side moves and clicks it: the
  # pointer is held at the latest of LOTA_PARITY_MOVE's moves, from the
  # first, in frame 1, which Lota.load puts it at, then after the game's
  # update of the frame before each, with Lota::Mouse.position=, which
  # updates SDL's mouse state and queues mousemoved, and
  # LOTA_PARITY_CLICK's clicks are pushed after it with
  # LotaNativeTest.click_mouse, at the pointer's position. Lota::Timer.delta returns DT, the dt
  # the game's update gets, as love.timer.getDelta does on the Lua side.
  #
  # Sound is measured twice, as on the Lua side. Lota.load first decodes
  # each file LOTA_PARITY_SOUNDS lists into LOTA_PARITY_SOUNDS_DIR, with
  # Lota::Sound::SoundData and Lota::Sound::Decoder, in the form the Lua
  # side writes LÖVE's (decode_sounds), so the two can be compared sample
  # for sample. And Lota.update, after the game's update, mixes the frame's
  # dt on the loopback device the harness loads into the process
  # (LotaNativeTest.render_loopback, ext/lota/native_test/loopback.cpp),
  # so the game's sounds are mixed on game time, as LÖVE's are.
  module Probe
    FRAMES_DIR = ENV.fetch("LOTA_PARITY_FRAMES_DIR")
    REPORT = ENV.fetch("LOTA_PARITY_REPORT")
    FRAMES = Integer(ENV.fetch("LOTA_PARITY_FRAMES"))
    # 1 / 60 in Lua divides as Floats; 1 / 60 in Ruby would not.
    DT = 1 / Float(ENV.fetch("LOTA_PARITY_FPS"))
    # [scancode, first frame, last frame], as the Lua side reads them.
    PRESSES = ENV.fetch("LOTA_PARITY_PRESS", "").scan(/(\d+):(\d+)-(\d+)/).map { |key| key.map(&:to_i) }.freeze
    # A pressed key is held for its frames too.
    HOLDS = (ENV.fetch("LOTA_PARITY_HOLD", "").scan(/(\d+):(\d+)-(\d+)/).map { |key| key.map(&:to_i) } +
      PRESSES).freeze
    # Whether a pressed key comes up after the last frame, so that the
    # game, not the probe, ends the run.
    GAME_QUITS = PRESSES.any? { |_, _, last| last == FRAMES }
    # The seconds since the epoch the clock is fixed at.
    CLOCK = Integer(ENV.fetch("LOTA_PARITY_CLOCK"))
    # The file the loopback device's mix goes to.
    LOOPBACK_FILE = ENV.fetch("LOTA_LOOPBACK_FILE")
    # [frame, x, y], as the Lua side reads them.
    MOVES = ENV.fetch("LOTA_PARITY_MOVE", "").scan(/(\d+):(-?[\d.]+):(-?[\d.]+)/)
      .map { |frame, x, y| [Integer(frame), Float(x), Float(y)] }.freeze
    # [button, first frame, last frame], as the Lua side reads them.
    CLICKS = ENV.fetch("LOTA_PARITY_CLICK", "").scan(/(\d+):(\d+)-(\d+)/).map { |click| click.map(&:to_i) }.freeze

    @frame = 0
    @compared = 0
    @mismatch = nil

    class << self
      # The frame under way, counting from 1.
      attr_reader :frame

      # Starts the next frame, and holds each scripted key down, or lets it
      # up, for it. A key listed twice is down when either range holds it.
      def next_frame
        @frame += 1
        down = Hash.new(false)
        HOLDS.each { |scancode, first, last| down[scancode] ||= @frame.between?(first, last) }
        down.each { |scancode, value| LotaNativeTest.hold(scancode, value) }
      end

      # Pushes the key events due at the start of the next frame, and
      # writes each key's state with its event, as the Lua side does.
      def press_keys
        PRESSES.each do |scancode, first, last|
          press_key(scancode, true) if first == @frame + 1
          press_key(scancode, false) if last + 1 == @frame + 1
        end
      end

      private def press_key(scancode, down)
        LotaNativeTest.hold(scancode, down)
        LotaNativeTest.press_key(scancode, down)
      end

      # Holds the pointer where the latest move by frame number +frame+
      # put it, unless the script moves it not at all.
      def hold_pointer(frame)
        _, x, y = MOVES.select { |move, _, _| move <= frame }.last
        Lota::Mouse.position = x, y if x && y
      end

      # Holds the pointer, and queues the clicks, for the next frame, as
      # the Lua side does.
      def use_mouse
        following = @frame + 1
        hold_pointer(following)
        CLICKS.each do |button, first, last|
          LotaNativeTest.click_mouse(button, true) if first == following
          LotaNativeTest.click_mouse(button, false) if last + 1 == following
        end
      end

      # Whether the probe should quit after frame +number+.
      def last_frame?(number)
        number == FRAMES && !GAME_QUITS
      end

      # The arguments +method+ declares, of +arguments+, as Lota passes a
      # callback's (ADR 003, section 3).
      def declared(method, arguments)
        parameters = method.parameters
        return arguments if parameters.any? { |type, _| type == :rest }

        arguments.first(parameters.count { |type, _| type == :req || type == :opt })
      end

      # Compares frame +number+, shown by Lota as +native+, a
      # Lota::Native::ImageData, with the frame LÖVE showed, until one
      # differs.
      def compare(number, native)
        return if @mismatch

        actual = Lota::Image::ImageData.from_native(native)
        message = mismatch_with_love(number, actual)
        @compared += 1
        return unless message

        @mismatch = { "frame" => number, "message" => message }
        File.binwrite(File.join(File.dirname(REPORT), format("lota-%04d.rgba", number)),
          LotaNativeTest.image_data_bytes(native))
      end

      # Decodes each sound file LOTA_PARITY_SOUNDS lists into
      # LOTA_PARITY_SOUNDS_DIR, as the Lua side's decode_sounds does: for
      # the Nth, N.sounddata, what SoundData.new makes of it, and
      # N.decoder, what Decoder.new decodes from it, piece by piece, each
      # a line of its format and then its samples' bytes, each Decoder
      # piece after a line with its size. Lua's string.format and Ruby's
      # format both write the duration's double with C's %.17g.
      def decode_sounds
        dir = ENV.fetch("LOTA_PARITY_SOUNDS_DIR", nil) or return

        ENV.fetch("LOTA_PARITY_SOUNDS", "").split(",").each.with_index(1) do |path, number|
          contents = File.binread(path)
          sound_data = Lota::Sound::SoundData.new(Lota::Filesystem::FileData.new(contents, File.basename(path)))
          File.binwrite(File.join(dir, "#{number}.sounddata"),
            format("%d %d %d %d %.17g %d\n", sound_data.sample_rate, sound_data.bit_depth, sound_data.channel_count,
              sound_data.sample_count, sound_data.duration, sound_data.size) + sound_data.string.b)
          decoder = Lota::Sound::Decoder.new(Lota::Filesystem::FileData.new(contents, File.basename(path)))
          File.open(File.join(dir, "#{number}.decoder"), "wb") do |out|
            out.write(format("%d %d %d %.17g\n", decoder.sample_rate, decoder.bit_depth, decoder.channel_count,
              decoder.duration))
            while (piece = decoder.decode)
              bytes = piece.string.b
              out.write("#{bytes.bytesize}\n", bytes)
            end
          end
        end
      end

      # Writes the report.
      def report
        File.write(REPORT, JSON.generate("compared" => @compared, "mismatch" => @mismatch))
      end

      private def mismatch_with_love(number, actual)
        path = File.join(FRAMES_DIR, format("%04d.png", number))
        return "LÖVE showed no frame #{number}" unless File.exist?(path)

        expected = Lota::Image::ImageData.new(Lota::Filesystem::FileData.new(File.binread(path), File.basename(path)))
        FrameComparison.new(expected, actual, "frame #{number}").message
      end
    end

    # The game's update and draw, wrapped. Lota calls each with the
    # arguments it declares, and each calls the game's with the arguments
    # the game's declares.
    module Callbacks
      def load(*arguments)
        Probe.decode_sounds
        Lota::Math.random_seed = CLOCK if Lota.math
        Probe.hold_pointer(1) if Lota.mouse
        game = method(:load).super_method
        super(*Probe.declared(game, arguments)) if game
      end

      def update(_dt)
        Probe.next_frame
        if Probe.frame > FRAMES
          puts("The game did not quit after frame #{FRAMES}.")
          return Lota::Event.quit(1)
        end

        game = method(:update).super_method
        super(*Probe.declared(game, [DT])) if game
        LotaNativeTest.render_loopback(LOOPBACK_FILE, DT) if Lota.audio
        Probe.press_keys
        Probe.use_mouse
      end

      def draw
        super if method(:draw).super_method
        number = Probe.frame
        return if number > FRAMES

        Lota::Native::Graphics.capture_screenshot(lambda do |native|
          Probe.compare(number, native)
          Lota::Event.quit if Probe.last_frame?(number)
        end)
      end
    end
  end
end

module Parity
  module Probe
    # Lota::Timer.delta, fixed at DT, the dt the game's update gets.
    module Delta
      def delta
        DT
      end
    end

    # Time.now, fixed at CLOCK when called with no arguments.
    module Clock
      def now(*arguments, **options)
        (arguments.empty? && options.empty?) ? at(CLOCK) : super
      end
    end
  end
end

# Return goes to every dialog the game shows, such as LÖVE's version
# warning, as the Lua side presses it.
LotaNativeTest.press_return_on_dialogs
Time.singleton_class.prepend(Parity::Probe::Clock)
Lota::Timer.singleton_class.prepend(Parity::Probe::Delta)
Lota.singleton_class.prepend(Parity::Probe::Callbacks)
at_exit { Parity::Probe.report }
