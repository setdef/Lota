# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"
require "fileutils"
require_relative "frame_comparison"
require_relative "png"

module Parity
  # The parity harness's Ruby side, which test/parity/lua/conf.lua mirrors
  # for LÖVE: measurement code, loaded into <tt>lota run</tt> with
  # <tt>ruby -r</tt> before the game. It runs a translated game unchanged,
  # with the same fixed dt and scripted keys as the Lua side, and compares
  # every frame the game shows with the one LÖVE showed.
  #
  # It prepends Callbacks to Lota's singleton class, so the game's own
  # <tt>def Lota.update</tt> and <tt>def Lota.draw</tt> run inside the
  # harness's, as a game-state library wraps callbacks
  # (doc/contributors/design/game.md).
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
  # the first that differed, and how (mismatch_with_love), which it also
  # saves in LOTA_PARITY_MISMATCH_DIR, as LÖVE showed it, love-NNNN.png,
  # and as Lota showed it, lota-NNNN.png.
  #
  # Deprecation notices are printed until the game's load returns, and
  # then turned off, as the Lua side turns off LÖVE's, which LÖVE would
  # also draw over its frames for 20 seconds of the real clock, as Lota
  # does.
  #
  # Every dialog the game shows, such as LÖVE's version warning, which
  # boot.lua shows before the window opens, has Return pressed on it, as
  # the Lua side does (LotaNativeTest.press_return_on_dialogs), so both
  # engines show it and neither waits for a player.
  #
  # Time.now, called with no arguments, returns LOTA_PARITY_CLOCK seconds
  # after the epoch, as the Lua side's os.time() does, so a game that
  # seeds Lota::Math's generator from the clock draws the same numbers
  # LÖVE's does, and the probe seeds the generator with it as Lota::Boot
  # loads the game's main.rb (SeedBeforeMain) and again before the game's
  # load, as the Lua side seeds LÖVE's, for a game that draws numbers
  # without seeding them.
  #
  # The mouse moves and clicks as the Lua side moves and clicks it: the
  # pointer is held at the latest of LOTA_PARITY_MOVE's moves, from the
  # first, in frame 1, which Lota.load puts it at, then after the game's
  # update of the frame before each, with Lota::Mouse.position=, which
  # updates SDL's mouse state and queues mousemoved, and
  # LOTA_PARITY_CLICK's clicks are pushed after it with
  # LotaNativeTest.click_mouse, at the pointer's position. Lota::Timer.delta returns DT, the dt
  # the game's update gets, as love.timer.getDelta does on the Lua side,
  # and Lota::Timer.time the game's time, the frame under way times DT, as
  # love.timer.getTime does there. Each Lota::Thread::Thread the game
  # starts runs to its end before start returns, as each of LÖVE's
  # threads does on the Lua side.
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
    MISMATCH_DIR = ENV.fetch("LOTA_PARITY_MISMATCH_DIR")
    # The file the number of the last frame shown goes to, for the harness
    # to tell a slow run from a stuck one (Parity.run). LÖVE's run needs no
    # such file: the frames it saves are its progress.
    PROGRESS = ENV.fetch("LOTA_PARITY_PROGRESS")
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
    @threads = 0

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
      # callback's (doc/contributors/design/game.md).
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

        actual = Lota::Image::ImageData.__send__(:from_native, native)
        @mismatch = mismatch_with_love(number, actual)
        @compared += 1
        keep_mismatch(number, actual) if @mismatch
      end

      # Saves frame +number+ as LÖVE showed it, if it did, and as Lota
      # showed it, +actual+, in MISMATCH_DIR.
      private def keep_mismatch(number, actual)
        FileUtils.mkdir_p(MISMATCH_DIR)
        love = love_frame(number)
        FileUtils.cp(love, File.join(MISMATCH_DIR, format("love-%04d.png", number))) if File.exist?(love)
        PNG.write(File.join(MISMATCH_DIR, format("lota-%04d.png", number)), actual.width, actual.height,
          LotaNativeTest.image_data_bytes(actual.__send__(:native)))
      end

      private def love_frame(number)
        File.join(FRAMES_DIR, format("%04d.png", number))
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
          sound_data = Lota::Sound::SoundData.new(Lota::Filesystem.new_file_data(contents, File.basename(path)).first)
          File.binwrite(File.join(dir, "#{number}.sounddata"),
            format("%d %d %d %d %.17g %d\n", sound_data.sample_rate, sound_data.bit_depth, sound_data.channel_count,
              sound_data.sample_count, sound_data.duration, sound_data.size) + sound_data.string.b)
          decoder = Lota::Sound::Decoder.new(Lota::Filesystem.new_file_data(contents, File.basename(path)).first)
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

      # Counts a Lota::Thread::Thread the game started.
      def thread_started
        @threads += 1
      end

      # Writes the report: the frames compared, the first that differed,
      # and how many Lota::Thread::Threads the game started.
      def report
        File.write(REPORT, JSON.generate("compared" => @compared, "mismatch" => @mismatch, "threads" => @threads))
      end

      # How frame +number+, shown by Lota as +actual+, differs from the one
      # LÖVE showed, as the report has it, or +nil+ when they match: the
      # frame, compareImg's message, which names Lota's pixel, and the
      # difference, which names LÖVE's, counts the pixels that differ, and
      # says how each engine's frame is coloured
      # (FrameComparison#difference).
      private def mismatch_with_love(number, actual)
        path = love_frame(number)
        return { "frame" => number, "message" => "LÖVE showed no frame #{number}" } unless File.exist?(path)

        expected = Lota::Image::ImageData.new(Lota::Filesystem.new_file_data(File.binread(path), File.basename(path)).first)
        comparison = FrameComparison.new(expected, actual, "frame #{number}")
        return if comparison.match?

        difference = comparison.difference(["LÖVE's frame", "Lota's frame"])
        { "frame" => number, "message" => comparison.message, "difference" => difference }
      end
    end

    # The game's update and draw, wrapped. Lota calls each with the
    # arguments it declares, and each calls the game's with the arguments
    # the game's declares.
    module Callbacks
      def load(*arguments)
        NativeCalls.install if NativeCalls.on?
        Probe.decode_sounds
        Lota::Math.random_seed = CLOCK if Lota.math
        Probe.hold_pointer(1) if Lota.mouse
        game = method(:load).super_method
        super(*Probe.declared(game, arguments)) if game
        Lota::Deprecation.output = false
      end

      def update(_dt)
        Probe.next_frame
        if Probe.frame > FRAMES
          puts("The game did not quit after frame #{FRAMES}.")
          return Lota::Event.quit(1)
        end

        Timing.start_frame if TIMES
        game = method(:update).super_method
        Timing.time(:update) { super(*Probe.declared(game, [DT])) if game }
        LotaNativeTest.render_loopback(LOOPBACK_FILE, DT) if Lota.audio
        Probe.press_keys
        Probe.use_mouse
      end

      def draw
        Timing.time(:draw) { super if method(:draw).super_method }
        number = Probe.frame
        return if number > FRAMES
        return Timing.finish(number) if TIMES

        Lota::Native::Graphics.capture_screenshot(lambda do |native|
          Probe.compare(number, native)
          File.write(PROGRESS, number.to_s)
          Lota::Event.quit if Probe.last_frame?(number)
        end)
      end
    end
  end
end

module Parity
  module Probe
    # Lota::Timer.delta, fixed at DT, the dt the game's update gets, and
    # Lota::Timer.time, the game's time: the frame under way, 0 in
    # Lota.load, times DT, as the Lua side fixes love.timer.getTime.
    module Delta
      def delta
        DT
      end

      def time
        Probe.frame * DT
      end
    end

    # Seeds Lota::Math's generator with CLOCK as Lota::Boot loads the
    # game's main.rb, as the Lua side seeds LÖVE's before main.lua, for a
    # game that draws numbers as its files load.
    module SeedBeforeMain
      private def require(path)
        Lota::Math.random_seed = CLOCK if path.end_with?("/main.rb") && Lota.math
        super
      end
    end

    # Each Lota::Thread::Thread the game starts runs to its end before
    # start returns, as the Lua side makes each of LÖVE's threads run
    # (wait_for_threads), and the report counts them.
    module Threads
      def start(...)
        started = super
        wait
        Probe.thread_started
        started
      end
    end

    # Time.now, fixed at CLOCK when called with no arguments.
    module Clock
      def now(*arguments, **options)
        (arguments.empty? && options.empty?) ? at(CLOCK) : super
      end
    end

    # The file the timing mode writes to, or +nil+ outside it (Timing).
    TIMES = ENV.fetch("LOTA_PARITY_TIMES", nil)

    # The harness's timing mode, which rake bench runs a translated game
    # in (tasks/bench.rb), as test/parity/lua/conf.lua runs LÖVE's. With
    # LOTA_PARITY_TIMES naming a file, Lota.draw takes no screenshot and
    # compares no frame, and the probe times each frame by the real clock
    # instead: the game's update and draw, each alone, and the whole frame,
    # from the start of one update to the start of the next, which takes in
    # the events, clearing, presenting, and the loop's sleep. It counts the
    # collector's work in each whole frame too, and each major collection's
    # cause, as Bench::Recorder does in rake bench's own game. After the
    # last frame it writes them to that file as JSON, with the JIT that
    # ran, and quits.
    module Timing
      # Monotonic seconds, as a Float.
      MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      # The GC.stat counts kept for the frames as a whole.
      GC_KEYS = %i[count minor_gc_count major_gc_count total_allocated_objects].freeze

      @times = { update: [], draw: [], frame: [] }
      @frame_gc_ns = []
      @frame_gc_count = []
      @major_causes = Hash.new(0)
      @started = nil

      # How often, in frames, the timing mode writes the last frame done to
      # PROGRESS, which rake bench reads when it stops a run that ran too
      # long; every frame would add the write to the frames it times.
      PROGRESS_EVERY = 30

      class << self
        # Turns the timing mode's diagnostics on: what the game prints goes
        # out at once, so a run killed for running too long loses none of
        # it, and SIGUSR1, which rake bench sends such a run before it kills
        # it, prints the frame under way and every thread's backtrace.
        def diagnose
          $stdout.sync = true
          $stderr.sync = true
          Signal.trap(:USR1) do
            warn "Parity probe: stopped in frame #{Probe.frame}; its threads:"
            ::Thread.list.each { |thread| warn "#{thread.inspect}\n  #{Array(thread.backtrace).join("\n  ")}" }
          end
        end

        # Runs the block, and in timing mode adds the seconds it took to
        # the times of +part+, :update or :draw.
        def time(part)
          return yield unless TIMES

          start = MONOTONIC.call
          NativeCalls.counting { yield }
        ensure
          @times.fetch(part) << (MONOTONIC.call - start) if TIMES && start
        end

        # Ends the frame before, if there was one, and starts the next.
        def start_frame
          now = MONOTONIC.call
          if @started
            @times.fetch(:frame) << (now - @started)
            @frame_gc_ns << (LotaNativeTest.gc_wall_time - @gc_time)
            @frame_gc_count << (GC.count - @gc_count)
            note_majors
          end
          NativeCalls.next_frame if NativeCalls.on?
          done = Probe.frame - 1
          File.write(PROGRESS, done.to_s) if (done % PROGRESS_EVERY).zero?
          @first ||= gc_snapshot
          @majors ||= GC.stat(:major_gc_count)
          @started = now
          @gc_time = LotaNativeTest.gc_wall_time
          @gc_count = GC.count
        end

        # After frame +number+'s draw: writes the times once it is the
        # last frame, and quits, unless the script leaves quitting to the
        # game.
        def finish(number)
          return unless number == FRAMES

          write
          Lota::Event.quit unless GAME_QUITS
        end

        private def write
          note_majors
          last = gc_snapshot
          File.write(TIMES, JSON.generate(
            "engine" => "lota", "jit" => jit, "ruby" => RUBY_DESCRIPTION,
            **@times.transform_keys(&:to_s),
            "frame_gc_ns" => @frame_gc_ns, "frame_gc_count" => @frame_gc_count,
            "gc" => last.to_h { |key, value| [key.to_s, value - @first.fetch(key)] },
            "gc_major_by" => @major_causes,
            **NativeCalls.to_h,
          ))
        end

        private def gc_snapshot
          GC.stat.slice(*GC_KEYS).merge(time_ns: LotaNativeTest.gc_wall_time)
        end

        # Counts the major collections since the last look by their cause,
        # as Bench::Recorder#note_majors does.
        private def note_majors
          majors = GC.stat(:major_gc_count)
          return if majors == @majors

          cause = GC.latest_gc_info(:major_by)
          @major_causes[cause.to_s] += 1 if cause
          unseen = majors - @majors - (cause ? 1 : 0)
          @major_causes["unseen"] += unseen if unseen.positive?
          @majors = majors
        end

        private def jit
          if defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled? then "zjit"
          elsif defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? then "yjit"
          else "interpreter"
          end
        end
      end
    end

    # In the timing mode, with LOTA_PARITY_NATIVE_TIMES=1 as well, how
    # long the game's update and draw spend in Lota's extension each frame,
    # so the rest of their time is Ruby's: the game's own code and Lota's
    # Ruby. Every method of Lota::Native's modules and classes that the
    # extension defines in C++ is wrapped, as the game loads, and each call
    # the game's update or draw makes into it is timed, less what the
    # wrapper itself adds to that time (#calibrate). A call the extension
    # makes back into Ruby is counted as the extension's. The wrappers add
    # time of their own outside what they time, so a run with them is
    # slower than one without, and rake bench takes the frame's other times
    # from a run without them.
    module NativeCalls
      @counting = false
      @seconds = 0.0
      @calls = 0
      @frame_seconds = []
      @frame_calls = []
      @started = false
      @overhead = 0.0

      class << self
        # Whether the native calls are timed.
        def on?
          TIMES && ENV.fetch("LOTA_PARITY_NATIVE_TIMES", nil) == "1"
        end

        # Runs the block, timing the native calls it makes while on.
        def counting
          return yield unless on?

          @counting = true
          yield
        ensure
          @counting = false
        end

        # Wraps each of the extension's methods, once Lota::Native is loaded.
        def install
          calibrate
          modules(Lota::Native).each do |mod|
            wrap(mod.singleton_class)
            wrap(mod) if mod.is_a?(Class)
          end
        end

        # Adds +seconds+ of one call, from a wrapper, to the frame's.
        def add(seconds)
          @seconds += seconds
          @calls += 1
        end

        # Whether a wrapper should time its call: inside the game's update
        # or draw, and not inside another timed call.
        def timing?
          @counting && !@inside
        end

        # Ends a frame's count, if one was under way, and starts the next.
        def next_frame
          close_frame if @started
          @started = true
        end

        # What the timing mode's report adds: each frame's seconds in native
        # calls, the wrapper's own time taken out, and its calls.
        def to_h
          return {} unless on?

          close_frame if @started
          { "native" => @frame_seconds, "native_calls" => @frame_calls, "native_overhead" => @overhead }
        end

        private def close_frame
          @frame_seconds << [@seconds - (@calls * @overhead), 0.0].max
          @frame_calls << @calls
          @seconds = 0.0
          @calls = 0
        end

        # Lota::Native and every module and class inside it.
        private def modules(root, seen = {})
          return [] if seen[root]

          seen[root] = true
          nested = root.constants(false).filter_map { |name| root.const_get(name, false) }.grep(Module)
          [root, *nested.flat_map { |mod| modules(mod, seen) }]
        end

        # Prepends to +target+ a wrapper for each method +target+ itself
        # defines that has no Ruby source, or for +names+ when given.
        #
        # Each wrapper is a method written with def, not define_method,
        # and times nothing outside the main Ractor: the game's threads
        # are Ractors of their own (Lota::Thread), which call the
        # extension too, and Ruby refuses another Ractor a method whose
        # body is a Proc it cannot share, and any of this module's state.
        # A thread that met that refusal would die, and a game that waits
        # for what it makes, as FLASH-BLIP waits for its music, would
        # wait for good.
        private def wrap(target, names = nil)
          names ||= (target.instance_methods(false) + target.private_instance_methods(false))
            .select { |name| target.instance_method(name).source_location.nil? }
          names = names.select { |name| name.match?(WRAPPABLE) }
          return if names.empty?

          private_names = names & target.private_instance_methods(false)
          wrapper = Module.new
          names.each do |name|
            wrapper.module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
              def #{name}(...)
                return super unless Ractor.main? && Parity::Probe::NativeCalls.timing?

                Parity::Probe::NativeCalls.time { super }
              end
            RUBY
          end
          wrapper.__send__(:private, *private_names) unless private_names.empty?
          target.prepend(wrapper)
        end

        # The names a method written with def can take, an operator's
        # among them; the extension's methods have no others.
        WRAPPABLE = %r{\A(?:[A-Za-z_]\w*[?!=]?|\[\]=?|[-+*/%<>]|<=|>=|==|<=>|!=)\z}

        # Times one call into the extension, the block, as a wrapper
        # makes it.
        def time
          @inside = true
          start = Timing::MONOTONIC.call
          begin
            yield
          ensure
            add(Timing::MONOTONIC.call - start)
            @inside = false
          end
        end

        # The time a wrapper adds to what it times, per call: a Ruby method
        # that does nothing, wrapped and called while counting, reports
        # only the wrapper's own time.
        private def calibrate
          probe = Module.new { def self.nothing = nil }
          wrap(probe.singleton_class, [:nothing])
          @counting = true
          3.times do
            @seconds = 0.0
            @calls = 0
            100_000.times { probe.nothing }
          end
          @overhead = @seconds / @calls
        ensure
          @counting = false
          @seconds = 0.0
          @calls = 0
        end
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
Lota::Boot.prepend(Parity::Probe::SeedBeforeMain)
Lota::Thread::Thread.prepend(Parity::Probe::Threads)
Parity::Probe::Timing.diagnose if Parity::Probe::TIMES
at_exit { Parity::Probe.report }
