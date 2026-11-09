# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tree_helper"
require_relative "../../tasks/api_diff"

# ApiDiff compares Lota's public API, as sig/ declares it, between two
# trees of signatures. The recorded pairs in fixtures/api_diff are sig/
# files as two of Lota's releases had them, and as trunk had them after.
class ApiDiffTest < Minitest::Test
  include TreeHelper

  FIXTURES = File.expand_path("fixtures/api_diff", __dir__)

  def recorded(name)
    ApiDiff.new(File.join(FIXTURES, name, "before"), File.join(FIXTURES, name, "after"))
  end

  # The ApiDiff of one file of signatures, +before+ and +after+.
  def compare(before, after)
    in_tree do |root|
      write(root, "before/lota.rbs", before)
      write(root, "after/lota.rbs", after)
      ApiDiff.new(File.join(root, "before"), File.join(root, "after"))
    end
  end

  # 0.3.0 renamed Lota::Sensor.get_name to name, and said so with a
  # Breaking: entry.
  def test_a_removed_method_is_a_break
    sensor = recorded("sensor")

    assert_equal ["removed Lota::Sensor.get_name: (::Symbol | ::String sensor_type) -> ::String"], sensor.breaks
    assert_includes sensor.added, "Lota::Sensor.name"
  end

  # After 0.3.1, play, stop, and pause took several Sources or an Array,
  # which widens what each accepts, but pause with no Source was declared
  # to return nil as well as the Array it always returns.
  def test_widened_parameters_are_kept_and_a_widened_return_is_a_change
    audio = recorded("audio")

    assert_equal 1, audio.breaks.size, audio.breaks.join("\n")
    assert_match(/\Achanged Lota::Audio\.pause: \(\) -> ::Array\[(::Lota::Audio::)?Source\] is no longer accepted/, audio.breaks.first)
  end

  # After 0.3.1 each Shape.new also took the deprecated forms without a
  # Body, which widens the first argument and turns required ones into a
  # rest; Fixture is new.
  def test_a_required_argument_that_becomes_part_of_a_wider_rest_is_kept
    shape = recorded("shape")

    assert_empty shape.breaks
    assert_includes shape.added, "Lota::Physics::Fixture"
  end

  # After 0.3.1 ImageData.new took Image's alias file, String |
  # Filesystem::File | Data, where it took Filesystem::FileData | String;
  # a FileData is a Data.
  def test_a_type_alias_and_a_subclass_are_seen_through
    image = recorded("image")

    assert_empty image.breaks
    assert_includes image.added, "Lota::Image.new_cube_faces"
  end

  def test_private_methods_and_names_outside_lota_are_not_its_api
    result = compare(<<~BEFORE, <<~AFTER)
      module Lota
        private def self.helper: () -> nil
        def self.other: () -> nil
        private
        def self.hidden: () -> nil
      end
      module Fiddle
        def self.gone: () -> nil
      end
    BEFORE
      module Lota
        def self.other: () -> nil
      end
    AFTER

    assert_empty result.breaks
  end

  def test_a_renamed_positional_parameter_is_no_change
    assert_empty compare("module Lota\n  def self.f: (Integer a) -> nil\nend\n", "module Lota\n  def self.f: (Integer b) -> nil\nend\n").breaks
  end

  def test_a_narrowed_parameter_is_a_change
    result = compare("module Lota\n  def self.f: (Integer | String a) -> nil\nend\n", "module Lota\n  def self.f: (Integer a) -> nil\nend\n")

    assert_equal 1, result.breaks.size
    assert_match(/\Achanged Lota\.f: \(::Integer \| ::String a\) -> nil is no longer accepted; now \(::Integer a\) -> nil\z/, result.breaks.first)
  end

  def test_a_new_required_argument_is_a_change_and_a_new_optional_one_is_not
    before = "module Lota\n  def self.f: (Integer a) -> nil\nend\n"

    refute_empty compare(before, "module Lota\n  def self.f: (Integer a, Integer b) -> nil\nend\n").breaks
    assert_empty compare(before, "module Lota\n  def self.f: (Integer a, ?Integer b) -> nil\nend\n").breaks
  end

  def test_keywords_are_matched_by_name
    before = "module Lota\n  def self.f: (?size: Integer) -> nil\nend\n"

    refute_empty compare(before, "module Lota\n  def self.f: (?width: Integer) -> nil\nend\n").breaks
    refute_empty compare(before, "module Lota\n  def self.f: (size: Integer) -> nil\nend\n").breaks
    assert_empty compare(before, "module Lota\n  def self.f: (?size: Integer | Float, ?scale: Float) -> nil\nend\n").breaks
  end

  def test_a_narrowed_return_is_kept
    assert_empty compare("module Lota\n  def self.f: () -> Integer?\nend\n", "module Lota\n  def self.f: () -> Integer\nend\n").breaks
  end

  def test_a_block_that_becomes_required_is_a_change
    before = "module Lota\n  def self.f: () ?{ () -> void } -> nil\nend\n"

    refute_empty compare(before, "module Lota\n  def self.f: () { () -> void } -> nil\nend\n").breaks
    assert_empty compare(before, "module Lota\n  def self.f: (?Integer a) ?{ () -> void } -> nil\nend\n").breaks
  end

  def test_removed_constants_classes_and_attributes_are_breaks
    result = compare(<<~BEFORE, <<~AFTER)
      module Lota
        LIMIT: Integer
        class Thing
          attr_reader size: Integer
        end
      end
    BEFORE
      module Lota
      end
    AFTER

    assert_equal ["removed Lota::LIMIT: ::Integer", "removed Lota::Thing: class", "removed Lota::Thing#size: () -> ::Integer"],
      result.breaks
  end

  def test_a_changed_constant_type_is_a_change
    result = compare("module Lota\n  LIMIT: Integer\nend\n", "module Lota\n  LIMIT: String\nend\n")

    assert_equal ["changed Lota::LIMIT: ::Integer is no longer accepted; now ::String"], result.breaks
  end

  def test_initialize_is_the_signature_of_new
    before = "module Lota\n  class Thing\n    def initialize: (Integer a) -> void\n  end\nend\n"
    after = "module Lota\n  class Thing\n    def self.new: (Integer a, ?Integer b) -> Thing\n  end\nend\n"

    assert_empty compare(before, after).breaks
  end
end
