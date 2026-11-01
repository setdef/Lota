# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "monitor"
require "rbconfig"

# The desktop's keyboard and mouse, shared by every process on the computer
# that needs them, Lota's and other projects' alike. Only one window has
# keyboard focus and there is one pointer, so a test that takes focus or
# moves the pointer fails if another process takes them in the meantime,
# and the gate's checks run at the same time (tasks/gate.rb).
#
# It follows a protocol agreed with the other projects whose tests share
# the computer, which Tokra implements the same way (its Plan 046,
# KeyboardNotice::Desk):
#
# - The lock is an exclusive +flock+ on LOCK, held only around each span
#   that needs the keyboard or the pointer, so the system frees it if the
#   process dies. Taking it blocks, after printing WAITING.
# - A speaking span, on taking the lock, finds no marker at MARKER, or one
#   naming a process that has ended, writes its own process id and the
#   time there, and says STEP_AWAY. A marker naming a live process means
#   someone has already warned.
# - Once SETTLE seconds pass with none of its spans running, a process that
#   held a speaking span tries the lock without waiting. If it gets it and
#   the marker is there, it removes the marker and says COME_BACK. If the
#   lock is busy, it tries again at each poll until it calls back or finds
#   the marker gone, so a busy lock only delays the call back.
# - On exit it first waits out the rest of SETTLE from its last release,
#   so a process blocked waiting for the lock takes it first, then tries
#   once more.
# - Both files are made mode 0666 whatever the umask, so every user's
#   processes can open the lock and rewrite the marker.
# - A silent span takes the same lock, but never speaks, never writes or
#   removes the marker, and starts no watcher.
#
# A speaking span speaks only on macOS, outside CI, and unless
# DESKTOP_INPUT_QUIET is set; elsewhere it is a silent one. Each thing it
# says it first shows as a Notification Center banner, which takes no
# focus, for a person whose sound is off, then says with macOS's own say
# if it is there. Neither fails the span if it cannot be shown or said.
#
# Two edges are left for the gem the projects mean to share: a retrying
# watcher can find the lock free in the gap between another process's
# spans and call the person back while that process still has more to
# do, and a person of another user cannot delete a marker left in /tmp,
# whose sticky bit keeps each user's files their own.
#
# Spans nest, and spans on several threads of one process share the one
# lock held while any runs, since a second +flock+ from the same process,
# on a descriptor of its own, would wait on the first forever.
class DesktopInput
  # The file every process locks: literally /tmp, not Dir.tmpdir, which
  # differs between processes on macOS.
  LOCK = "/tmp/desktop-input.lock"
  # The file that says the person was told to step away, holding "<pid>
  # <unix time>" of the process that told them.
  MARKER = "/tmp/desktop-input.away"
  # macOS's speech synthesizer.
  SAY = "/usr/bin/say"
  # What shows a Notification Center banner.
  OSASCRIPT = "/usr/bin/osascript"
  # Seconds with no span running before the person is called back.
  SETTLE = 3
  # What the first speaking span says.
  STEP_AWAY = "Tests need the keyboard and mouse for a moment. Please step away."
  # What is said once no one needs them.
  COME_BACK = "The tests are done with the keyboard and mouse. You can come back now."
  # What a span that has to wait for the lock prints first.
  WAITING = "waiting for the desktop input lock"

  # [lock] The file locked.
  # [marker] The file that says the person was told to step away.
  # [say] The speech synthesizer, given the words to say.
  # [osascript] What runs the AppleScript that shows the banner.
  # [settle] Seconds with no span running before COME_BACK.
  # [env] The environment that can quiet it (CI, DESKTOP_INPUT_QUIET).
  # [host_os] The operating system, which speaks only when it is macOS.
  # [log] Where WAITING is printed.
  def initialize(lock: LOCK, marker: MARKER, say: SAY, osascript: OSASCRIPT, settle: SETTLE, env: ENV,
    host_os: RbConfig::CONFIG["host_os"], log: $stderr
  )
    @lock = lock
    @marker = marker
    @say = say
    @osascript = osascript
    @settle = settle
    @env = env
    @host_os = host_os
    @log = log
    @state = Monitor.new
    @depth = 0
    @file = nil
    @pending = false
    @last_done = nil
    @watcher = nil
  end

  # Runs the block holding the lock, as a speaking span unless +speak+ is
  # false, and lets go, even if the block raises.
  def hold(speak: true)
    acquire(speak:)
    begin
      yield
    ensure
      release
    end
  end

  # Takes the lock, to be given back by #release, for a test whose setup
  # and teardown are separate methods. Returns this DesktopInput.
  #
  # Here alone Lota differs from Tokra, which takes the lock only on macOS
  # outside CI, where its tests could collide with another project's: Lota
  # takes it everywhere, CI and Linux among them, since its own lanes run
  # at the same time there too, and move the pointer under each other's
  # tests on a display they share. Speaking stays where Tokra's does.
  def acquire(speak: true)
    speak &&= speaks?
    @state.synchronize do
      take if @depth.zero?
      @depth += 1
      announce if speak
    end
    self
  end

  # Gives back what #acquire took, letting go of the lock once no span of
  # this process holds it.
  def release
    @state.synchronize do
      @depth -= 1
      @last_done = now
      next unless @depth.zero?

      @file.close
      @file = nil
    end
  end

  # Whether a speaking span speaks here: on macOS, outside CI, and unless
  # DESKTOP_INPUT_QUIET is set.
  def speaks?
    @host_os.include?("darwin") && @env["CI"].nil? && @env["DESKTOP_INPUT_QUIET"].nil?
  end

  # Calls the person back, once SETTLE seconds have passed since the last
  # span of this process ended, if a speaking span has run since the last
  # call. While the lock is busy and the marker is there, it tries again
  # at the next call. The watcher polls it.
  def tick
    @state.synchronize do
      next unless @pending && @depth.zero?
      next if now - @last_done < @settle

      @pending = come_back == :busy
    end
  end

  # Calls the person back if no one holds the lock and the marker says
  # they were sent away. Never waits for the lock. Returns +:called+,
  # +:busy+ when someone holds the lock and the marker is there, or
  # +:gone+ when the marker is not.
  def call_back
    @state.synchronize { come_back }
  end

  # What a process that held a speaking span does as it exits: stops the
  # watcher, waits out what is left of SETTLE since it last let go of the
  # lock, so a process already waiting for the lock takes it first, and
  # then calls back.
  def finish
    @watcher&.kill&.join
    @watcher = nil
    last_done = @state.synchronize { @last_done }
    left = last_done && (@settle - (now - last_done))
    sleep left if left&.positive?
    call_back
  end

  private def take
    file = open_lock
    begin
      unless file.flock(File::LOCK_EX | File::LOCK_NB)
        @log.puts WAITING
        file.flock(File::LOCK_EX)
      end
      @file = file
    ensure
      file.close unless @file
    end
  end

  private def announce
    step_away unless warned_by_a_live_process?
    @pending = true
    @watcher ||= start_watcher
  end

  private def open_lock
    file = File.open(@lock, File::RDONLY | File::CREAT, 0o666)
    share(@lock)
    file
  end

  private def step_away
    File.write(@marker, "#{Process.pid} #{Time.now.to_i}")
    share(@marker)
    tell(STEP_AWAY)
  end

  # Makes +path+ readable and writable by every user, whatever the umask.
  # A file another user created stays as they made it.
  private def share(path)
    File.chmod(0o666, path)
  rescue Errno::EPERM
    nil
  end

  private def warned_by_a_live_process?
    pid = Integer(File.read(@marker).split.first, exception: false)
    !pid.nil? && pid.positive? && alive?(pid)
  rescue Errno::ENOENT
    false
  end

  private def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  private def start_watcher
    at_exit { finish }
    Thread.new do
      loop do
        sleep [@settle / 4.0, 0.25].min
        tick
      end
    end
  end

  # Holding no lock of its own, looks at the lock on a fresh descriptor.
  private def come_back
    file = open_lock
    begin
      return File.exist?(@marker) ? :busy : :gone unless file.flock(File::LOCK_EX | File::LOCK_NB)
      return :gone unless File.exist?(@marker)

      File.delete(@marker)
      tell(COME_BACK)
      :called
    ensure
      file.close
    end
  end

  # Shows +words+ in a banner, then says them, waiting until they are said.
  private def tell(words)
    system(@osascript, "-e", "display notification #{words.dump} with title \"Tests\"", exception: false)
    system(@say, words, exception: false) if File.executable?(@say)
  end

  private def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # The process's own, which every span in it shares.
  DEFAULT = new

  # DEFAULT's #hold.
  def self.hold(speak: true, &) = DEFAULT.hold(speak:, &)

  # DEFAULT's #acquire.
  def self.acquire(speak: true) = DEFAULT.acquire(speak:)
end
