# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "held_foreground"

# LOTA_FOREGROUND_HELD (test/lovetest/held_foreground.rb): which runs it
# turns on, and what it adds to the skips a run counts.
class HeldForegroundTest < Minitest::Test
  WINDOWS = "aarch64-mingw-ucrt"
  MACOS = "arm64-darwin27"

  def test_it_is_on_only_when_set_to_1_on_windows
    assert HeldForeground.on?(env: { "LOTA_FOREGROUND_HELD" => "1" }, platform: WINDOWS)
    refute HeldForeground.on?(env: { "LOTA_FOREGROUND_HELD" => "1" }, platform: MACOS)
    refute HeldForeground.on?(env: { "LOTA_FOREGROUND_HELD" => "0" }, platform: WINDOWS)
    refute HeldForeground.on?(env: {}, platform: WINDOWS)
  end

  def test_it_adds_one_skip_only_when_on
    assert_equal 11, HeldForeground.skips(10, env: { "LOTA_FOREGROUND_HELD" => "1" }, platform: WINDOWS)
    assert_equal 10, HeldForeground.skips(10, env: {}, platform: WINDOWS)
  end
end
