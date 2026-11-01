# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require "timeout"
require_relative "../../tasks/focus_lock"

class FocusLockTest < Minitest::Test
  include TreeHelper

  # Another process waits while this one holds the lock, and goes on when
  # this one lets go.
  def test_a_process_waits_for_the_process_holding_the_lock
    in_tree do |root|
      path = File.join(root, "focus.lock")
      script = "require 'timeout'; require '#{File.join(ROOT, 'tasks/focus_lock')}'; " \
        "begin; Timeout.timeout(1) { FocusLock.hold(path: '#{path}') { } }; puts 'got it'; " \
        "rescue Timeout::Error; puts 'waited'; end"
      held = FocusLock.acquire(path:)
      out, = Open3.capture2e(RbConfig.ruby, "-e", script)

      assert_equal "waited\n", out

      FocusLock.release(held)
      out, = Open3.capture2e(RbConfig.ruby, "-e", script)

      assert_equal "got it\n", out
    end
  end

  def test_hold_gives_the_lock_back_when_the_block_raises
    in_tree do |root|
      path = File.join(root, "focus.lock")

      assert_raises(RuntimeError) { FocusLock.hold(path:) { raise "boom" } }

      Timeout.timeout(1) { FocusLock.release(FocusLock.acquire(path:)) }
    end
  end
end
