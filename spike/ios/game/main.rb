# frozen_string_literal: true

# The iOS spike's game: a background that changes color, a rectangle, and
# a line of text, so a screenshot shows that the engine drew. It prints
# what the frames did, which the log shows, and quits after ten seconds.
$stdout.sync = true

def Lota.load
  puts "LotaSpike loaded on #{RUBY_PLATFORM}, renderer #{Lota::Graphics.renderer_info.join(' / ')}"
  puts "LotaSpike window #{Lota::Graphics.dimensions.join('x')}, dpi scale #{Lota::Graphics.dpi_scale}"
  @frames = 0
  @time = 0.0
end

def Lota.update(dt)
  @time += dt
  Lota::Event.quit(0) if @time > 10
end

def Lota.draw
  @frames += 1
  Lota::Graphics.background_color = 0.1, 0.3 + 0.2 * Math.sin(@time), 0.6
  Lota::Graphics.color = 1, 0.8, 0.2
  Lota::Graphics.rectangle(:fill, 40, 120, 300, 200)
  Lota::Graphics.color = 1, 1, 1
  Lota::Graphics.print("Lota on iOS, frame #{@frames}", 40, 60, 0, 2, 2)
  puts "LotaSpike drew frame #{@frames}" if @frames == 1 || (@frames % 60).zero?
end

def Lota.quit
  puts "LotaSpike quits after #{@frames} frames"
  false
end
