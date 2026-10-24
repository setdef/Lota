# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class VersionTest < Minitest::Test
  def test_version_is_a_semantic_version
    assert_match(/\A\d+\.\d+\.\d+(?:\.pre\.\d+)?\z/, Lota::VERSION)
  end

  def test_gemspec_publishes_the_library_version
    spec = Gem::Specification.load(File.expand_path("../lota.gemspec", __dir__))

    assert_equal Lota::VERSION, spec.version.to_s
  end
end
