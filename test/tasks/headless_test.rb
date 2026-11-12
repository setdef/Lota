# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/headless"
require "json"
require "rbconfig"
require "stringio"

# Headless decides when rake makes displays of its own and how they draw,
# and its Session starts real X servers, runs a command in them, and ends
# them.
class HeadlessTest < Minitest::Test
  include TreeHelper

  LINUX = "x86_64-linux"

  def wanted?(env, tasks: %w[default], platform: LINUX, usable: false)
    Headless.wanted?(env:, tasks:, platform:, usable: -> (_display) { usable })
  end

  def test_rake_makes_displays_on_linux_when_no_display_works
    assert wanted?({})
    assert wanted?({ "DISPLAY" => ":0" })
  end

  def test_rake_uses_a_desktop_whose_display_works
    refute wanted?({ "DISPLAY" => ":0" }, usable: true)
  end

  def test_lota_headless_asks_for_displays_even_on_a_desktop_or_refuses_them
    assert wanted?({ "DISPLAY" => ":0", "LOTA_HEADLESS" => "1" }, usable: true)
    refute wanted?({ "LOTA_HEADLESS" => "0" })
    assert_raises(Headless::Failure) { wanted?({ "LOTA_HEADLESS" => "yes" }) }
  end

  def test_a_gpu_mode_asks_for_displays
    assert wanted?({ "DISPLAY" => ":0", "LOTA_GATE_GPU" => "opengl" }, usable: true)
    refute wanted?({ "DISPLAY" => ":0", "LOTA_GATE_GPU" => "off" }, usable: true)
  end

  def test_displays_given_are_kept_as_ci_gives_them
    refute wanted?({ "LOTA_GATE_DISPLAYS" => ":99 :97 :96 :98" })
    refute wanted?({ "LOTA_GATE_DISPLAYS" => ":99", "LOTA_HEADLESS" => "1" })
  end

  def test_only_linux_and_only_tasks_that_open_windows
    refute wanted?({}, platform: "arm64-darwin25")
    refute wanted?({}, platform: "x64-mingw-ucrt")
    refute wanted?({}, tasks: %w[lint steep compile])
    %w[gate prepush red_before_green[a..b] test test:shard:parity package:install].each do |task|
      assert wanted?({}, tasks: ["lint", task]), task
    end
  end

  def test_gpu_modes
    assert_equal "off", Headless.gpu({})
    assert_equal "off", Headless.gpu({ "LOTA_GATE_GPU" => "" })
    assert_equal "vulkan", Headless.gpu({ "LOTA_GATE_GPU" => "vulkan" })
    error = assert_raises(Headless::Failure) { Headless.gpu({ "LOTA_GATE_GPU" => "metal" }) }
    assert_includes error.message, "off, opengl, vulkan"
  end

  def test_a_display_is_usable_when_its_socket_answers
    in_tree do |dir|
      server = UNIXServer.new(File.join(dir, "X7"))

      assert Headless.usable?(":7", sockets: dir)
      assert Headless.usable?("unix:7.0", sockets: dir)
      refute Headless.usable?(":8", sockets: dir)
      refute Headless.usable?("", sockets: dir)
      assert Headless.usable?("remote:0", sockets: dir)
    ensure
      server&.close
    end
  end

  def test_numbers_skip_those_held_and_those_whose_server_fails_and_are_never_reused
    numbers = Headless::Numbers.new(first: 300, last: 305, taken: -> (number) { number == 300 })
    tried = []

    first = numbers.claim { |number| (tried << number) && number != 301 }
    second = numbers.claim { |number| (tried << number) && true }

    assert_equal [302, 303], [first, second]
    assert_equal [301, 302, 303], tried
  end

  def test_numbers_run_out
    numbers = Headless::Numbers.new(first: 300, last: 301, taken: -> (_number) { false })

    error = assert_raises(Headless::Failure) { numbers.claim { false } }
    assert_includes error.message, "no display"
  end

  def test_only_a_gpus_renderer_counts
    output = "name of display: :300\nOpenGL vendor string: AMD\nOpenGL renderer string: AMD Radeon 890M (radeonsi)\n"
    assert_equal "AMD Radeon 890M (radeonsi)", Headless.renderer(output)
    assert Headless.gpu_renderer?("AMD Radeon 890M (radeonsi)")
    refute Headless.gpu_renderer?("llvmpipe (LLVM 20.1.2, 256 bits)")
    refute Headless.gpu_renderer?(nil)
    assert_nil Headless.renderer("Error: unable to open display :300\n")
  end

  def test_vulkan_needs_a_device_besides_llvmpipe
    summary = "Devices:\n========\nGPU0:\n\tdeviceName         = llvmpipe (LLVM 20.1.2, 256 bits)\n" \
      "GPU1:\n\tdeviceName         = AMD Radeon 890M (RADV GFX1150)\n"
    assert_equal "AMD Radeon 890M (RADV GFX1150)", Headless.vulkan_device(summary)
    assert_nil Headless.vulkan_device("GPU0:\n\tdeviceName = llvmpipe (LLVM 20.1.2, 256 bits)\n")
  end

  def test_vulkans_drivers_are_hidden_unless_the_mode_is_vulkan
    icds = %w[/usr/share/vulkan/icd.d]

    assert_equal %w[/bin/bwrap --die-with-parent --dev-bind / / --bind /e /usr/share/vulkan/icd.d],
      Headless.sandbox(mode: "off", bwrap: "/bin/bwrap", icds:, empty: "/e")
    assert_equal "/bin/bwrap", Headless.sandbox(mode: "opengl", bwrap: "/bin/bwrap", icds:, empty: "/e").first
    assert_empty Headless.sandbox(mode: "vulkan", bwrap: "/bin/bwrap", icds:, empty: "/e")
    assert_empty Headless.sandbox(mode: "off", bwrap: nil, icds:, empty: "/e")
    assert_empty Headless.sandbox(mode: "off", bwrap: "/bin/bwrap", icds: [], empty: "/e")
  end

  def test_the_environment_gives_each_lane_its_display_and_keeps_what_is_set
    env = { "LP_PERF" => "nothing", "WAYLAND_DISPLAY" => "wayland-0" }

    changes = Headless.environment(env:, displays: %w[:300 :301 :302 :303], mode: "off", dir: "/run",
      root: "/lota", ccache: "/bin/ccache")

    assert_equal ":300", changes.fetch("DISPLAY")
    assert_equal ":300 :301 :302 :303", changes.fetch("LOTA_GATE_DISPLAYS")
    assert_equal ":303", changes.fetch("LOTA_PARITY_DISPLAY")
    assert_equal "off", changes.fetch("LOTA_GATE_GPU")
    assert_equal "/run/desktop-input.lock", changes.fetch("DESKTOP_INPUT_LOCK")
    assert_equal "1", changes.fetch("DESKTOP_INPUT_QUIET")
    assert_equal "0", changes.fetch("LOTA_PARITY_CACHE")
    assert_equal "/bin/ccache", changes.fetch("CMAKE_CXX_COMPILER_LAUNCHER")
    assert_equal "/lota", changes.fetch("CCACHE_BASEDIR")
    refute changes.key?("LP_PERF"), "LP_PERF, set, is kept"
    assert_nil changes.fetch("WAYLAND_DISPLAY")
    assert_nil changes.fetch("PULSE_SERVER")
  end

  def test_the_environment_turns_off_llvmpipes_linear_rasterizer_and_leaves_ccache_off_without_it
    changes = Headless.environment(env: {}, displays: %w[:300], mode: "off", dir: "/run", root: "/lota")

    assert_equal "no_rast_linear", changes.fetch("LP_PERF")
    refute changes.key?("CMAKE_C_COMPILER_LAUNCHER")
  end

  # What the command run in a session finds: its displays, each answering.
  REPORT = <<~RUBY
    require #{File.expand_path('../../tasks/headless', __dir__).dump}
    displays = ENV.fetch("LOTA_GATE_DISPLAYS").split
    File.write(ARGV.fetch(0), JSON.generate("displays" => displays, "display" => ENV["DISPLAY"],
      "parity" => ENV["LOTA_PARITY_DISPLAY"], "usable" => displays.map { |display| Headless.usable?(display) }))
    exit 7
  RUBY

  def session(env, command)
    out = StringIO.new
    status = Headless::Session.new(env: ENV.to_h.merge(env).except("LOTA_GATE_GPU"), root: Dir.pwd, out:)
      .run(command)
    [status, out.string]
  end

  def report(file) = [RbConfig.ruby, "-rjson", "-e", REPORT, file]

  def test_a_session_runs_its_command_on_four_displays_of_its_own_and_ends_them
    skip "X servers run on Linux" unless RUBY_PLATFORM.include?("linux")
    skip "Xvfb is not installed" unless Headless.which(ENV, "Xvfb")

    in_tree do |dir|
      file = File.join(dir, "report.json")
      status, out = session({}, report(file))

      assert_equal 7, status, out
      found = JSON.parse(File.read(file))
      displays = found.fetch("displays")
      assert_equal 4, displays.uniq.size
      assert(displays.all? { |display| display.delete_prefix(":").to_i >= Headless::FIRST })
      assert_equal [displays.first, displays.last], found.values_at("display", "parity")
      assert_equal [true] * 4, found.fetch("usable")
      refute(displays.any? { |display| Headless.usable?(display) }, "a display outlived its session")
    end
  end

  def test_sessions_at_once_never_share_a_display
    skip "X servers run on Linux" unless RUBY_PLATFORM.include?("linux")
    skip "Xvfb is not installed" unless Headless.which(ENV, "Xvfb")

    in_tree do |dir|
      inner = File.join(dir, "inner.json")
      outer = File.join(dir, "outer.json")
      nested = <<~RUBY
        require #{File.expand_path('../../tasks/headless', __dir__).dump}
        require "stringio"
        system(*#{report(outer).inspect})
        exit Headless::Session.new(env: ENV.to_h, root: Dir.pwd, out: StringIO.new).run(#{report(inner).inspect})
      RUBY

      status, out = session({}, [RbConfig.ruby, "-e", nested])

      assert_equal 7, status, out
      first, second = [outer, inner].map { |file| JSON.parse(File.read(file)).fetch("displays") }
      assert_empty first & second
    end
  end
end
