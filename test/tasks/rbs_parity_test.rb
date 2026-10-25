# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../test_helper"
require_relative "../../tasks/rbs_parity"
require "fileutils"
require "tmpdir"

# RbsParity reads a method called new on a class as its constructor, which
# initialize implements, and on a module as an ordinary module method.
class RbsParityTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @lib = File.join(@root, "lib")
    @sig = File.join(@root, "sig")
    Dir.mkdir(@lib)
    Dir.mkdir(@sig)
  end

  def teardown
    %i[RbsParityModuleWithNew RbsParityModuleWithoutNew RbsParityClassWithInitialize].each do |name|
      Object.__send__(:remove_const, name) if Object.const_defined?(name, false)
    end
    FileUtils.rm_rf(@root)
  end

  # Writes +ruby+ into lib and +rbs+ into sig, loads the Ruby, and returns
  # what RbsParity finds.
  def violations(ruby, rbs)
    file = File.join(@lib, "example.rb")
    File.write(file, ruby)
    File.write(File.join(@sig, "example.rbs"), rbs)
    load file
    RbsParity.new(sig_dirs: [@sig], lib_dirs: [@lib]).violations
  end

  def test_a_module_that_defines_new_matches_its_signature
    found = violations(<<~RUBY, <<~RBS)
      module RbsParityModuleWithNew
        def self.new = 1
      end
    RUBY
      module RbsParityModuleWithNew
        def self.new: () -> Integer
      end
    RBS

    assert_empty found
  end

  def test_a_module_that_declares_new_without_defining_it_is_reported
    found = violations(<<~RUBY, <<~RBS)
      module RbsParityModuleWithoutNew
        def self.other = 1
      end
    RUBY
      module RbsParityModuleWithoutNew
        def self.new: () -> Integer

        def self.other: () -> Integer
      end
    RBS

    assert_equal ["RbsParityModuleWithoutNew.new: declared in sig/ but not defined in lib/"], found
  end

  def test_a_class_whose_initialize_implements_new_matches_its_signature
    found = violations(<<~RUBY, <<~RBS)
      class RbsParityClassWithInitialize
        def initialize(value) = @value = value
      end
    RUBY
      class RbsParityClassWithInitialize
        def self.new: (Integer value) -> RbsParityClassWithInitialize
      end
    RBS

    assert_empty found
  end
end
