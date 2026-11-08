# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"

# .github/phones/privacy_imports.sh, which .github/workflows/phones.yml
# runs on the iOS app's executable: it must fail when the executable
# imports a required reason API of a category the manifest leaves out.
# The test gives the script a text file of symbols in place of an
# executable, with NM=cat, and a real manifest, read by plutil, which
# only macOS has; the script runs there, on the runner.
class PrivacyImportsTest < Minitest::Test
  include TreeHelper

  SCRIPT = File.join(ROOT, ".github/phones/privacy_imports.sh")

  def setup
    skip "plutil is macOS's" unless File.executable?("/usr/bin/plutil")
  end

  def manifest(root, *categories)
    entries = categories.map do |category|
      "<dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategory#{category}</string></dict>"
    end
    write(root, "PrivacyInfo.xcprivacy", <<~PLIST)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict><key>NSPrivacyAccessedAPITypes</key><array>#{entries.join}</array></dict></plist>
    PLIST
  end

  def check(root, symbols, *declared)
    executable = write(root, "App", symbols.join("\n"))
    output, status = Open3.capture2e({ "NM" => "cat" }, "bash", SCRIPT, executable, manifest(root, *declared))
    [output, status]
  end

  def test_passes_when_every_imported_category_is_declared
    in_tree do |root|
      output, status = check(root, %w[_stat _mach_absolute_time _printf], "FileTimestamp", "SystemBootTime")

      assert_predicate status, :success?, output
      assert_includes output, "NSPrivacyAccessedAPICategoryFileTimestamp: imported\n  _stat"
      assert_includes output, "every imported category is declared"
    end
  end

  def test_fails_naming_the_symbol_and_category_when_one_is_not_declared
    in_tree do |root|
      output, status = check(root, %w[_stat _mach_absolute_time _statfs], "FileTimestamp", "SystemBootTime")

      refute_predicate status, :success?
      assert_includes output, "NSPrivacyAccessedAPICategoryDiskSpace: imported\n  _statfs"
      assert_includes output, "imports _statfs for NSPrivacyAccessedAPICategoryDiskSpace"
    end
  end

  def test_fails_on_an_objective_c_class_and_a_constant
    in_tree do |root|
      output, status = check(root, %w[_OBJC_CLASS_$_NSUserDefaults _NSFileSystemFreeSize])

      refute_predicate status, :success?
      assert_includes output, "_OBJC_CLASS_$_NSUserDefaults for NSPrivacyAccessedAPICategoryUserDefaults"
      assert_includes output, "_NSFileSystemFreeSize for NSPrivacyAccessedAPICategoryDiskSpace"
    end
  end

  def test_getattrlist_and_cfpreferences_are_printed_and_do_not_fail
    in_tree do |root|
      output, status = check(root, %w[_getattrlist _CFPreferencesGetAppBooleanValue], "FileTimestamp")

      assert_predicate status, :success?, output
      assert_includes output, "NSPrivacyAccessedAPICategoryDiskSpace: known, not checked\n  _getattrlist"
      assert_includes output, "none: CFPreferences: known, not checked\n  _CFPreferencesGetAppBooleanValue"
    end
  end
end
