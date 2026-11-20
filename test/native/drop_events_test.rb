# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"

# Lota::Native.check_drop_events asks, as LÖVE's main asks before LÖVE
# boots (src/love.cpp:105-120), for the file macOS opened the program
# with, which arrives as an Apple event that SDL turns into a drop
# (src/common/macos.mm:57-85). A test process is opened with no file, so
# there is none; elsewhere than macOS there never is. Opening a file with
# an app takes Launch Services and a desktop, which no test here drives.
class DropEventsTest < Minitest::Test
  include NativeHelper

  def test_a_program_opened_with_no_file_has_no_dropped_path
    assert_equal "", Lota::Native.check_drop_events
    assert_equal "", Lota::Native.check_drop_events, "asking again starts and stops SDL's video again"
  end
end
