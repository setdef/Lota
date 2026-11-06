# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# The parity harness's Metal watch (ext/lota/native_test/metal_watch.mm),
# which every parity run loads on macOS (Parity::METAL_WATCH): in a
# program that draws, it sees each command buffer the engine commits and
# waits for, and reports none that completed; it reports each that did
# not, with its status and error, and counts them all at exit. Each run is
# a Ruby of its own that loads the watch first, as the harness's runs do.
class MetalWatchTest < Minitest::Test
  # The watch's line at exit, with the counts it holds.
  SUMMARY = /\Alota-metal-watch: (\d+) command buffers committed, (\d+) completed, (\d+) failed; (\d+) waited on, (\d+) of them not completed\n\z/

  # Runs the Ruby +code+ with Lota and the test extension on the load path
  # and the watch loaded, in a home of its own, and returns its Output.
  def watched(code)
    Dir.mktmpdir("lota-metal-watch-") do |home|
      preload = { "DYLD_INSERT_LIBRARIES" => Parity::METAL_WATCH.join(":") }
      Parity.run({ "HOME" => home, **TestHome.environment(home), **preload }, RbConfig.ruby,
        "-w", "-I#{File.join(Parity::ROOT, 'lib')}", "-I#{Parity::LIB}",
        "-rlota_native_test", "-e", code, side: "Ruby") { 1 }
    end
  end

  unless TestHome::LINUX
    # A frame taken for a screenshot is copied, committed, and waited for
    # (vendor/love/src/modules/graphics/metal/Graphics.mm:1683-1745).
    def test_a_program_that_draws_commits_and_waits_for_command_buffers_that_complete
      output = watched(<<~RUBY)
        require #{File.join(Parity::ROOT, 'test/engine_helper').dump}
        EngineHelper.open_window
        frames = 0
        Lota::Native::Graphics.capture_screenshot(-> (_image) { frames += 1 })
        Lota::Graphics.clear(1, 0, 0)
        Lota::Graphics.present
        puts frames
      RUBY

      assert_predicate output.status, :success?, output.text + output.diagnostics
      # Lövetest's conf.rb, which EngineHelper boots, prints its name.
      assert_equal "love.conf\n1\n", output.text
      committed, _completed, failed, waited, not_completed = SUMMARY.match(output.diagnostics)&.captures&.map(&:to_i)

      assert_operator committed, :>=, 1, output.diagnostics
      assert_operator waited, :>=, 1, output.diagnostics
      assert_equal [0, 0], [failed, not_completed], output.diagnostics
    end

    # Metal fails a command buffer only when the GPU does, which no program
    # can make it do on purpose, so the test reports what the watch's
    # wrappers would have seen. A buffer is reported unless it completed
    # without an error, whether its completed handler or a wait saw it end.
    def test_a_command_buffer_that_did_not_complete_is_reported_with_its_status_and_error
      output = watched(<<~RUBY)
        LotaNativeTest.check_metal_command_buffer(false, 4, 0)
        LotaNativeTest.check_metal_command_buffer(false, 5, 2)
        LotaNativeTest.check_metal_command_buffer(true, 4, 0)
        LotaNativeTest.check_metal_command_buffer(true, 4, 3)
        LotaNativeTest.check_metal_command_buffer(true, 3, 0)
        puts "checked"
      RUBY
      reports = output.diagnostics.lines

      assert_predicate output.status, :success?, output.text + output.diagnostics
      assert_equal "checked\n", output.text
      assert_equal 4, reports.size, output.diagnostics
      assert_match(/\Alota-metal-watch: a committed command buffer ended with status 5 \(error\), error: Error Domain=MTLCommandBufferErrorDomain Code=2 "a failure the test reported"/,
        reports[0])
      assert_match(/\Alota-metal-watch: a command buffer waited on ended with status 4 \(completed\), error: Error Domain=MTLCommandBufferErrorDomain Code=3 /,
        reports[1])
      assert_equal "lota-metal-watch: a command buffer waited on ended with status 3 (scheduled), error: none\n",
        reports[2]
      assert_equal "lota-metal-watch: 0 command buffers committed, 1 completed, 1 failed; 3 waited on, " \
        "2 of them not completed\n", reports[3]
    end

    # Exit-time code may still ask Metal for a device after the watch's
    # own first call has registered whatever C++ destroys at exit, as the
    # frameworks a game links may (the handler registered first runs
    # last). The watch keeps working through the end of the process.
    def test_a_device_made_as_the_process_exits_is_watched_like_any_other
      output = watched(<<~RUBY)
        LotaNativeTest.create_metal_device_at_exit
        LotaNativeTest.create_metal_device
        puts "made"
      RUBY

      assert_predicate output.status, :success?, output.text + output.diagnostics
      assert_equal "made\n", output.text
      assert_equal "lota-metal-watch: 0 command buffers committed, 0 completed, 0 failed; 0 waited on, " \
        "0 of them not completed\n", output.diagnostics
    end
  end

  def test_the_watch_is_loaded_only_where_the_engine_draws_with_metal
    assert_equal TestHome::LINUX ? [] : [File.join(Parity::LIB, "liblota_metal_watch.dylib")], Parity::METAL_WATCH
    assert_equal TestHome::LINUX, Parity.loopback("audio").values.none? { |value| value.include?("metal_watch") }
  end
end
