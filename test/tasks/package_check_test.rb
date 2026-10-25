# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/package_check"

# PackageCheck's fast mode copies the compiled extension into the unpacked
# gem with whatever it loads through its relative rpaths.
class PackageCheckTest < Minitest::Test
  BUNDLE = File.expand_path("../../lib/lota/native.#{RbConfig::CONFIG['DLEXT']}", __dir__)

  def test_the_extension_needs_sdl_beside_it_through_its_rpath
    assert_equal [
"../../vendor/love-apple-dependencies/shared/Frameworks/SDL3.xcframework/macos-arm64_x86_64/" \
  "SDL3.framework",
], PackageCheck.rpath_dependencies(BUNDLE)
  end

  def test_each_dependency_is_a_framework_directory_that_exists
    PackageCheck.rpath_dependencies(BUNDLE).each do |relative|
      assert File.directory?(File.expand_path(relative, File.dirname(BUNDLE))), relative
    end
  end

  def test_otool_failures_raise
    error = assert_raises(PackageCheck::Failure) { PackageCheck.otool("-L", "/no/such/bundle") }

    assert_includes error.message, "otool -L /no/such/bundle failed"
  end
end
