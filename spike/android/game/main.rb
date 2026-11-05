# frozen_string_literal: true

# The Android spike's game: a background that changes color, a rectangle,
# a line of text, and a white square where the last touch landed, so a
# screenshot shows that the engine drew and that a touch arrived. It
# prints what the frames did, each touch callback's arguments, and whether
# Lota's main-thread check holds on Android's Ruby thread, which logcat
# shows, and quits after LOTA_SPIKE_SECONDS (default 40).
$stdout.sync = true

def Lota.load
  puts "LotaSpike loaded on #{RUBY_PLATFORM} (#{Lota::System.os}), renderer #{Lota::Graphics.renderer_info.join(' / ')}"
  puts "LotaSpike window #{Lota::Graphics.dimensions.join('x')}, pixels " \
    "#{Lota::Graphics.pixel_dimensions.join('x')}, dpi scale #{Lota::Graphics.dpi_scale}"
  puts "LotaSpike save directory #{Lota::Filesystem.save_directory}"
  puts "LotaSpike main thread: graphics here gives a font, #{Lota::Graphics.font.class}"
  off = Thread.new do
    Lota::Graphics.font
    "no error"
  rescue ThreadError => e
    "#{e.class}: #{e.message}"
  end.value
  puts "LotaSpike another thread: #{off}"
  begin
    tone = Lota::Sound::SoundData.new(22_050, 22_050, 16, 1)
    tone.sample_count.times { |i| tone.sample = i, 0.2 * Math.sin(2 * Math::PI * 440 * i / 22_050.0) }
    @source = Lota::Audio::Source.new(tone, :static)
    @source.looping = true
    @source.play
    puts "LotaSpike audio: playing #{@source.playing?}, active sources #{Lota::Audio.active_source_count}"
  rescue StandardError => e
    puts "LotaSpike audio failed: #{e.class}: #{e.message}"
  end
  @seconds = Float(ENV.fetch("LOTA_SPIKE_SECONDS", "40"))
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
  Lota::Graphics.background_color = 0.1, 0.3 + 0.2 * Math.sin(@time), 0.6
  Lota::Graphics.color = 1, 0.8, 0.2
  Lota::Graphics.rectangle(:fill, 40, 120, 300, 200)
  Lota::Graphics.color = 1, 1, 1
  Lota::Graphics.print("Lota on Android, frame #{@frames}", 40, 60, 0, 2, 2)
  Lota::Graphics.rectangle(:fill, @touch[0] - 40, @touch[1] - 40, 80, 80) if @touch
  return unless @frames == 1 || (@frames % 120).zero?

  puts "LotaSpike drew frame #{@frames} at #{@time.round(1)} s, source playing #{@source&.playing?}"
end

def Lota.touchpressed(id, x, y, dx, dy, pressure, devicetype, mouse)
  @touch = [x, y]
  puts "LotaSpike touchpressed id=#{id.inspect} x=#{x.inspect} y=#{y.inspect} dx=#{dx.inspect} dy=#{dy.inspect} " \
    "pressure=#{pressure.inspect} devicetype=#{devicetype.inspect} mouse=#{mouse.inspect} frame #{@frames}"
end

def Lota.touchreleased(id, x, y, dx, dy, pressure, devicetype, mouse)
  puts "LotaSpike touchreleased id=#{id.inspect} x=#{x.inspect} y=#{y.inspect} dx=#{dx.inspect} dy=#{dy.inspect} " \
    "pressure=#{pressure.inspect} devicetype=#{devicetype.inspect} mouse=#{mouse.inspect}"
end

def Lota.mousepressed(x, y, button, istouch, presses)
  puts "LotaSpike mousepressed x=#{x.inspect} y=#{y.inspect} button=#{button.inspect} istouch=#{istouch.inspect} " \
    "presses=#{presses.inspect}"
end

def Lota.keypressed(key, scancode, isrepeat)
  puts "LotaSpike keypressed key=#{key.inspect} scancode=#{scancode.inspect} isrepeat=#{isrepeat.inspect}"
end

def Lota.keyreleased(key, scancode)
  puts "LotaSpike keyreleased key=#{key.inspect} scancode=#{scancode.inspect}"
end

def Lota.focus(focus)
  puts "LotaSpike focus #{focus.inspect} at #{@time.round(1)} s, source playing #{@source&.playing?}"
end

def Lota.visible(visible)
  puts "LotaSpike visible #{visible.inspect} at #{@time.round(1)} s, source playing #{@source&.playing?}"
end

def Lota.quit
  puts "LotaSpike quits after #{@frames} frames in #{@time.round(1)} s"
  false
end
