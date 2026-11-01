# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tmpdir"

# A lock across every process on the computer, for the moments a window
# takes keyboard focus. Only one window has focus, so a test that needs it
# (Lövetest's love.mouse.setGrabbed test passes only for the window with
# focus) fails if another process takes it away, and the gate's checks run
# at the same time (tasks/gate.rb). Windows that stay in the background
# take none, so only those that take focus wait for each other.
module FocusLock
  # The file the processes lock.
  PATH = File.join(Dir.tmpdir, "lota-focus.lock")

  # Waits for the lock, runs the block holding it, and lets go. The
  # operating system lets go of it if the process dies.
  def self.hold(path: PATH)
    lock = acquire(path:)
    yield
  ensure
    release(lock) if lock
  end

  # Takes the lock, to be given back by #release, for a test whose setup
  # and teardown are separate methods. Returns the lock.
  def self.acquire(path: PATH)
    File.open(path, File::RDWR | File::CREAT, 0o600).tap { |file| file.flock(File::LOCK_EX) }
  end

  # Gives back what #acquire took.
  def self.release(lock) = lock.close
end
