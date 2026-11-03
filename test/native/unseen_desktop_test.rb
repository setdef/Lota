# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../lovetest/unseen_desktop"
require_relative "../lovetest/tests/window"

# LOTA_DESKTOP_UNSEEN (test/lovetest/unseen_desktop.rb): which runs it
# turns on, what it adds to the skips the gate counts, and that Lövetest's
# isOccluded test skips under it.
class UnseenDesktopTest < Minitest::Test
  MACOS = "arm64-darwin27"
  LINUX = "aarch64-linux"

  def test_it_is_on_only_when_set_to_1_on_macos
    assert UnseenDesktop.on?(env: { "LOTA_DESKTOP_UNSEEN" => "1" }, platform: MACOS)
    refute UnseenDesktop.on?(env: { "LOTA_DESKTOP_UNSEEN" => "1" }, platform: LINUX)
    refute UnseenDesktop.on?(env: { "LOTA_DESKTOP_UNSEEN" => "0" }, platform: MACOS)
    refute UnseenDesktop.on?(env: { "LOTA_DESKTOP_UNSEEN" => "yes" }, platform: MACOS)
    refute UnseenDesktop.on?(env: {}, platform: MACOS)
  end

  def test_it_adds_one_skip_only_when_on
    assert_equal 8, UnseenDesktop.skips(7, env: { "LOTA_DESKTOP_UNSEEN" => "1" }, platform: MACOS)
    assert_equal 14, UnseenDesktop.skips(14, env: { "LOTA_DESKTOP_UNSEEN" => "1" }, platform: LINUX)
    assert_equal 7, UnseenDesktop.skips(7, env: {}, platform: MACOS)
  end

  # The test's own body skips, with the switch's reason, before it asks
  # anything of the window, on macOS; under X11 the switch changes nothing.
  def test_lovetests_is_occluded_test_skips_when_on
    before = ENV.fetch("LOTA_DESKTOP_UNSEEN", nil)
    ENV["LOTA_DESKTOP_UNSEEN"] = "1"
    if TestHome::LINUX
      refute_predicate UnseenDesktop, :on?
    else
      skipped = assert_raises(Minitest::Skip) { WindowTest.new("test_is_occluded").test_is_occluded }
      assert_equal UnseenDesktop::REASON, skipped.message
    end
  ensure
    ENV["LOTA_DESKTOP_UNSEEN"] = before
  end
end
