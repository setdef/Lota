# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# A generated binding reads its arguments in the statements LÖVE reads
# them in, so the error a game meets for a call with several mistakes is
# the one LÖVE raises first (tasks/bindings/port.rb, Port#hoisted).
class ArgumentOrderTest < Minitest::Test
  def setup
    EngineHelper.open_window
  end

  # w_setDepthMode reads the compare mode's name and then the write flag,
  # and only then checks the name (wrap_Graphics.cpp:2884-2901), so a
  # missing flag is named before an unknown mode.
  def test_a_missing_argument_is_named_before_an_unknown_name_that_lovee_checks_later
    error = assert_raises(ArgumentError) { Lota::Graphics.depth_mode = :sometimes }

    assert_equal "Missing argument. Name: write.", error.message
  end
end
