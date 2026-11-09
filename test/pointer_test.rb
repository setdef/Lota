# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"
require "rbconfig"

# Lota::Pointer, which makes Lota's raw pointers Fiddle's. Lota does not
# depend on the fiddle gem, so a game without it in its Gemfile is told
# what to add, and test/native/data_test.rb and window_queries_test.rb
# check the pointers themselves.
class PointerTest < Minitest::Test
  # Fiddle keeps a size only for an address that is not null, so this
  # one is an address nothing reads through.
  def test_a_pointer_is_fiddles_at_the_address_with_the_size
    pointer = Lota::Pointer.at(4096, 16)

    assert_instance_of Fiddle::Pointer, pointer
    assert_equal 4096, pointer.to_i
    assert_equal 16, pointer.size
    assert_equal 0, Lota::Pointer.at(4096).size
    assert_predicate Lota::Pointer.at(0), :null?
  end

  # A process where Fiddle will not load, as in a bundle without it: its
  # require of fiddle raises LoadError, as Bundler's does.
  def test_without_fiddle_the_error_says_to_add_it_to_the_gemfile
    script = <<~RUBY
      module Kernel
        alias_method :lota_test_require, :require
        def require(name)
          raise LoadError, "cannot load such file -- fiddle" if name == "fiddle"

          lota_test_require(name)
        end
      end
      require #{File.expand_path('../lib/lota/pointer', __dir__).dump}
      begin
        Lota::Pointer.at(0)
      rescue LoadError => e
        print e.message
      end
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, "-e", script)

    assert_predicate status, :success?, output
    assert_equal "#{Lota::Pointer::MISSING} (cannot load such file -- fiddle)", output
    assert_includes output, 'Add gem "fiddle" to your Gemfile'
  end
end
