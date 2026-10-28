# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "parity_helper"

# The folders the parity harness keeps its runs in (Parity.directory) are
# gone once the test run that made them ends, whether its tests passed or
# failed, so a run's frames do not pile up in the temporary directory.
class DirectoryTest < Minitest::Test
  # A test run of its own: two tests that each run LÖVE for two frames of
  # the arkanoid tutorial's first snapshot in a folder of their own, and
  # print it, one passing and one failing.
  RUN = <<~RUBY
    require "minitest/autorun"
    require #{File.join(__dir__, 'parity_helper').dump}

    class RunsLove < Minitest::Test
      SCRIPT = Parity::Script.new(frames: 2, fps: 60, holds: [])

      def run_love
        run = Parity::LoveRun.new(File.join(Parity::ARKANOID, "1-01_TheBallTheBrickThePlatform"), SCRIPT,
          Parity.directory)
        puts "folder: \#{File.dirname(run.frames_dir)}"
        run
      end

      def test_passes = assert_equal(2, run_love.frames.size)
      def test_fails = flunk(run_love.frames.size.to_s)
    end
  RUBY

  def test_a_test_runs_folders_are_removed_when_it_ends_whether_it_passed_or_failed
    output, status = Open3.capture2e(RbConfig.ruby, "-e", RUN, "--", "--seed", "1")
    folders = output.scan(/folder: (\S+)/).flatten

    assert_equal 1, status.exitstatus, output
    assert_match(/2 runs, \d+ assertions, 1 failures, 0 errors/, output)
    assert_equal 2, folders.size, output
    folders.each { |folder| assert_equal Dir.tmpdir, File.dirname(folder) }
    assert_empty folders.select { |folder| File.exist?(folder) }
    assert_empty Dir.glob(File.join(Dir.tmpdir, "lota-parity-*-#{status.pid}-*"))
  end
end
