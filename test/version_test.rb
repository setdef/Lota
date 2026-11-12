# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/version"

# A clone is 0.0.1.dev; a release's gems carry the release's version, which
# CI stamps into lib/lota/version.rb as it builds them
# (doc/contributors/releasing.md).
class VersionTest < Minitest::Test
  def test_version_is_a_release_or_the_development_version
    assert_match(/\A(?:\d+\.\d+\.\d+|0\.0\.1\.dev)\z/, Lota::VERSION)
  end
end
