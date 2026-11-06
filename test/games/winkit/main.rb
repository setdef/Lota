# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rbconfig"

# Prints, one line each, what Lota sees of the computer it runs on: the
# version, Ruby, the system, a file saved and read back, a tone played,
# the controllers, touches, and sensors, then opens a window, prints the
# renderer and the display, compiles three shaders (one broken on
# purpose), animates for a few seconds, prints its frame times, and reads
# back two pixels of its own frame. It quits by itself with 0, or with 4
# when the window cannot open.
#
#   Winkit.exe                 runs 8 seconds
#   Winkit.exe --seconds=45    runs 45 seconds, for frame pacing
#   Winkit.exe --hold          runs 60 seconds and reports the input it saw
#
# When WINKIT_LOG names a file, every line goes there too, for a run
# started through the shell, whose standard output no one reads.
class Winkit
  ORANGE = [1.0, 0.5, 0.0, 1.0].freeze
  BACKGROUND = [0.1, 0.2, 0.6, 1.0].freeze
  ENVIRONMENT = %w[
    RUBYOPT
    RUBYLIB
    GEM_HOME
    GEM_PATH
    RUBYSHELL
    BUNDLE_GEMFILE
    ALSOFT_DRIVERS
    GALLIUM_DRIVER
    SDL_VIDEODRIVER
    LANG
].freeze

  PIXEL = <<~GLSL
    uniform float time;
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
      return Texel(tex, uv) * color * vec4(0.6 + 0.4 * sin(time + screen_coords.x / 40.0), 1.0, 1.0, 1.0);
    }
  GLSL
  VERTEX = <<~GLSL
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
      return transform_projection * vertex_position;
    }
  GLSL
  BROKEN = "vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) { return no_such_name; }"

  def initialize(arguments)
    @seconds = option(arguments, "--seconds", 8)
    @hold = arguments.any? { |argument| argument.start_with?("--hold") }
    @seconds = option(arguments, "--hold", 60) if @hold
    @log = ENV.fetch("WINKIT_LOG", nil)
    @frames = []
    @fps = []
    @inputs = Hash.new(0)
    @last = {}
    @drawn = 0
  end

  def say(line)
    puts line
    File.open(@log, "a:UTF-8") { |file| file.puts(line) } if @log
  end

  def load
    say "time at load: #{milliseconds}"
    say "lota: #{Lota::VERSION}"
    report_ruby
    report_system
    report_files
    report_audio
    report_input_devices
    open_window
  end

  def update(delta)
    return if @finished

    elapsed = Lota::Timer.time - @started
    return finish(4) if elapsed >= (@window ? @seconds : 1)

    @frames << delta if @window && elapsed > 0.5
    @fps << Lota::Timer.fps while @fps.size < elapsed.floor
    capture if !@captured && elapsed > 2 && @drawn > 10
  end

  # The loop clears each frame with the background colour before draw,
  # as love.run does, so the colour is set once the window opens.
  def draw
    first_frame if @drawn.zero?
    @drawn += 1
    Lota::Graphics.color = ORANGE
    Lota::Graphics.rectangle(:fill, 24, 24, 64, 64)
    draw_animation(Lota::Timer.time - @started)
    Lota::Graphics.color = [1, 1, 1, 1]
    Lota::Graphics.print(caption, 110, 24)
  end

  def event(name, *arguments)
    @inputs[name] += 1
    @last[name] = arguments.map { |argument| shown(argument) }
    return if %i[mousemoved wheelmoved joystickaxis gamepadaxis].include?(name)

    say "input: #{name} #{@last[name].join(' ')} at #{(Lota::Timer.time - @started).round(2)} s"
  end

  def joystick(change, stick)
    say "joystick #{change}: #{stick.name.inspect} guid=#{stick.guid} gamepad?=#{stick.gamepad?}"
    return unless change == :added

    say "  type=#{stick.joystick_type} axes=#{stick.axis_count} buttons=#{stick.button_count} " \
      "hats=#{stick.hat_count} device=#{stick.device_info.inspect}"
    say "  gamepad type=#{stick.gamepad_type}" if stick.gamepad?
  end

  private def shown(argument)
    return argument.round(3) if argument.is_a?(Float)

    argument.respond_to?(:guid) ? argument.name : argument
  end

  private def option(arguments, name, default)
    found = arguments.find { |argument| argument.start_with?("#{name}=") }
    found ? Float(found.split("=", 2).last) : default
  end

  private def milliseconds
    (Time.now.to_f * 1000).round
  end

  private def report_ruby
    say "ruby: #{RUBY_DESCRIPTION}"
    say "ruby program: #{RbConfig.ruby}"
    say "gem dir: #{Gem.dir}"
    say "verbose: #{$VERBOSE.inspect}"
    say "game folder: #{__dir__}"
    say "working directory: #{Dir.pwd}"
    say "encodings: external=#{Encoding.default_external} filesystem=#{Encoding.find('filesystem')}"
    ENVIRONMENT.each { |name| say "env #{name}: #{ENV.fetch(name, '(unset)')}" }
  end

  private def report_system
    say "os: #{Lota::System.os}"
    say "processors: #{Lota::System.processor_count}"
    say "memory: #{Lota::System.memory_size} MB"
    say "power: #{Lota::System.power_info.inspect}"
    say "locales: #{Lota::System.preferred_locales.inspect}"
  end

  private def report_files
    say "fused: #{Lota::Filesystem.fused?}"
    say "identity: #{Lota::Filesystem.identity}"
    say "save directory: #{Lota::Filesystem.save_directory}"
    written = "winkit wrote this at #{Time.now.utc}"
    say "saved: #{Lota::Filesystem.write('winkit-check.txt', written).inspect}"
    read = Lota::Filesystem.read("winkit-check.txt").first
    say "read back: #{(read == written) ? 'the same' : "different: #{read.inspect}"}"
  rescue => e
    say "files: #{e.class}: #{e.message}"
  end

  private def report_audio
    samples = 22_050
    tone = Lota::Sound::SoundData.new(samples, 44_100, 16, 1)
    samples.times { |index| tone.sample = [index, 0.3 * Math.sin(2 * Math::PI * 440 * index / 44_100.0)] }
    @source = Lota::Audio::Source.new(tone)
    @source.play
    say "audio: 440 Hz tone for #{tone.duration.round(2)} s, active sources: #{Lota::Audio.active_source_count}"
  rescue => e
    say "audio: #{e.class}: #{e.message}"
  end

  private def report_input_devices
    say "joysticks at load: #{Lota::Joystick.joystick_count}"
    say "touches: #{Lota::Touch.touches.size}"
    %i[accelerometer gyroscope].each { |sensor| say "sensor #{sensor}: #{Lota::Sensor.sensor?(sensor)}" }
  rescue => e
    say "input devices: #{e.class}: #{e.message}"
  end

  private def open_window
    @started = Lota::Timer.time
    Lota::Window.title = "Winkit"
    Lota::Window.set_mode(800, 450, vsync: 1, resizable: true)
    @window = true
    Lota::Graphics.background_color = BACKGROUND
    report_renderer
    report_display
    compile_shaders
    say "hold: for #{@seconds.round} s, move the mouse, click, press keys and gamepad buttons" if @hold
  rescue => e
    say "window: refused"
    e.message.each_line { |line| say "  #{line.chomp}" }
  end

  private def report_renderer
    info = Lota::Graphics.renderer_info
    @device = info.last.to_s
    say "renderer: #{info.join(' / ')}"
    say "texture size limit: #{Lota::Graphics.system_limits.texturesize}"
  end

  private def report_display
    width, height, mode = Lota::Window.mode
    say "window: #{width}x#{height} vsync=#{mode.vsync} refreshrate=#{mode.refreshrate} display=#{mode.displayindex}"
    say "window dpi scale: #{Lota::Window.dpi_scale} native: #{Lota::Window.native_dpi_scale}"
    say "graphics dimensions: #{Lota::Graphics.dimensions.inspect} pixels: #{Lota::Graphics.pixel_dimensions.inspect} " \
      "dpi scale: #{Lota::Graphics.dpi_scale}"
    (1..(Lota::Window.display_count)).each do |index|
      rates = Lota::Window.fullscreen_modes(index).map(&:refreshrate).uniq.sort.reverse.first(4)
      say "display #{index}: #{Lota::Window.display_name(index).inspect} " \
        "desktop=#{Lota::Window.desktop_dimensions(index).join('x')} refresh rates=#{rates.inspect}"
    end
  rescue => e
    say "display: #{e.class}: #{e.message}"
  end

  private def compile_shaders
    { "pixel" => [PIXEL], "vertex and pixel" => [VERTEX, PIXEL], "broken, on purpose" => [BROKEN] }.each do |label, code|
      shader = Lota::Graphics::Shader.new(*code)
      @shader ||= shader
      say "shader #{label}: compiled#{" with warnings: #{shader.warnings.strip}" unless shader.warnings.strip.empty?}"
    rescue => e
      say "shader #{label}: #{e.class}"
      e.message.each_line { |line| say "  #{line.chomp}" }
    end
  end

  private def first_frame
    say "time at first frame: #{milliseconds}"
  end

  private def draw_animation(elapsed)
    Lota::Graphics.color = [1, 1, 1, 1]
    Lota::Graphics.push
    Lota::Graphics.translate(400, 260)
    Lota::Graphics.rotate(elapsed * 2)
    Lota::Graphics.rectangle(:fill, -40, -40, 80, 80)
    Lota::Graphics.pop
    Lota::Graphics.circle(:fill, 400 + (Math.cos(elapsed * 3) * 150), 260 + (Math.sin(elapsed * 3) * 100), 20)
    return unless @shader

    @shader.__send__(:send, "time", elapsed) # Shader#send, which Style/Send reads as Object#send
    Lota::Graphics.shader = @shader
    Lota::Graphics.rectangle(:fill, 24, 300, 200, 100)
    Lota::Graphics.shader = nil
  end

  private def caption
    lines = ["Winkit, Lota #{Lota::VERSION}", "#{Lota::Timer.fps} fps", @device.to_s]
    if @hold
      lines << "Move the mouse, click, press keys and gamepad buttons."
      lines.concat(@last.except(:mousemoved).map { |name, values| "#{name} #{values.join(' ')}" }.last(6))
    end
    lines.join("\n")
  end

  private def capture
    @captured = true
    Lota::Graphics.capture_screenshot do |image|
      scale = image.width / Lota::Graphics.width.to_f
      say "frame: #{image.width}x#{image.height}"
      say "pixel in the orange square: #{rounded(image.pixel(56 * scale, 56 * scale))} (drawn #{ORANGE.inspect})"
      say "pixel in the corner: #{rounded(image.pixel(image.width - 3, image.height - 3))} (drawn #{BACKGROUND.inspect})"
      image.encode(:png, "frame.png")
      say "frame saved: #{File.join(Lota::Filesystem.save_directory, 'frame.png')}"
    end
  end

  private def rounded(values)
    values.map { |value| value.round(3) }.inspect
  end

  private def finish(status)
    @finished = true
    report_frames
    report_inputs
    say "audio: active sources at the end: #{Lota::Audio.active_source_count}"
    say "exiting with #{@window ? 0 : status}"
    Lota::Event.quit(@window ? 0 : status)
  end

  private def report_frames
    return say("frames: none drawn") if @frames.empty?

    times = @frames.map { |delta| delta * 1000 }.sort
    worst = times.last([times.size / 100, 1].max)
    say "frames: #{times.size} after the first half second, ms average=#{(times.sum / times.size).round(2)} " \
      "min=#{times.first.round(2)} max=#{times.last.round(2)} p99=#{times[(times.size * 0.99).floor - 1].round(2)} " \
      "1% low=#{(1000 / (worst.sum / worst.size)).round(1)} fps"
    say "fps each second: #{@fps.join(' ')}"
  end

  private def report_inputs
    say "inputs seen: #{@inputs.empty? ? 'none' : @inputs.map { |name, count| "#{name}=#{count}" }.join(' ')}"
    @last.each { |name, values| say "last #{name}: #{values.join(' ')}" }
    say "mouse at the end: #{Lota::Mouse.position.map(&:round).inspect}" if @window
  end
end

def Lota.load(arguments)
  @winkit = Winkit.new(arguments + ARGV)
  @winkit.load
end

def Lota.update(delta)
  @winkit.update(delta)
end

def Lota.draw
  @winkit.draw
end

def Lota.joystickadded(joystick)
  @winkit.joystick(:added, joystick)
end

def Lota.joystickremoved(joystick)
  @winkit.joystick(:removed, joystick)
end

%i[
  keypressed
  keyreleased
  mousepressed
  mousereleased
  mousemoved
  wheelmoved
  textinput
  touchpressed
  joystickpressed
  joystickaxis
  joystickhat
  gamepadpressed
  gamepadreleased
  gamepadaxis
].each do |name|
  Lota.define_singleton_method(name) { |*arguments| @winkit.event(name, *arguments) }
end

def Lota.errorhandler(error)
  puts "error: #{error.class}: #{error.message}"
  error.backtrace&.first(8)&.each { |line| puts "  #{line}" }
  nil
end
