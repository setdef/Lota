# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Draws a background that changes color, a rectangle, a line of text, and
# a square where the last touch landed, so a screenshot shows that the
# engine drew and that a touch arrived; plays a quiet tone; prints what it
# saw, each line starting "phone check:", which the phone's log shows; and
# quits with status 0 after PHONE_CHECK_SECONDS, 20 by default.
module PhoneCheck
  # What a graphics call from another Ruby thread does: LÖVE confines
  # graphics to the main thread, and Lota raises ThreadError there.
  def self.off_main_thread
    Thread.new do
      Lota::Graphics.font
      "no error"
    rescue ThreadError => e
      e.class.name
    end.value
  end

  # A second of a 440 Hz sine, looped, at a fifth of full scale.
  def self.tone
    rate = 22_050
    data = Lota::Sound::SoundData.new(rate, rate, 16, 1)
    data.sample_count.times { |i| data.sample = i, 0.2 * Math.sin(2 * Math::PI * 440 * i / rate.to_f) }
    source = Lota::Audio::Source.new(data, :static)
    source.looping = true
    source.play
    puts "phone check: audio playing #{source.playing?}"
    source
  end
end

def Lota.load
  puts "phone check: loaded on #{Lota::System.os}, renderer #{Lota::Graphics.renderer_info.join(' / ')}"
  puts "phone check: window #{Lota::Graphics.dimensions.join('x')}, pixels " \
    "#{Lota::Graphics.pixel_dimensions.join('x')}, dpi scale #{Lota::Graphics.dpi_scale}"
  puts "phone check: save directory #{Lota::Filesystem.save_directory}"
  puts "phone check: saved #{Lota::Filesystem.write('check.txt', 'saved').first}"
  puts "phone check: another thread: #{PhoneCheck.off_main_thread}"
  @source = PhoneCheck.tone
  @seconds = Float(ENV.fetch("PHONE_CHECK_SECONDS", "20"))
  @frames = 0
  @time = 0.0
  @touch = nil
end

def Lota.update(dt)
  @time += dt
  Lota::Event.quit(0) if @time > @seconds
end

def Lota.draw
  @frames += 1
  Lota::Graphics.background_color = 0.1, 0.3 + (0.2 * Math.sin(@time)), 0.6
  Lota::Graphics.color = 1, 0.8, 0.2
  Lota::Graphics.rectangle(:fill, 40, 120, 300, 200)
  Lota::Graphics.color = 1, 1, 1
  Lota::Graphics.print("Lota on #{Lota::System.os}, frame #{@frames}", 40, 60, 0, 2, 2)
  Lota::Graphics.rectangle(:fill, @touch[0] - 40, @touch[1] - 40, 80, 80) if @touch
  puts "phone check: drew frame #{@frames}" if @frames == 1 || (@frames % 300).zero?
end

def Lota.touchpressed(id, x, y)
  @touch = [x, y]
  puts "phone check: touchpressed #{id.class} at #{x.round}, #{y.round}"
end

def Lota.keypressed(key, scancode)
  puts "phone check: keypressed #{key.inspect} #{scancode.inspect}"
end

def Lota.quit
  puts "phone check: quits after #{@frames} frames in #{@time.round(1)} s"
  false
end
