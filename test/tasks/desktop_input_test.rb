# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require "stringio"
require "timeout"
require_relative "../../tasks/desktop_input"

# The desktop input lock and what it says, in real processes, over a lock
# and marker of each test's own, with say replaced by a script that writes
# down what it was given to say.
class DesktopInputTest < Minitest::Test
  include TreeHelper

  SETTLE = 0.3

  # What every process's script starts with: the DesktopInput of the tree
  # given as its first argument, speaking as macOS outside CI would.
  PRELUDE = <<~RUBY
    require #{File.join(ROOT, 'tasks/desktop_input').dump}
    dir = ARGV.fetch(0)
    input = DesktopInput.new(lock: File.join(dir, "lock"), marker: File.join(dir, "away"),
      say: File.join(dir, "say"), osascript: File.join(dir, "osascript"), settle: #{SETTLE}, env: {},
      host_os: "darwin")
    def waiting?(name)
      File.read(File.join(ARGV.fetch(0), name)).include?(DesktopInput::WAITING)
    rescue Errno::ENOENT
      false
    end
    def hand_over_to(name) = (sleep 0.01 until waiting?(name))
  RUBY

  def in_desktop
    in_tree do |root|
      say = write(root, "say", "#!/bin/sh\nprintf 'say: %s\\n' \"$1\" >> \"#{root}/said\"\n")
      banner = write(root, "osascript", "#!/bin/sh\nprintf 'osascript %s %s\\n' \"$1\" \"$2\" >> \"#{root}/said\"\n")
      File.chmod(0o755, say)
      File.chmod(0o755, banner)
      yield root
    end
  end

  # Starts a process running +code+ after PRELUDE, its standard error, and
  # so whether it waits for the lock, in the file +err+ names.
  def spawn_script(root, code, err: nil)
    spawn(RbConfig.ruby, "-e", "#{PRELUDE}\n#{code}", root, err: err ? File.join(root, err) : File::NULL)
  end

  def run_script(root, code, err: nil) = reap(spawn_script(root, code, err:))

  # Waits for the process +pid+ to end, killing it if it has not in ten
  # seconds, so that a test that fails leaves nothing running.
  def reap(pid)
    Timeout.timeout(10) { Process.wait(pid) }
  rescue Timeout::Error
    Process.kill(:KILL, pid)
    Process.wait(pid)
    raise
  end

  # What the person is shown and told of +words+, in order: each first as
  # a banner, then aloud.
  def told(*words)
    words.flat_map { |text| ["osascript -e display notification #{text.dump} with title \"Tests\"", "say: #{text}"] }
  end

  def said(root) = File.exist?(File.join(root, "said")) ? File.readlines(File.join(root, "said"), chomp: true) : []

  def input(root, **)
    DesktopInput.new(lock: File.join(root, "lock"), marker: File.join(root, "away"), say: File.join(root, "say"),
      osascript: File.join(root, "osascript"), settle: SETTLE, env: {}, host_os: "darwin", log: StringIO.new, **)
  end

  def wait_for(path) = wait_until { File.exist?(path) }

  def wait_until(&) = Timeout.timeout(5) { sleep 0.01 until yield }

  # The second process's span waits for the first's and starts as soon as
  # it ends, so the person is asked to step away once and to come back
  # once, after both.
  def test_two_processes_say_each_once
    in_desktop do |root|
      first = spawn_script(root, "input.hold { File.write(File.join(dir, 'first'), ''); hand_over_to('second') }; " \
        "sleep #{SETTLE * 2}")
      wait_for(File.join(root, "first"))
      run_script(root, "input.hold { sleep 0.5 }", err: "second")
      reap(first)

      assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK), said(root)
      refute_path_exists File.join(root, "away")
    end
  end

  # A process that settles while another, silent, holds the lock says
  # nothing, since someone is still working, and asks the person back
  # once the lock is free, without waiting to exit.
  def test_a_silent_span_holding_the_lock_only_delays_the_call_back
    in_desktop do |root|
      speaker = spawn_script(root, "input.hold { File.write(File.join(dir, 'spoke'), ''); hand_over_to('silent') }; " \
        "sleep 0.1 until File.exist?(File.join(dir, 'free'))")
      begin
        wait_for(File.join(root, "spoke"))
        run_script(root, "input.hold(speak: false) { sleep #{SETTLE * 3} }", err: "silent")

        assert_equal told(DesktopInput::STEP_AWAY), said(root)
        wait_until { said(root).size == 4 }

        assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK), said(root)
      ensure
        File.write(File.join(root, "free"), "")
        reap(speaker)
      end

      assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK), said(root)
    end
  end

  # A process that exits as soon as it lets go leaves the lock to one
  # already waiting for it, held up here so that the exiting one would
  # get there first, and so leaves the call back to that one.
  def test_a_process_exiting_as_it_lets_go_leaves_the_call_back_to_one_waiting
    in_desktop do |root|
      first = spawn_script(root, "input.hold { File.write(File.join(dir, 'first'), ''); hand_over_to('second') }; " \
        "File.write(File.join(dir, 'released'), '')")
      wait_for(File.join(root, "first"))
      second = spawn_script(root, "input.hold { sleep #{SETTLE * 3} }", err: "second")
      begin
        wait_until { File.exist?(File.join(root, "second")) && File.read(File.join(root, "second")).include?(DesktopInput::WAITING) }
        Process.kill(:STOP, second)
        wait_for(File.join(root, "released"))
        sleep SETTLE / 3
      ensure
        Process.kill(:CONT, second)
      end
      reap(first)
      reap(second)

      assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK), said(root)
    end
  end

  # The lock and the marker are ones every user can open and rewrite,
  # whatever the umask of the process that made them.
  def test_the_files_it_makes_are_every_users_whatever_the_umask
    in_desktop do |root|
      pid = spawn(RbConfig.ruby, "-e", "#{PRELUDE}\ninput.hold { File.write(File.join(dir, 'mode'), " \
        "File.stat(File.join(dir, 'away')).mode & 0o777) }", root, umask: 0o022)
      reap(pid)

      assert_equal 0o666, File.stat(File.join(root, "lock")).mode & 0o777
      assert_equal 0o666, Integer(File.read(File.join(root, "mode")))
    end
  end

  # A process that settles while another holds the lock leaves it to that
  # one to ask the person back.
  def test_a_process_that_settles_while_another_works_says_nothing
    in_desktop do |root|
      first = spawn_script(root, "input.hold { File.write(File.join(dir, 'first'), ''); hand_over_to('second') }; " \
        "sleep #{SETTLE * 3}")
      wait_for(File.join(root, "first"))
      run_script(root, "input.hold { sleep #{SETTLE * 6} }", err: "second")

      assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK), said(root)
      reap(first)

      assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK), said(root)
    end
  end

  # A marker whose process is gone was left by one that died before asking
  # the person back, so the person is asked again, and the marker is this
  # process's.
  def test_a_marker_left_by_a_dead_process_is_replaced
    in_desktop do |root|
      dead = spawn("true")
      Process.wait(dead)
      File.write(File.join(root, "away"), "#{dead} 0")
      run_script(root, "input.hold { File.write(File.join(dir, 'held'), File.read(File.join(dir, 'away'))) }")

      assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK), said(root)
      refute_equal dead, Integer(File.read(File.join(root, "held")).split.first)
    end
  end

  # A marker naming no process at all is as stale as one whose process is
  # gone.
  def test_a_marker_naming_no_process_is_replaced
    in_desktop do |root|
      File.write(File.join(root, "away"), "0 0")
      run_script(root, "input.hold { }")

      assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK), said(root)
    end
  end

  # Spans nest, and the process lets go of the lock only when the last
  # ends, without waiting on the lock it already holds.
  def test_spans_nest_and_the_last_lets_go
    in_desktop do |root|
      outer = input(root).acquire(speak: false)
      Timeout.timeout(1) { outer.hold(speak: false) { nil } }

      assert_equal "#{DesktopInput::WAITING}\nwaited\n", try_from_another_process(root)

      outer.release

      assert_equal "got it\n", try_from_another_process(root)
    end
  end

  # A marker whose process lives means the person was asked already.
  def test_a_marker_of_a_live_process_keeps_it_quiet
    in_desktop do |root|
      File.write(File.join(root, "away"), "#{Process.pid} 0")
      run_script(root, "input.hold { }")

      assert_equal told(DesktopInput::COME_BACK), said(root)
    end
  end

  def test_a_silent_span_says_nothing_and_leaves_the_marker_alone
    in_desktop do |root|
      threads = Thread.list.size
      input(root).hold(speak: false) { nil }

      refute_path_exists File.join(root, "away")
      File.write(File.join(root, "away"), "1 0")
      input(root).hold(speak: false) { nil }

      assert_equal "1 0", File.read(File.join(root, "away"))
      assert_empty said(root)
      assert_equal threads, Thread.list.size
    end
  end

  def test_it_speaks_only_on_macos_outside_ci_unless_quieted
    in_desktop do |root|
      assert_predicate input(root), :speaks?
      refute_predicate input(root, env: { "CI" => "true" }), :speaks?
      refute_predicate input(root, env: { "DESKTOP_INPUT_QUIET" => "" }), :speaks?
      refute_predicate input(root, host_os: "linux-gnu"), :speaks?
    end
  end

  # Without say, the person still sees the banners.
  def test_without_say_it_only_shows
    in_desktop do |root|
      File.delete(File.join(root, "say"))
      run_script(root, "input.hold { }")

      assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK).grep(/\Aosascript/), said(root)
    end
  end

  # A banner that cannot be shown, as where notifications are denied,
  # fails nothing, and the words are still said.
  def test_a_banner_that_fails_fails_nothing
    in_desktop do |root|
      write(root, "osascript", "#!/bin/sh\nexit 1\n")
      run_script(root, "input.hold { File.write(File.join(dir, 'ran'), '') }")

      assert_path_exists File.join(root, "ran")
      assert_equal told(DesktopInput::STEP_AWAY, DesktopInput::COME_BACK).grep(/\Asay/), said(root)
    end
  end

  # Where it would not speak, a speaking span is a silent one.
  def test_a_quiet_span_says_nothing
    in_desktop do |root|
      input(root, env: { "DESKTOP_INPUT_QUIET" => "1" }).hold { nil }

      assert_empty said(root)
      refute_path_exists File.join(root, "away")
    end
  end

  # What another process says of the lock: that it got it within a
  # second, or, having said it was waiting, that it waited.
  def try_from_another_process(root)
    script = "#{PRELUDE}\nrequire 'timeout'\n" \
      "begin; Timeout.timeout(1) { input.hold(speak: false) { } }; puts 'got it'; " \
      "rescue Timeout::Error; puts 'waited'; end"
    Open3.capture2e(RbConfig.ruby, "-e", script, root).first
  end

  # Another process waits while this one holds the lock, saying so once,
  # and goes on when this one lets go.
  def test_a_process_waits_for_the_process_holding_the_lock
    in_desktop do |root|
      held = input(root).acquire(speak: false)

      assert_equal "#{DesktopInput::WAITING}\nwaited\n", try_from_another_process(root)

      held.release

      assert_equal "got it\n", try_from_another_process(root)
    end
  end

  def test_hold_gives_the_lock_back_when_the_block_raises
    in_desktop do |root|
      assert_raises(RuntimeError) { input(root).hold(speak: false) { raise "boom" } }

      Timeout.timeout(1) { input(root).hold(speak: false) { nil } }
    end
  end

  # The lock and marker are the ones every project following the protocol
  # shares, and the lock is one any user can open.
  def test_every_process_shares_the_same_files
    assert_equal "/tmp/desktop-input.lock", DesktopInput::LOCK
    assert_equal "/tmp/desktop-input.away", DesktopInput::MARKER
    assert_equal 3, DesktopInput::SETTLE
  end
end
