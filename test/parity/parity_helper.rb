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
  # the run fails: a dialog waiting for a click would wait for good.
  TIMEOUT = 120

  # What a run of one engine printed, and how it ended.
  Output = Data.define(:text, :status)

  # A script both engines run the same game under: how many frames, the
  # fixed dt as frames a second, and the keys held, each as an SDL scancode
  # and the first and last frames, counting from 1, it is held in.
  class Script < Data.define(:frames, :fps, :holds)
    # The environment both sides read the script from.
    def environment
      {
        "LOTA_PARITY_FRAMES" => frames.to_s,
        "LOTA_PARITY_FPS" => fps.to_s,
        "LOTA_PARITY_HOLD" => holds.map { |scancode, frames| "#{scancode}:#{frames.first}-#{frames.last}" }.join(","),
      }
    end
  end

  # A game run in the reference love, whose frames a run in Lota is
  # compared with.
  class LoveRun
    attr_reader :frames_dir, :output

    # Runs the game in the folder +game+ under +script+, keeping its frames
    # in +directory+.
    def initialize(game, script, directory)
      @frames_dir = File.join(directory, "love")
      Dir.mkdir(@frames_dir)
      love = ENV.fetch("LOTA_REFERENCE_LOVE") do
        raise "LOTA_REFERENCE_LOVE is not set; bundle exec rake test:parity builds the reference love and sets it"
      end
      environment = script.environment.merge("LOTA_PARITY_GAME" => game, "LOTA_PARITY_FRAMES_DIR" => @frames_dir)
      @output = Parity.run(environment, love, File.join(ROOT, "test/parity/lua"))
    end

    # The frames LÖVE showed, as PNG files, in order.
    def frames
      Dir[File.join(@frames_dir, "*.png")]
    end
  end

  # A translated game run in Lota, each frame compared with a LoveRun's.
  class LotaRun
    attr_reader :output, :report

    # Runs the game in the folder +game+ under +script+ with
    # test/parity/probe.rb, comparing its frames with +love+'s, and keeps
    # its report in +directory+.
    def initialize(game, script, love, directory)
      report = File.join(directory, "lota-#{File.basename(game)}-#{object_id}.json")
      environment = script.environment.merge("LOTA_PARITY_FRAMES_DIR" => love.frames_dir,
        "LOTA_PARITY_REPORT" => report)
      native_test = File.join(ROOT, "tmp/engine/build/lib")
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
