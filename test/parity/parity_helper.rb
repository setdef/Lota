# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../native/native_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# The parity harness (Plan 001, "What correct means"): a LÖVE game,
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

  # How long either engine may take to run a game before it is stopped and
  # the run fails: a dialog waiting for a click would wait for good. On
  # Linux both draw through Mesa's software renderer, on CI's virtual
  # display, which takes several times as long over the 2,520 frames of
  # Gravity-Wars, each read back and saved.
  TIMEOUT = TestHome::LINUX ? 600 : 120

  # What a run of one engine printed, and how it ended.
  Output = Data.define(:text, :status)

  # The build tree the harness's own libraries are in.
  LIB = File.join(ROOT, "tmp/engine/build/lib")

  # The parity harness's audio device (ext/lota/native_test/loopback.cpp),
  # which every run, LÖVE's and Lota's, loads before anything else
  # (NativeHelper.preload): it gives LÖVE's audio module an OpenAL Soft
  # loopback device in place of the wave file writer test/alsoft.conf
  # names, which each side of the harness mixes once a frame, for the
  # frame's fixed dt, into the run's LOTA_LOOPBACK_FILE. Both engines are
  # started directly, never through a shell, which macOS protects and would
  # drop DYLD_INSERT_LIBRARIES from. On Linux each run also loads the
  # library that answers dialogs (NativeHelper.dialogs).
  LOOPBACK = File.join(LIB, "liblota_loopback.#{TestHome::LINUX ? 'so' : 'dylib'}")

  # The sample rate and channels the loopback device mixes at, and the
  # bytes of one sample frame: 32-bit float stereo at 48 kHz.
  LOOPBACK_RATE = 48_000
  LOOPBACK_FRAME_BYTES = 2 * 4

  # The environment that loads the loopback device and names the file it
  # writes, +audio+.
  def self.loopback(audio)
    { **NativeHelper.preload(LOOPBACK, *NativeHelper.dialogs(LIB)), "LOTA_LOOPBACK_FILE" => audio }
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
    # in +directory+. LÖVE's home directory is +directory+/home
    # (test/test_home.rb), so a game that saves starts each run with
    # nothing saved and leaves nothing behind.
    def initialize(game, script, directory)
      @frames_dir = File.join(directory, "love")
      Dir.mkdir(@frames_dir)
      love = ENV.fetch("LOTA_REFERENCE_LOVE") do
        raise "LOTA_REFERENCE_LOVE is not set; bundle exec rake test:parity builds the reference love and sets it"
      end
      @home = File.join(directory, "home")
      Dir.mkdir(@home)
      @audio = File.join(directory, "love.f32")
      @sounds_dir = File.join(directory, "love-sounds")
      Dir.mkdir(@sounds_dir)
      environment = script.environment.merge("LOTA_PARITY_GAME" => game, "LOTA_PARITY_FRAMES_DIR" => @frames_dir,
        **TestHome.environment(@home), "LOTA_PARITY_SOUNDS_DIR" => @sounds_dir, **Parity.loopback(@audio), **MEMORY)
      @output = Parity.run(environment, love, File.join(ROOT, "test/parity/lua"))
    end

    # The frames LÖVE showed, as PNG files, in order.
    def frames
      Dir[File.join(@frames_dir, "*.png")]
    end
  end

  # Where each run that differs from LÖVE's keeps the first frame that
  # differs, as both engines showed it, so a failure on CI, which uploads
  # this folder, can be seen.
  MISMATCHES = File.join(ROOT, "tmp/parity-mismatches")

  # A translated game run in Lota, each frame compared with a LoveRun's.
  class LotaRun
    attr_reader :output, :report, :home, :audio, :sounds_dir, :mismatch_dir

    # Runs the game in the folder +game+ under +script+ with
    # test/parity/probe.rb, comparing its frames with +love+'s, and keeps
    # its report in +directory+. Lota's home directory is a new folder in
    # +directory+, as LÖVE's is, so a game that saves starts each run with
    # nothing saved and leaves nothing behind. The first frame that differs
    # goes to a folder of the run's own in MISMATCHES, as LÖVE's and Lota's
    # PNG files.
    def initialize(game, script, love, directory)
      report = File.join(directory, "lota-#{File.basename(game)}-#{object_id}.json")
      @mismatch_dir = File.join(MISMATCHES, "#{File.basename(game)}-#{Process.pid}-#{object_id}")
      @home = File.join(directory, "lota-home-#{object_id}")
      Dir.mkdir(@home)
      @audio = File.join(directory, "lota-#{File.basename(game)}-#{object_id}.f32")
      @sounds_dir = File.join(directory, "lota-sounds-#{object_id}")
      Dir.mkdir(@sounds_dir)
      environment = script.environment.merge("LOTA_PARITY_FRAMES_DIR" => love.frames_dir,
        "LOTA_PARITY_REPORT" => report, **TestHome.environment(@home), "LOTA_PARITY_SOUNDS_DIR" => @sounds_dir,
        "LOTA_PARITY_MISMATCH_DIR" => @mismatch_dir, **Parity.loopback(@audio), **MEMORY)
      native_test = LIB
      @output = Parity.run(environment, RbConfig.ruby, "-w", "-I#{File.join(ROOT, 'lib')}", "-I#{native_test}",
        "-r#{File.join(ROOT, 'test/parity/probe.rb')}", File.join(ROOT, "exe/lota"), "run", game)
      @report = File.exist?(report) ? JSON.parse(File.read(report)) : {}
    end

    # How many frames were compared.
    def compared
      @report.fetch("compared", 0)
    end

    # The first frame that differed, and how, or +nil+.
    def mismatch
      @report["mismatch"]
    end
  end

  # Runs +command+ with +environment+ added to this process's, and returns
  # its Output, its standard output and error interleaved. A command still
  # running after TIMEOUT seconds is killed.
  def self.run(environment, *command)
    Open3.popen2e(environment, *command) do |stdin, output, wait|
      stdin.close
      reader = Thread.new { output.read }
      unless wait.join(TIMEOUT)
        Process.kill(:KILL, wait.pid)
        wait.join
      end
      Output.new(reader.value, wait.value)
    end
  end
end
