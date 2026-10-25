# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/package_check"

# What PackageCheck reads from a compiled bundle and from dyld, checked on
# rake compile's bundle, whose rpaths point into vendor/.
class PackageCheckTest < Minitest::Test
  include TreeHelper

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

  # From lib/, SDL3 resolves into vendor/, outside the directory a gem
  # would be; from the repository root, it resolves inside.
  def test_a_library_that_resolves_outside_the_gem_escapes_it
    assert_equal ["@rpath/SDL3.framework/Versions/A/SDL3 resolves outside #{File.join(ROOT, 'lib')}"],
      PackageCheck.escapes(BUNDLE, File.join(ROOT, "lib"))
    assert_empty PackageCheck.escapes(BUNDLE, ROOT)
  end

  def test_a_library_no_rpath_resolves_escapes_the_gem
    in_tree do |dir|
      FileUtils.cp(BUNDLE, dir)

      assert_equal ["@rpath/SDL3.framework/Versions/A/SDL3 resolves outside #{dir}"],
        PackageCheck.escapes(File.join(dir, File.basename(BUNDLE)), dir)
    end
  end

  def test_dyld_loaded_reads_what_dyld_print_libraries_reports
    output = "dyld[1]: <4E21E109-7AF9-3222-97EA-BFD99EAEEC19> /usr/bin/ruby\nwindow 800x600\n" \
      "dyld[1]: <B9EBCD53-332C-3CF1-A6F2-627AD367856C> /gems/SDL3.framework/Versions/A/SDL3\n"

    assert_equal ["/usr/bin/ruby", "/gems/SDL3.framework/Versions/A/SDL3"], PackageCheck.dyld_loaded(output)
  end

  def test_otool_failures_raise
    error = assert_raises(PackageCheck::Failure) { PackageCheck.otool("-L", "/no/such/bundle") }

    assert_includes error.message, "otool -L /no/such/bundle failed"
  end
end
