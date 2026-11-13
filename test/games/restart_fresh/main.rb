# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Restarts as many times as LOTA_RESTARTS says, each run making engine
# objects of most modules, a running thread, a named channel's message, a
# constant, a callback, an instance variable on Lota, a global, and an
# exit proc, and appends to the file LOTA_RESTART_LOG what each run finds
# left of the runs before it, with how many runs the Ruby it runs in has
# seen, which RestartMarker, loaded before the game, counts. The run after
# the last restart quits with status 3.
require "helper"
require_relative "helper"

RESTARTS = Integer(ENV.fetch("LOTA_RESTARTS"))
LOG = ENV.fetch("LOTA_RESTART_LOG")

def log(line)
  File.open(LOG, "a") { |file| file.puts(line) }
end

def Lota.load(_arguments)
  @run = (Lota.restart || 0).to_i + 1
  log("load run=#{@run} pid=#{Process.pid} helper=#{Helper.load_once} global=#{$restart_fresh.inspect} " \
    "keypressed=#{Lota.respond_to?(:keypressed)} color=#{Lota::Graphics.color.inspect} " \
    "channel=#{Lota::Thread.channel('runs').count} window=#{Lota::Window.open?} ruby_runs=#{RestartMarker.count}")
  $restart_fresh = @run
  def Lota.keypressed(_key) = nil
  Lota::Graphics.color = [1, 0, 0, 1]
  Lota::Thread.channel("runs").push(@run)
  make_objects
  start_worker
  @frames = 0
end

def make_objects
  @canvas = Lota::Graphics::Canvas.new(32, 32)
  @image = Lota::Graphics::Image.new(Lota::Image::ImageData.new(16, 16))
  @font = Lota::Graphics::Font.new(12)
  @text = Lota::Graphics::TextBatch.new(@font, "run #{@run}")
  @source = Lota::Audio::Source.new(Lota::Sound::SoundData.new(4410, 44_100, 16, 1))
  @source.play
  @world = Lota::Physics::World.new(0, 9.81)
  3.times { |i| Lota::Physics.new_circle_body(@world, :dynamic, i * 10, 0, 5) }
end

# Starts a thread that runs until the run's exit proc stops it.
def start_worker
  thread = Lota::Thread::Thread.new("worker.rb")
  thread.start
  run = @run
  at_exit do
    Lota::Thread.channel("stop").push(true)
    thread.wait
    log("at_exit run=#{run}")
  end
end

def Lota.update(dt)
  @frames += 1
  @world.update(dt)
  return if @frames < 3

  (@run > RESTARTS) ? Lota::Event.quit(3) : Lota::Event.restart(@run)
end

def Lota.draw
  Lota::Graphics.canvas = @canvas
  Lota::Graphics.clear(0, 0, 1, 1)
  Lota::Graphics.canvas = nil
  Lota::Graphics.draw(@canvas)
  Lota::Graphics.draw(@image, 10, 10)
  Lota::Graphics.draw(@text, 20, 20)
end
