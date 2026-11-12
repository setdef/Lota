# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "lota/notices"

# What lota.gemspec publishes agrees with what Lota says of itself. The
# gemspec lists the gem's files with git ls-files, so loading it starts a
# process, and these are integration tests; the unit tests of the version,
# the notices, and the phone hosts are beside them.
class GemspecTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def spec
    @spec ||= Gem::Specification.load(File.join(ROOT, "lota.gemspec"))
  end

  def test_gemspec_publishes_the_library_version
    assert_equal Lota::VERSION, spec.version.to_s
  end

  # The notices name the license and the source the gemspec gives.
  def test_the_notices_name_the_license_and_source_the_gemspec_gives
    assert_equal spec.license, Lota::Notices::LICENSE
    assert_equal spec.metadata.fetch("source_code_uri"), Lota::Notices::SOURCE
  end

  # The phone hosts in ext/lota/phone/host, which a game's Fledge project
  # names in fledge.yml, reach a game only if the gem carries them.
  def test_the_gem_carries_each_phone_host_file
    host = File.join(ROOT, "ext/lota/phone/host")
    hosts = Dir.glob("**/*", base: host).select { |path| File.file?(File.join(host, path)) }

    assert_operator hosts.size, :>=, 5
    hosts.each { |path| assert_includes spec.files, "ext/lota/phone/host/#{path}" }
  end
end
