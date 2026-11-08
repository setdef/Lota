# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"

# Lota is setdef's. A file that names anyone else as the holder of Lota's
# copyright is a mistake, so this reads every tracked file outside vendor/
# (and outside the fixtures, which are other people's games) and fails on one.
class CopyrightHolderTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  HOLDER = "setdef <kerrick@setdef.com>"
  WRONG = /Kerrick Long|kerricklong\.com/i

  def tracked_files
    out, status = Open3.capture2("git", "ls-files", "-z", chdir: ROOT)
    assert_predicate status, :success?
    out.split("\0")
      .reject { |path| path.start_with?("vendor/", "test/fixtures/") || path == "test/copyright_holder_test.rb" }
      .select { |path| File.file?(File.join(ROOT, path)) }
  end

  def test_no_tracked_file_names_another_copyright_holder
    offenders = tracked_files.flat_map do |path|
      File.binread(File.join(ROOT, path)).lines.each_with_index.filter_map do |line, index|
        "#{path}:#{index + 1}" if line.match?(/copyright/i) && line.match?(WRONG)
      end
    end

    assert_empty offenders, "these lines name someone other than setdef as a copyright holder"
  end

  def test_notices_name_setdef_as_the_holder
    assert_equal "2026 #{HOLDER}", Lota::Notices::COPYRIGHT
  end

  def test_the_readmes_say_whose_copyright_it_is
    assert_includes File.read(File.join(ROOT, "README.md")), "Lota is copyright 2026, setdef."
    assert_includes File.read(File.join(ROOT, "README.rdoc")), "Lota is copyright 2026, setdef,"
  end
end
