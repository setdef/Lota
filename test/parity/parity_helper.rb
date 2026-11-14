# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../native/native_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "desktop_input_lock"
require_relative "reference_cache"

# The parity harness: a LÖVE game,
# unchanged, in the reference love built from vendor/love, and its Ruby
# translation in Lota, each with the same fixed dt and the same scripted
# keys, compared frame by frame. test/parity/lua/conf.lua and
# test/parity/probe.rb are its two sides; this runs them.
module Parity
  ROOT = File.expand_path("../..", __dir__)

  # The arkanoid tutorial's snapshots (test/fixtures), and their Ruby
  # translations (test/games/arkanoid).
  ARKANOID = File.join(ROOT, "test/fixtures/love2d_arkanoid_tutorial")
  ARKANOID_TRANSLATED = File.join(ROOT, "test/games/arkanoid")

  # How long either engine may go without showing a new frame before the
  # run is taken to be stuck, stopped, and failed: a dialog waiting for a
  # click, or a hang, would wait for good. A run is never stopped for being
  # slow, only for standing still, so a loaded machine, or Mesa's software
  # renderer on CI's virtual display, makes a run longer but never fails
  # it. The longest wait between two frames of a healthy run is before the
  # first, while the engine starts, opens its window, and loads the game,
  # which takes a few seconds on an idle machine; a minute leaves room for
  # that start to run many times slower, on a machine loaded several
  # hundred processes deep, and still stops a stuck run within one. No cap
  # on the whole run is needed: both sides quit after the script's last
  # frame, so a run that keeps showing frames ends.
  STALL = 60

  # What a run of one engine printed, and how it ended: +text+, what the
  # engine and the game printed, and +diagnostics+, the lines the Metal
  # watch (METAL_WATCH) printed among them, which are the harness's, not
  # the engine's, so no comparison of what the two engines printed sees
  # them.
  class Output < Data.define(:text, :status, :diagnostics)
    def initialize(text:, status:, diagnostics: "")
      super
    end

    # Whether the Metal watch saw a command buffer end other than
    # completed: the GPU did not draw every frame the engine showed.
    def gpu_failed?
      diagnostics.include?(" ended with status ")
    end
  end

  # A line the Metal watch prints (ext/lota/native_test/metal_watch.mm).
  # It writes each line whole, in one write of fewer bytes than a pipe
  # writes at once, so a line of its own is never split, though it may
  # land inside a line the engine had begun.
  DIAGNOSTIC = /lota-metal-watch: [^\n]*\n/

  # The Output of a run that printed +printed+, its standard output and
  # error interleaved, and ended with +status+: the Metal watch's lines
  # taken out of what the engine printed and kept apart.
  def self.output(printed, status)
    Output.new(printed.gsub(DIAGNOSTIC, ""), status, printed.scan(DIAGNOSTIC).join)
  end

  # How many of the last lines each engine printed a failure shows
  # (Parity.mismatch_message).
  TAIL = 40

  # What a test that found the frame +mismatch+ differ says: the frame,
  # then the last TAIL lines each engine printed, +love+'s and +lota+'s
  # Output, and what the Metal watch reported in each, so that what an
  # engine printed about a frame it could not draw, a GPU's error among
  # it, is not lost with the run.
  def self.mismatch_message(mismatch, love, lota)
    sides = { "The reference love" => love, "Lota" => lota }.map do |side, output|
      lines = output.text.lines
      heading = (lines.size > TAIL) ? "#{side} printed, last #{TAIL} of #{lines.size} lines:" : "#{side} printed:"
      "#{heading}\n#{block(lines.last(TAIL).join)}#{side}'s Metal watch reported:\n#{block(output.diagnostics)}"
    end
    "first differing frame: #{mismatch}\n#{sides.join}"
  end

  # +text+ as a block of lines in a failure's message: "(nothing)" when
  # empty, and ending in a newline.
  def self.block(text)
    return "(nothing)\n" if text.empty?

    text.end_with?("\n") ? text : "#{text}\n"
  end

  # The build tree the harness's own libraries are in.
  LIB = File.join(ROOT, "tmp/engine/build/lib")

  # The parity harness's audio device (ext/lota/native_test/loopback.cpp),
  # which every run, LÖVE's and Lota's, loads before anything else
  # (Parity.loopback): it gives LÖVE's audio module an OpenAL Soft
  # loopback device in place of the wave file writer test/alsoft.conf
  # names, which each side of the harness mixes once a frame, for the
  # frame's fixed dt, into the run's LOTA_LOOPBACK_FILE. Both engines are
  # started directly, never through a shell, which macOS protects and would
  # drop DYLD_INSERT_LIBRARIES from. On macOS each run also loads the Metal
  # watch (METAL_WATCH), and on Linux the library that answers dialogs
  # (NativeHelper.dialogs).
  LOOPBACK = File.join(LIB, "liblota_loopback.#{TestHome::LINUX ? 'so' : 'dylib'}")

  # On macOS, the parity harness's Metal watch (ext/lota/native_test/
  # metal_watch.mm), which every run also loads: it prints, with the
  # prefix DIAGNOSTIC matches, each Metal command buffer that ended other
  # than completed, with its status and error, and at exit how many there
  # were, so a frame that comes back black says whether the GPU ran it.
  # LÖVE waits for the command buffer that copies a frame for its
  # screenshot and never reads how it ended (graphics/metal/
  # Graphics.mm:1740-1745). Linux draws with OpenGL, and loads none.
  METAL_WATCH = TestHome::LINUX ? [] : [File.join(LIB, "liblota_metal_watch.dylib")]

  # The sample rate and channels the loopback device mixes at, and the
  # bytes of one sample frame: 32-bit float stereo at 48 kHz.
  LOOPBACK_RATE = 48_000
  LOOPBACK_FRAME_BYTES = 2 * 4

  # The harness's library that keeps every run off the network
  # (ext/lota/native_test/offline_linux.cpp and offline.mm), which
  # every run also loads: it refuses each connection to an Internet
  # address at once, as a server that is there and refuses it would, and
  # looks up only a name written as an address. A game that asks a server
  # for something, as FLASH-BLIP asks one on the local network for a newer
  # version at every start, then gets the same answer in both engines,
  # whatever network the machine is on, and nothing leaves either.
  OFFLINE = File.join(LIB, "liblota_offline.#{TestHome::LINUX ? 'so' : 'dylib'}")

  # The environment that loads the loopback device and names the file it
  # writes, +audio+, and loads OFFLINE, the Metal watch, and the library
  # that answers dialogs: the preload is the harness's alone, since a run
  # gets no variable of this process's (Parity.environment).
  def self.loopback(audio)
    libraries = [LOOPBACK, OFFLINE, *METAL_WATCH, *NativeHelper.dialogs(LIB)]
    preload = TestHome::LINUX ? { "LD_PRELOAD" => libraries.join(" ") } : { "DYLD_INSERT_LIBRARIES" => libraries.join(":") }
    { **preload, "LOTA_LOOPBACK_FILE" => audio }
  end

  # What either engine reads of memory it never wrote is the same in both,
  # on Linux. Mesa's software renderer, on CI's Xvfb, gives a window's
  # OpenGL drawable a new size only when it shows a frame, so the first
  # frame after a game's setMode resizes its window, as Gravity-Wars's
  # love.load does, is drawn into a drawable the window's old size.
  # love.graphics.captureScreenshot reads the frame with glReadPixels into
  # a buffer from new[] (graphics/opengl/Graphics.cpp:1250-1280), and
  # glReadPixels writes only the part inside the drawable, so the rest is
  # whatever malloc left there, which differs between two programs, and
  # between two runs of one. glibc fills each block malloc hands out with
  # the complement of MALLOC_PERTURB_'s byte, so that part is 0xFE in both
  # engines, every run. macOS's malloc has no such setting, and LÖVE draws
  # there with Metal, whose frames the harness compares as they are.
  MEMORY = TestHome::LINUX ? { "MALLOC_PERTURB_" => "1" } : {}

  # Mesa's drivers write nothing into a run's home, on Linux. They keep
  # the shaders they compile in caches on disk under the home's .cache
  # (llvmpipe and radeonsi in mesa_shader_cache; RADV, Mesa's Vulkan
  # driver for AMD's GPUs, there and in radv_builtin_shaders), and each
  # run of either engine has a home of its own, so a cache never spares a
  # later run anything. RADV writes its caches' indexes and entries
  # differently from one run of the same game to the next, so the run's
  # folder a ReferenceCache keeps would differ from the one running the
  # reference love again writes. A cache only spares a driver compiling a
  # shader it compiled before; nothing either engine draws depends on it.
  DRIVER = TestHome::LINUX ? { "MESA_SHADER_CACHE_DISABLE" => "true" } : {}

  # The whole environment a run of either engine gets: +variables+, the
  # harness's for the run, and these, the same for both engines, and
  # nothing of this process's. A shell's own variables, which differ from
  # one terminal or session to the next, can then neither change what
  # either engine does nor make a ReferenceCache miss. What both engines
  # need of the computer is here: the system's PATH; the temporary folder;
  # a UTF-8 locale, which sets the encoding Ruby reads and writes text in;
  # OpenAL Soft's settings for the tests (test/alsoft.conf); SDL's hints
  # that keep the windows in the background (test/test_helper.rb); and on
  # Linux, the display to open them on, which must be set, and its
  # authority and runtime folder, if they are, the byte malloc fills
  # memory with (MEMORY), and Mesa's shader cache turned off (DRIVER).
  # Each run's home, for HOME, is in +variables+.
  def self.environment(variables)
    {
      "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin",
      "TMPDIR" => Dir.tmpdir,
      "LANG" => TestHome::LINUX ? "C.UTF-8" : "en_US.UTF-8",
      "ALSOFT_CONF" => File.join(ROOT, "test/alsoft.conf"),
      "SDL_MAC_BACKGROUND_APP" => "1",
      "SDL_WINDOW_ACTIVATE_WHEN_SHOWN" => "0",
      "SDL_WINDOW_ACTIVATE_WHEN_RAISED" => "0",
      **display,
      **MEMORY,
      **DRIVER,
    }.merge(variables)
  end

  # On Linux, the X display the windows open on, and what reaching it
  # needs; nothing elsewhere. Raises when DISPLAY is not set, since no
  # window could open.
  #
  # LOTA_PARITY_DISPLAY names a display of the harness's own, which it
  # opens its windows on instead. A warp of the pointer under X11 reaches
  # SDL only as the motion event the X server sends the window on top
  # where the pointer lands (SDL 3.4.10, src/video/x11/SDL_x11mouse.c,
  # X11_WarpMouseInternal), so on a display the gate's other checks share,
  # a window of theirs that opens over the run's takes the move the script
  # made, and the game never hears of it. CI gives the harness a display
  # of its own (.github/workflows/ci.yml).
  def self.display
    return {} unless TestHome::LINUX

    display = ENV.fetch("LOTA_PARITY_DISPLAY") do
      ENV.fetch("DISPLAY") { raise "DISPLAY is not set; the parity harness opens its windows on an X display" }
    end
    { "DISPLAY" => display, **ENV.slice("XAUTHORITY", "XDG_RUNTIME_DIR") }
  end

  # The seconds since the epoch both engines' clocks stand at, unless a
  # script names its own: 2020-09-13, 12:26:40 UTC.
  CLOCK = 1_600_000_000

  # A script both engines run the same game under: how many frames, the
  # fixed dt as frames a second, the keys held, and the keys pressed, each
  # as an SDL scancode and the first and last frames, counting from 1, it
  # is down in, and the clock, in seconds since the epoch, that a game
  # reading the time reads, so that a game seeding its random numbers from
  # the clock draws the same ones in both. Both engines also seed LÖVE's
  # generator with the clock before the game's load, as LÖVE seeds it from
  # the real time when love.math opens (math/MathModule.cpp:203-210).
  #
  # The mouse moves and clicks as a player's does. A move is the frame it
  # happens at the start of and the position in the window it goes to,
  # which love.mouse.setPosition puts the pointer at, so that
  # love.mouse.getPosition reads it from then on and mousemoved hears of
  # it; the first move is in frame 1, where the pointer starts, and the
  # pointer is held at the latest move's position every frame, as a key is
  # held. A click is a button, numbered as LÖVE numbers it, and the first
  # and last frames it is down in: mousepressed hears of it at the start of
  # its first frame and mousereleased at the start of the frame after its
  # last, at the pointer's position then. Like a key press, a click is set
  # up a frame early, so it cannot start in frame 1, and love.mouse.isDown
  # does not see it.
  #
  # A held key is only down, in the keyboard state Lota::Keyboard.down?
  # reads. A pressed key is down too, and also goes down and comes up as a
  # player's does: the game's keypressed hears of it at the start of its
  # first frame, and its keyreleased at the start of the frame after its
  # last. The harness pushes the key events a frame early, so a press
  # cannot start in frame 1. A press whose last frame is the script's last
  # comes up after it, and then the game must quit on its own, as on
  # Escape; otherwise the harness quits after the last frame.
  #
  # The sounds are sound files, by absolute path, that both engines decode
  # when the game loads, each as LÖVE's SoundData and Decoder decode it,
  # for a test to compare (test/parity/lua/conf.lua, decode_sounds).
  class Script < Data.define(:frames, :fps, :holds, :presses, :clock, :moves, :clicks, :sounds)
    def initialize(frames:, fps:, holds:, presses: [], clock: CLOCK, moves: [], clicks: [], sounds: [])
      if (presses + clicks).any? { |_, range| range.first < 2 || range.last > frames }
        raise ArgumentError, "a press or a click must start in frame 2 or later and end by frame #{frames}"
      end
      if moves.any? && moves.first.first != 1
        raise ArgumentError, "the first move must be in frame 1, where the pointer starts"
      end

      super
    end

    # The environment both sides read the script from.
    def environment
      {
        "LOTA_PARITY_FRAMES" => frames.to_s,
        "LOTA_PARITY_FPS" => fps.to_s,
        "LOTA_PARITY_CLOCK" => clock.to_s,
        "LOTA_PARITY_HOLD" => Parity.keys(holds),
        "LOTA_PARITY_PRESS" => Parity.keys(presses),
        "LOTA_PARITY_MOVE" => moves.map { |frame, x, y| "#{frame}:#{x}:#{y}" }.join(","),
        "LOTA_PARITY_CLICK" => Parity.keys(clicks),
        "LOTA_PARITY_SOUNDS" => sounds.join(","),
      }
    end
  end

  # A new folder in the system's temporary directory for a LoveRun, and
  # every LotaRun compared with it, to keep frames, homes, and sounds in.
  # A test class runs LÖVE once for all its tests, so the folder outlives
  # each test, and Minitest has no hook for the end of a class: it is
  # removed when the test run ends, whether its tests passed or failed.
  # What a run that differs from LÖVE's keeps for CI is in MISMATCHES,
  # not here.
  def self.directory
    directory = Dir.mktmpdir("lota-parity-")
    Minitest.after_run { FileUtils.rm_rf(directory) }
    directory
  end

  # +keys+, each an SDL scancode and a Range of frames, as the two sides
  # read them: scancode:first-last, separated by commas.
  def self.keys(keys)
    keys.map { |scancode, frames| "#{scancode}:#{frames.first}-#{frames.last}" }.join(",")
  end

  # A game run in the reference love, whose frames a run in Lota is
  # compared with.
  class LoveRun
    attr_reader :frames_dir, :output, :home, :audio, :sounds_dir

    # Runs the game in the folder +game+ under +script+, keeping its frames
    # in +directory+, or with +game+ +nil+, LÖVE's no-game screen
    # (vendor/love/src/scripts/nogame.lua), which test/parity/lua/conf.lua
    # starts as boot.lua starts it when it finds no game. LÖVE's home directory is +directory+/home
    # (test/test_home.rb), so a game that saves starts each run with
    # nothing saved and leaves nothing behind. When +cache+ holds a run
    # under the same inputs (ReferenceCache), what that run wrote and
    # printed stands in for running +love+ again.
    def initialize(game, script, directory, love: Parity.reference_love, cache: ReferenceCache.default)
      @frames_dir = File.join(directory, "love")
      Dir.mkdir(@frames_dir)
      @home = File.join(directory, "home")
      Dir.mkdir(@home)
      @audio = File.join(directory, "love.f32")
      @sounds_dir = File.join(directory, "love-sounds")
      Dir.mkdir(@sounds_dir)
      game_variable = game ? { "LOTA_PARITY_GAME" => game } : { "LOTA_PARITY_NOGAME" => "1" }
      environment = Parity.environment(script.environment.merge(**game_variable,
        "LOTA_PARITY_FRAMES_DIR" => @frames_dir, "HOME" => @home, **TestHome.environment(@home),
        "LOTA_PARITY_SOUNDS_DIR" => @sounds_dir, **Parity.loopback(@audio)))
      command = [love, File.join(ROOT, "test/parity/lua")]
      @output, @cached = if cache
        cache.fetch(command, environment, directory) { run(environment, command) }
      else
        [run(environment, command), false]
      end
    end

    # Whether the run's output came from a ReferenceCache, not from
    # running the reference love.
    def cached?
      @cached
    end

    # The frames LÖVE showed, as PNG files, in order.
    def frames
      Dir[File.join(@frames_dir, "*.png")]
    end

    # The GPU of a virtual Mac, as CI's runners are, has hung under the
    # reference love partway through a run, and Metal then ignored what
    # LÖVE sent it: LÖVE showed black frames to the script's end and quit
    # with 0, since it never reads how the command buffer behind a
    # screenshot ended (graphics/metal/Graphics.mm:1740-1745). Such a run
    # is no reference to compare Lota with, so LÖVE runs once more, in an
    # empty run folder. A second failure is kept, and fails the test with
    # the Metal watch's report.
    private def run(environment, command)
      output = run_once(environment, command)
      return output unless output.gpu_failed?

      [@frames_dir, @home, @sounds_dir].each { |dir| FileUtils.rm_rf(Dir.children(dir).map { |child| File.join(dir, child) }) }
      FileUtils.rm_f(@audio)
      run_once(environment, command)
    end

    private def run_once(environment, command)
      shown = 0
      Parity.run(environment, *command, side: "The reference love") do
        shown += 1 while File.exist?(File.join(@frames_dir, format("%04d.png", shown + 1)))
        shown
      end
    end
  end

  # The reference love's executable, which bundle exec rake test:parity
  # builds and names in LOTA_REFERENCE_LOVE.
  def self.reference_love
    ENV.fetch("LOTA_REFERENCE_LOVE") do
      raise "LOTA_REFERENCE_LOVE is not set; bundle exec rake test:parity builds the reference love and sets it"
    end
  end

  # Where each run that differs from LÖVE's keeps the first frame that
  # differs, as both engines showed it, so a failure on CI, which uploads
  # this folder, can be seen.
  MISMATCHES = File.join(ROOT, "tmp/parity-mismatches")

  # What starts Lota with no game, for a LotaRun of its no-game screen
  # (test/parity/no_game.rb).
  NO_GAME = File.join(ROOT, "test/parity/no_game.rb")

  # A translated game run in Lota, each frame compared with a LoveRun's.
  class LotaRun
    attr_reader :output, :report, :home, :audio, :sounds_dir, :mismatch_dir

    # Runs the game in the folder +game+ under +script+ with
    # test/parity/probe.rb, or with +game+ +nil+, Lota's no-game screen
    # (NO_GAME), comparing its frames with +love+'s, and keeps
    # its report in +directory+. Lota's home directory is a new folder in
    # +directory+, as LÖVE's is, so a game that saves starts each run with
    # nothing saved and leaves nothing behind. The first frame that differs
    # goes to a folder of the run's own in MISMATCHES, as LÖVE's and Lota's
    # PNG files.
    def initialize(game, script, love, directory)
      name = game ? File.basename(game) : "no_game"
      report = File.join(directory, "lota-#{name}-#{object_id}.json")
      @mismatch_dir = File.join(MISMATCHES, "#{name}-#{Process.pid}-#{object_id}")
      @home = File.join(directory, "lota-home-#{object_id}")
      Dir.mkdir(@home)
      @audio = File.join(directory, "lota-#{name}-#{object_id}.f32")
      @sounds_dir = File.join(directory, "lota-sounds-#{object_id}")
      Dir.mkdir(@sounds_dir)
      progress = File.join(directory, "lota-progress-#{object_id}")
      environment = Parity.environment(script.environment.merge("LOTA_PARITY_FRAMES_DIR" => love.frames_dir,
        "LOTA_PARITY_REPORT" => report, "HOME" => @home, **TestHome.environment(@home),
        "LOTA_PARITY_SOUNDS_DIR" => @sounds_dir, "LOTA_PARITY_MISMATCH_DIR" => @mismatch_dir,
        "LOTA_PARITY_PROGRESS" => progress, **Parity.loopback(@audio)))
      native_test = LIB
      start = game ? [File.join(ROOT, "exe/lota"), "run", game] : [NO_GAME]
      @output = Parity.run(environment, RbConfig.ruby, "-w", "-I#{File.join(ROOT, 'lib')}", "-I#{native_test}",
        "-r#{File.join(ROOT, 'test/parity/probe.rb')}", *start, side: "Lota") do
        File.exist?(progress) ? File.read(progress).to_i : 0
      end
      @report = File.exist?(report) ? JSON.parse(File.read(report)) : {}
      @love_output = love.output
    end

    # How many frames were compared.
    def compared
      @report.fetch("compared", 0)
    end

    # The first frame that differed, and how, or +nil+.
    def mismatch
      @report["mismatch"]
    end

    # What a test that found a frame differ says: the frame, and what both
    # engines printed (Parity.mismatch_message).
    def mismatch_message
      Parity.mismatch_message(mismatch, @love_output, output)
    end
  end

  # Runs +command+ with +environment+, and with the variables every run
  # gets (Parity.environment), and with nothing else, and returns
  # its Output, its standard output and error interleaved, with the Metal
  # watch's lines kept apart (Parity.output). The block
  # answers the last frame the command has shown, counting from 1, or 0
  # before the first. A command that shows no new frame for +stall+
  # seconds is stuck: it is killed, and its Output ends with a line that
  # says so, naming it as +side+.
  #
  # A run whose script moves or clicks the mouse holds the desktop input
  # lock (the desktop_input_lock gem), +desktop_input+'s, until it ends, since
  # the pointer is the computer's, and the gate's other checks read it and
  # move it too. It holds it silently: its window stays in the background,
  # and takes no focus.
  def self.run(environment, *command, side:, stall: STALL, desktop_input: DesktopInputLock::DEFAULT, &shown)
    if moves_pointer?(environment)
      return desktop_input.hold(speak: false) { run_unlocked(environment, *command, side:, stall:, &shown) }
    end

    run_unlocked(environment, *command, side:, stall:, &shown)
  end

  def self.moves_pointer?(environment)
    !environment.fetch("LOTA_PARITY_MOVE", "").empty? || !environment.fetch("LOTA_PARITY_CLICK", "").empty?
  end

  def self.run_unlocked(environment, *command, side:, stall: STALL, &shown)
    Open3.popen2e(Parity.environment(environment), *command, unsetenv_others: true) do |stdin, output, wait|
      stdin.close
      reader = Thread.new { output.read }
      stuck = Parity.stuck(wait, stall, &shown)
      Process.kill(:KILL, wait.pid) if stuck
      wait.join
      Parity.output(stuck ? reader.value + Parity.stopped(side, stall, stuck) : reader.value, wait.value)
    end
  end

  # The line a run's Output ends with when +side+ showed no frame after
  # +frame+, 0 before its first, for +stall+ seconds and was stopped.
  def self.stopped(side, stall, frame)
    "#{side} showed no new frame for #{stall} seconds, after #{frame.zero? ? 'starting' : "frame #{frame}"}, " \
      "and was stopped.\n"
  end

  # Waits for the process +wait+ waits on to end, and returns +nil+; or,
  # if the block, which answers the last frame it has shown, answers no
  # later frame for +stall+ seconds, returns the last one it did answer.
  def self.stuck(wait, stall)
    last = yield
    since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    until wait.join([stall / 4.0, 1].min)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      frame = yield
      if frame > last
        last = frame
        since = now
      elsif now - since >= stall
        return last
      end
    end
    nil
  end
end
