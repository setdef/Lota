# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/ruby_stamp"

# RubyStamp records the Ruby that runs rake, in a real folder, and
# rewrites the record only when another Ruby runs it, so that the
# extension's Makefiles, which depend on it, are configured again then.
class RubyStampTest < Minitest::Test
  include TreeHelper

  OLD = "/home/agent/.local/share/mise/installs/ruby/4.1.0-preview1/bin/ruby"
  NEW = "/home/agent/workspaces/lota/mise/0123456789abcdef/installs/ruby/4.1.0-preview1/bin/ruby"

  def test_a_tree_with_no_record_gets_one
    in_tree do |dir|
      stamp = RubyStamp.new(tmp: File.join(dir, "tmp"), ruby: OLD)

      assert_equal :recorded, stamp.refresh
      assert_equal OLD, File.read(stamp.path)
    end
  end

  def test_the_same_ruby_keeps_the_record_as_it_was
    in_tree do |dir|
      stamp = RubyStamp.new(tmp: File.join(dir, "tmp"), ruby: OLD)
      stamp.refresh
      File.utime(Time.at(0), Time.at(0), stamp.path)

      assert_equal :kept, stamp.refresh
      assert_equal Time.at(0), File.mtime(stamp.path)
    end
  end

  def test_another_ruby_of_the_same_version_rewrites_the_record
    in_tree do |dir|
      tmp = File.join(dir, "tmp")
      RubyStamp.new(tmp:, ruby: OLD).refresh
      makefile = write(tmp, "x86_64-linux/lota/native/4.1.0/Makefile", "configured for the old Ruby")
      File.utime(Time.at(0), Time.at(0), File.join(tmp, RubyStamp::FILE))
      File.utime(Time.at(1), Time.at(1), makefile)
      stamp = RubyStamp.new(tmp:, ruby: NEW)

      assert_equal :recorded, stamp.refresh
      assert_equal NEW, File.read(stamp.path)
      assert_operator File.mtime(stamp.path), :>, File.mtime(makefile)
    end
  end
end
