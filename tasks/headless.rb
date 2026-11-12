# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "rbconfig"
require "socket"
require "timeout"
require "tmpdir"

# Displays of a run's own, for Lota's checks on a Linux computer with no
# desktop: a headless machine, a CI runner, or a container.
#
# The checks open windows, and the gate gives each of its lanes an X
# display of its own (LOTA_GATE_DISPLAYS, tasks/gate.rb). When rake runs a
# task that opens windows, on Linux, and nothing has given it displays,
# tasks/headless.rake asks Headless.wanted? whether to make some. If so, a
# Session starts four, each with Openbox to manage its windows, as CI's
# Linux gate does, runs rake again inside them, and ends them however that
# rake ends. Each display is the first free one from FIRST up, clear of a
# desktop's and of xvfb-run's, and an X server holds its number by its
# lock, so runs at the same time never share a display.
#
# LOTA_HEADLESS=1 makes displays even where DISPLAY names one that works,
# so no window opens on that desktop, and LOTA_HEADLESS=0 never makes
# them. LOTA_GATE_GPU chooses where they draw:
#
# [off]    Xvfb, drawn by Mesa's llvmpipe, as on CI's runner (the default).
# [opengl] The GPU at RENDER_NODE: for each display a weston of its own,
#          whose headless backend renders on the GPU with no seat, no
#          login, and nothing on a screen, and in it a rootful Xwayland as
#          the X display. LÖVE takes the GPU's OpenGL.
# [vulkan] The same, with Vulkan visible, so LÖVE takes the GPU's Vulkan.
#          A GPU with no Vulkan driver falls back to opengl.
#
# Either GPU mode asks for displays, and one that cannot start says why and
# falls back to Xvfb. Unless the mode is vulkan, rake runs under bwrap with
# Vulkan's driver folders (ICDS) hidden behind an empty one: Vulkan cannot
# present on Xvfb, which has no DRI3, and CI's runner has no Vulkan driver.
class Headless
  # Raised when the displays cannot start, or a setting is not one Headless knows.
  class Failure < StandardError; end

  # The first and last display numbers a Session tries.
  FIRST = 300
  LAST = 399

  # How many displays a Session starts: one for each of the gate's lanes
  # that opens windows (tasks/gate.rake), the last the parity harness's.
  COUNT = 4

  # Each display's screen, which holds the 800x600 window a game opens by
  # default with room to move it.
  WIDTH = 1280
  HEIGHT = 1024

  # LOTA_GATE_GPU's values.
  GPU_MODES = %w[off opengl vulkan].freeze

  # The tasks that open windows, besides test and its namespace.
  TASKS = %w[default gate prepush red_before_green package:install package:deliver].freeze

  # The tests of test's namespace that open none: the unit tests
  # (UNIT_TESTS in tasks/test.rake).
  UNIT = /\Atest:(?:shard:)?unit(?::|\z)/

  # The render node a GPU mode draws on.
  RENDER_NODE = "/dev/dri/renderD128"

  # Where Vulkan's loader finds its drivers.
  ICDS = %w[/usr/share/vulkan/icd.d /etc/vulkan/icd.d].freeze

  # Where X servers put their sockets.
  SOCKETS = "/tmp/.X11-unix"

  # Whether rake, running the top-level +tasks+ in +env+ on +platform+,
  # should start displays of its own: on Linux, for a task that opens
  # windows, when LOTA_GATE_DISPLAYS names none, and when LOTA_HEADLESS or
  # LOTA_GATE_GPU asks for them, or +usable+ (called with DISPLAY's value)
  # says DISPLAY names no display that works.
  def self.wanted?(env:, tasks:, platform: RUBY_PLATFORM, usable: method(:usable?))
    return false unless platform.include?("linux")
    return false unless env.fetch("LOTA_GATE_DISPLAYS", "").strip.empty?
    return false unless tasks.any? { |task| opens_windows?(task) }

    case env.fetch("LOTA_HEADLESS", "")
    when "1" then true
    when "0" then false
    when "" then gpu(env) != "off" || !usable.call(env.fetch("DISPLAY", ""))
    else raise Failure, "LOTA_HEADLESS is #{env['LOTA_HEADLESS'].inspect}; use 1, 0, or leave it unset"
    end
  end

  # Whether the rake task +task+, as given on rake's command line, opens windows.
  def self.opens_windows?(task)
    name = task.sub(/\[.*\z/m, "")
    return false if name.match?(UNIT)

    TASKS.include?(name) || name == "test" || name.start_with?("test:")
  end

  # LOTA_GATE_GPU's mode in +env+, off unless set.
  def self.gpu(env)
    mode = env.fetch("LOTA_GATE_GPU", "")
    mode = "off" if mode.empty?
    return mode if GPU_MODES.include?(mode)

    raise Failure, "LOTA_GATE_GPU is #{mode.inspect}; use #{GPU_MODES.join(', ')}, or leave it unset"
  end

  # Whether +display+, a DISPLAY value, names an X server that takes
  # connections. A display on another host is taken at its word; a local
  # one must answer on its socket in +sockets+.
  def self.usable?(display, sockets: SOCKETS)
    match = /\A(?<host>[^:]*):(?<number>\d+)(?:\.\d+)?\z/.match(display)
    return false unless match
    return true unless match[:host].empty? || match[:host] == "unix"

    UNIXSocket.new(File.join(sockets, "X#{match[:number]}")).close
    true
  rescue SystemCallError
    false
  end

  # Where +tool+ is on +env+'s PATH, or nil.
  def self.which(env, tool)
    env.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }
      .find { |path| File.executable?(path) && !File.directory?(path) }
  end

  # The renderer glxinfo -B's +output+ names, or nil.
  def self.renderer(output)
    output[/^OpenGL renderer string: (.+)$/, 1]&.strip
  end

  # Whether +renderer+ is a GPU's, not Mesa's software rasterizers.
  def self.gpu_renderer?(renderer)
    !renderer.nil? && !renderer.match?(/llvmpipe|softpipe/)
  end

  # The first GPU vulkaninfo --summary's +output+ names, or nil when it
  # names only llvmpipe or nothing.
  def self.vulkan_device(output)
    output.scan(/^\s*deviceName\s*=\s*(.+)$/).flatten.map(&:strip).find { |name| !name.include?("llvmpipe") }
  end

  # The command that hides +icds+, the Vulkan driver folders that exist,
  # behind +empty+ with +bwrap+, put before rake's: nothing in +mode+
  # vulkan, without bwrap, or with no folder to hide.
  def self.sandbox(mode:, bwrap:, icds:, empty:)
    return [] if mode == "vulkan" || bwrap.nil? || icds.empty?

    [bwrap, "--die-with-parent", "--dev-bind", "/", "/", *icds.flat_map { |icd| ["--bind", empty, icd] }]
  end

  # What a Session changes in rake's environment, given the +env+ it
  # started in: the +displays+, in the gate's lane order, the last the
  # parity harness's; where they draw, +mode+; a desktop input lock of the
  # run's own in +dir+, since its displays are; and, unless +env+ sets
  # them, the settings Lota's checks need without a desktop:
  #
  # - LP_PERF=no_rast_linear, since Mesa's llvmpipe after 24.0.5 reads the
  #   wrong uniform array and matrix elements in its linear rasterizer
  #   (stock LÖVE fails the same way);
  # - LOTA_PARITY_CACHE=0, as on CI: a run on displays of its own keeps
  #   nothing for a later one (test/parity/reference_cache.rb);
  # - DESKTOP_INPUT_QUIET=1, since the desktop input lock otherwise speaks
  #   and shows banners outside CI, and nothing plays here;
  # - with +ccache+, the path of ccache, CMake's builds compile through it,
  #   with paths taken relative to +root+, so a new checkout builds from
  #   ccache's cache, which follows XDG_CACHE_HOME.
  #
  # WAYLAND_DISPLAY and PULSE_SERVER go, so nothing reaches a desktop.
  def self.environment(env:, displays:, mode:, dir:, root:, ccache: nil)
    given = {
      "LP_PERF" => "no_rast_linear",
      "LOTA_PARITY_CACHE" => "0",
      "DESKTOP_INPUT_QUIET" => "1",
    }
    if ccache
      given.merge!("CMAKE_C_COMPILER_LAUNCHER" => ccache, "CMAKE_CXX_COMPILER_LAUNCHER" => ccache,
        "CCACHE_BASEDIR" => root)
    end
    given.reject { |name, _| env.key?(name) }.merge(
      "DISPLAY" => displays.first,
      "LOTA_GATE_DISPLAYS" => displays.join(" "),
      "LOTA_PARITY_DISPLAY" => displays.last,
      "LOTA_GATE_GPU" => mode,
      "DESKTOP_INPUT_LOCK" => File.join(dir, "desktop-input.lock"),
      "WAYLAND_DISPLAY" => nil,
      "PULSE_SERVER" => nil
    )
  end

  # The display numbers from +first+ to +last+, each handed out once.
  class Numbers
    # [taken] Whether a number's lock file says a server holds it.
    def initialize(first: FIRST, last: LAST, taken: -> (number) { File.exist?("/tmp/.X#{number}-lock") })
      @next = first
      @last = last
      @taken = taken
    end

    # The first number from here up that no server holds and for which the
    # block, which starts a server on it, answers true; numbers tried are
    # never tried again. Raises Failure when none is left.
    def claim
      while @next <= @last
        number = @next
        @next += 1
        next if @taken.call(number)
        return number if yield(number)
      end
      raise Failure, "no display from :#{FIRST} to :#{@last} is free"
    end
  end

  # Starts the displays, runs a command in them, and ends them.
  class Session
    # How long, in seconds, a server may take to take connections.
    READY = 10

    # [env] The environment rake started in.
    # [root] The checkout.
    # [out] Where the session says what it does.
    def initialize(env:, root:, out: $stdout)
      @env = env
      @root = root
      @out = out
      @pids = []
      @numbers = Numbers.new
    end

    # Runs +command+ in displays of its own and returns its exit status.
    def run(command)
      @dir = Dir.mktmpdir("lota-headless-")
      mode = start
      child = spawn_child(command, mode)
      status = wait_for(child)
      status.exitstatus || (128 + status.termsig.to_i)
    ensure
      stop
      FileUtils.rm_rf(@dir) if @dir
    end

    private def start
      missing = %w[Xvfb openbox].reject { |tool| which(tool) }
      unless missing.empty?
        raise Failure, "#{missing.join(' and ')} must be installed to open windows with no desktop " \
          "(tasks/apt/build.txt names their packages)"
      end

      mode = Headless.gpu(@env)
      mode = start_gpu(mode) if mode != "off"
      start_xvfb if mode == "off"
      @displays.each { |display| background({ "DISPLAY" => display }, "openbox") }
      start_bus
      sleep 1
      say "displays #{@displays.join(' ')} (GPU: #{mode})"
      mode
    end

    private def start_xvfb
      @displays = Array.new(COUNT) do
        server("Xvfb", "-screen", "0", "#{WIDTH}x#{HEIGHT}x24", "-nolisten", "tcp")
      end
    end

    # The mode the GPU displays started in, or off when they could not.
    # weston's 1 kHz refresh keeps vsync from pacing every test to 60 Hz
    # through Xwayland.
    private def start_gpu(mode)
      why = gpu_missing
      return fallback(why) if why

      runtime = File.join(@dir, "gpu")
      Dir.mkdir(runtime, 0o700)
      config = File.join(runtime, "weston.ini")
      File.write(config, "[core]\nidle-time=0\nshell=kiosk\n")
      @displays = Array.new(COUNT) do |index|
        socket = File.join(runtime, "w#{index}")
        log = File.join(runtime, "weston#{index}.log")
        background({ "XDG_RUNTIME_DIR" => runtime }, "weston", "--config=#{config}", "--backend=headless",
          "--renderer=gl", "--width=#{WIDTH}", "--height=#{HEIGHT}", "--refresh-rate=1000000",
          "--socket=w#{index}", "--log=#{log}")
        wait_until { File.socket?(socket) }
        unless File.read(log).include?("Using rendering device: /dev/dri/renderD")
          return fallback("weston did not render on the GPU: #{File.readlines(log).last(2).join.strip}")
        end

        server({ "WAYLAND_DISPLAY" => socket }, "Xwayland", "-fullscreen", "-geometry", "#{WIDTH}x#{HEIGHT}",
          "-nolisten", "tcp")
      end
      renderer = Headless.renderer(capture("glxinfo", "-B"))
      return fallback("OpenGL is not the GPU's (#{renderer || 'none'})") unless Headless.gpu_renderer?(renderer)

      say "GPU displays; OpenGL: #{renderer}"
      (mode == "vulkan") ? vulkan : mode
    rescue Failure, SystemCallError => e
      fallback(e.message)
    end

    private def gpu_missing
      return "no access to #{RENDER_NODE}" unless File.readable?(RENDER_NODE) && File.writable?(RENDER_NODE)

      missing = %w[weston Xwayland glxinfo].find { |tool| !which(tool) }
      "#{missing} is not installed" if missing
    end

    private def vulkan
      device = Headless.vulkan_device(capture("vulkaninfo", "--summary"))
      return say("Vulkan: #{device}") && "vulkan" if device

      say "no Vulkan GPU; hiding Vulkan, as for opengl"
      "opengl"
    end

    private def fallback(why)
      say "GPU displays unavailable (#{why}); falling back to Xvfb and llvmpipe"
      stop
      @displays = nil
      "off"
    end

    # Starts the X server +command+ on the next free display and answers
    # it, as :N, once the server says, on the descriptor -displayfd names,
    # that it takes connections.
    private def server(*command)
      environment = command.first.is_a?(Hash) ? command.shift : {}
      number = @numbers.claim do |candidate|
        reader, writer = IO.pipe
        pid = background(environment, *command, ":#{candidate}", "-displayfd", "3", 3 => writer)
        writer.close
        ready?(reader, pid)
      ensure
        reader&.close
      end
      ":#{number}"
    end

    # Whether the server +pid+ wrote its display number to +reader+ before
    # it ended, as it does when another server holds the number, or before
    # READY seconds passed.
    private def ready?(reader, pid)
      Timeout.timeout(READY) { !reader.gets.to_s.strip.empty? }
    rescue Timeout::Error
      Process.kill("TERM", pid)
      false
    end

    # A session bus of the run's own where none is given, with
    # XDG_RUNTIME_DIR, which SDL wants and says so in output the tests
    # compare. Without one, libdbus starts a bus tied to the X display, and
    # the first program on each display writes ~/.dbus while later ones
    # find that bus and write nothing.
    private def start_bus
      @bus = {}
      return if (runtime = @env["XDG_RUNTIME_DIR"]) && File.directory?(runtime)

      runtime = File.join(@dir, "xdg-runtime")
      Dir.mkdir(runtime, 0o700)
      @bus["XDG_RUNTIME_DIR"] = runtime
      return say("dbus-daemon is not installed; no session bus") unless which("dbus-daemon")

      socket = File.join(runtime, "bus")
      background("dbus-daemon", "--session", "--nofork", "--nopidfile", "--address=unix:path=#{socket}")
      wait_until { File.socket?(socket) }
      raise Failure, "the session bus did not start" unless File.socket?(socket)

      @bus["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=#{socket}"
    end

    private def spawn_child(command, mode)
      environment = Headless.environment(env: @env, displays: @displays, mode:, dir: @dir, root: @root,
        ccache: which("ccache")).merge(@bus)
      empty = File.join(@dir, "empty")
      Dir.mkdir(empty)
      sandbox = Headless.sandbox(mode:, bwrap: usable_bwrap, icds: ICDS.select { |icd| File.directory?(icd) }, empty:)
      say "running: #{command.join(' ')}"
      Process.spawn(environment, *sandbox, *command, chdir: @root, pgroup: true)
    end

    # bwrap, when it is installed and can run here; in a container it
    # often cannot.
    private def usable_bwrap
      path = which("bwrap")
      return say("bwrap is not installed; Vulkan's drivers stay visible") && nil unless path
      return path if system(path, "--dev-bind", "/", "/", "true", %i[out err] => File::NULL)

      say "bwrap cannot run here; Vulkan's drivers stay visible"
      nil
    end

    # Waits for +child+, passing on any signal the session gets.
    private def wait_for(child)
      previous = %w[INT TERM HUP].to_h do |signal|
        [signal, Signal.trap(signal) { pass_on(signal, child) }]
      end
      Process.wait2(child).last
    ensure
      previous&.each { |signal, handler| Signal.trap(signal, handler) }
    end

    private def pass_on(signal, child)
      Process.kill(signal, child)
    rescue Errno::ESRCH
      nil
    end

    # Starts +command+, tied to this process where setpriv can do it, so it
    # gets TERM even if this process is killed.
    private def background(*command, **redirects)
      environment = command.first.is_a?(Hash) ? command.shift : {}
      tie = which("setpriv") ? %w[setpriv --pdeathsig TERM] : []
      pid = Process.spawn(environment, *tie, *command, in: File::NULL, out: File::NULL, err: File::NULL, **redirects)
      @pids << pid
      pid
    end

    private def stop
      @pids.each { |pid| pass_on("TERM", pid) }
      @pids.each do |pid|
        Timeout.timeout(5) { Process.wait(pid) }
      rescue Timeout::Error
        Process.kill("KILL", pid)
        Process.wait(pid)
      rescue Errno::ECHILD
        nil
      end
      @pids.clear
    end

    private def wait_until
      50.times do
        return if yield

        sleep 0.1
      end
    end

    private def capture(*command)
      IO.popen({ "DISPLAY" => @displays.first }, ["timeout", "20", *command], err: File::NULL, &:read)
    rescue SystemCallError
      ""
    end

    private def which(tool) = Headless.which(@env, tool)

    private def say(text)
      @out.puts "headless: #{text}"
      @out.flush
      true
    end
  end
end
