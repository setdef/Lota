# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/version"

class VersionTest < Minitest::Test
  def test_version_is_a_semantic_version
    assert_match(/\A\d+\.\d+\.\d+(?:\.pre\.\d+)?\z/, Lota::VERSION)
  end
end
