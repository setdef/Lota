# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "bindings_helper"

# ADR 001's rules, applied to LÖVE's real functions. The examples are the
# rule table's own, so the engine and the table cannot drift apart.
class RulesTest < Minitest::Test
  include BindingsHelper

  def ruby_name(love_name)
    translation(love_name).ruby_name
  end

  def rules(love_name)
    translation(love_name).rules
  end

  def collisions(love_name)
    translation(love_name).collisions.map { |collision| [collision.kind, collision.rules] }
  end

  def test_rule_1_modules_keep_their_names
    assert_equal "Lota::Graphics", translation("love.graphics.getWidth").scope
    assert_equal "Lota::Physics::Body", translation("Body:applyForce").scope
  end

  # LÖVE's root type Data keeps its name inside Lota (ADR 001, section 7),
  # so Data's methods are Lota::Data's, which every Data includes, as
  # Object's are Lota::Object's, while love.data's other types are classes
  # in that module.
  def test_the_root_type_data_is_lota_data
    assert_equal "Lota::Data#size", ruby_name("Data:getSize")
    assert_equal "Lota::Data#string", ruby_name("Data:getString")
    assert_equal "Lota::Data.compress", ruby_name("love.data.compress")
    assert_equal "Lota::Data::ByteData", translation("ByteData:clone").scope
  end

  def test_rule_2_factories_become_constructors
    assert_equal "Lota::Graphics::SpriteBatch.new", ruby_name("love.graphics.newSpriteBatch")
    assert_includes rules("love.graphics.newSpriteBatch"), 2
    assert_empty collisions("love.graphics.newSpriteBatch")
  end

  # Rule 2 decides Canvas === and Image === itself, and RectangleShape ===
  # is decided as Image === is, true of every PolygonShape; other
  # factories with no class leave it open.
  def test_rule_2_module_factories_leave_their_case_equality_open
    assert_equal "Lota::Graphics::Canvas.new", ruby_name("love.graphics.newCanvas")
    assert_empty collisions("love.graphics.newCanvas")
    assert_empty collisions("love.graphics.newImage")
    assert_empty collisions("love.physics.newRectangleShape")
    assert_equal [[:open, [2]]], collisions("love.graphics.newCubeTexture")
  end

  def test_rules_3_and_4_getters_drop_get_and_return_arrays
    assert_equal "Lota::Graphics.dimensions", ruby_name("love.graphics.getDimensions")
    assert_equal [1, 3, 4, 14], rules("love.graphics.getDimensions")
    assert_equal [1, 3, 14], rules("love.graphics.getWidth")
  end

  def test_rules_5_and_6_setters_become_writers
    assert_equal "Lota::Window.title=", ruby_name("love.window.setTitle")
    assert_includes rules("love.window.setTitle"), 5
    assert_equal "Lota::Mouse.position=", ruby_name("love.mouse.setPosition")
    assert_includes rules("love.mouse.setPosition"), 6
  end

  def test_rule_7_setters_that_return_a_value_stay_methods
    assert_equal "Lota::Window.set_fullscreen", ruby_name("love.window.setFullscreen")
    assert_includes rules("love.window.setFullscreen"), 7
  end

  # Transform:setTransformation returns the Transform itself
  # (wrap_Transform.cpp), so it is a writer (ADR 001, after the table).
  def test_a_setter_that_returns_itself_is_a_writer
    assert_equal "Lota::Math::Transform#transformation=", ruby_name("Transform:setTransformation")
  end

  def test_rule_8_predicates_gain_a_question_mark
    assert_equal "Lota::Mouse.down?", ruby_name("love.mouse.isDown")
    assert_equal "Lota::Window.focus?", ruby_name("love.window.hasFocus")
  end

  def test_rule_9_enums_rule_10_option_tables_rule_12_functions
    assert_includes rules("love.graphics.setLineStyle"), 9
    assert_includes rules("love.window.showMessageBox"), 10
    assert_includes rules("love.graphics.captureScreenshot"), 12
    assert_includes rules("ImageData:mapPixel"), 12
    refute_includes rules("ImageData:getPixel"), 12
  end

  def test_rule_13_every_other_name_becomes_snake_case
    assert_equal "Lota::Physics::Body#apply_force", ruby_name("Body:applyForce")
    assert_equal "readback_texture", Bindings::Rules.snake_case("readbackTexture")
    assert_equal "high_dpi_allowed", Bindings::Rules.snake_case("HighDPIAllowed")
  end

  def test_rule_14_numbers_mark_the_function
    assert_includes rules("love.graphics.getWidth"), 14
    refute_includes rules("love.window.setTitle"), 14
  end

  def test_an_underscore_fits_no_rule
    assert_nil translation("RandomGenerator:_random").name
    assert_equal [[:no_rule, []]], collisions("RandomGenerator:_random")
  end

  # Rule 13: a Lua metamethod is a method like any other, named as Ruby
  # names the same method, by its operator.
  def test_rule_13_names_a_metamethod_by_its_operator
    assert_equal "Lota::Math::Transform#*", ruby_name("Transform:__mul")
    assert_includes rules("Transform:__mul"), 13
    assert_empty collisions("Transform:__mul")
    assert_equal "==", Bindings::Rules::METAMETHODS.fetch("__eq")
    assert_equal "to_s", Bindings::Rules::METAMETHODS.fetch("__tostring")
  end

  def test_several_values_from_a_non_getter_fit_no_rule
    assert_includes collisions("love.graphics.transformPoint"), [:no_rule, []]
  end

  # Rule 13 spells LÖVE's UInt as C spells uint8_t, one word, so
  # Data:getUInt8 is uint8, not u_int8, and leaves nothing open.
  def test_rule_13_spells_uint_as_one_word
    assert_equal "Lota::Data#uint8", ruby_name("Data:getUInt8")
    assert_equal "Lota::Data#uint32", ruby_name("Data:getUInt32")
    assert_equal "uint16", Bindings::Rules.snake_case("UInt16")
    assert_empty collisions("Data:getUInt16")
    assert_equal "int16", Bindings::Rules.snake_case("Int16")
  end

  # Rule 13: an acronym is one word, and digits stay with the word they
  # follow, as in Ruby's use_ssl? and sha256, so nothing is left open.
  def test_rule_13_keeps_an_acronym_and_its_digits_one_word
    assert_equal "Lota::Graphics.dpi_scale", ruby_name("love.graphics.getDPIScale")
    assert_empty collisions("love.graphics.getDPIScale")
    assert_equal "Lota::Math::Transform#affine2d_transform?", ruby_name("Transform:isAffine2DTransform")
    assert_empty collisions("Transform:isAffine2DTransform")
    assert_equal "uint8_array", Bindings::Rules.snake_case("UInt8Array")
    assert_equal "fps", Bindings::Rules.snake_case("FPS")
  end

  def test_an_option_table_before_other_arguments_fits_two_rules
    assert_includes collisions("love.window.showMessageBox"), [:several_rules, [10]]
  end

  # Rule 16: on a class that also has getType, where type would be
  # ambiguous, getType and setType keep their prefixes, as methods, not
  # the getter and writer rules 3 and 5 would make them, and no longer
  # collide with Object:type.
  def test_rule_16_keeps_get_type_and_set_type_where_a_class_has_get_type
    assert_equal "Lota::Physics::Body#get_type", ruby_name("Body:getType")
    assert_equal "Lota::Physics::Body#set_type", ruby_name("Body:setType")
    assert_equal "Lota::Audio::Source#get_type", ruby_name("Source:getType")
    assert_equal [1, 16, 9], rules("Body:getType")
    refute_includes rules("Body:setType"), 5
    %w[Body:getType Body:setType Shape:getType Joint:getType Source:getType Cursor:getType].each do |name|
      assert_empty collisions(name), name
    end
  end

  # Rule 16 takes type from every class with getType, found in the wrap
  # files rather than listed by hand: its subclasses inherit getType.
  def test_the_survey_finds_every_class_with_get_type
    assert_equal %w[
      Lota::Audio::Source
      Lota::Mouse::Cursor
      Lota::Physics::Body
      Lota::Physics::Joint
      Lota::Physics::Shape
], survey.typed_classes
  end

  # Rule 16 gives every object object_type, type, and type_of?, so a
  # function that would take one of those names collides.
  def test_rule_16s_object_methods_are_its_own
    assert_equal %w[object_type type type_of?], Bindings::Rules::OBJECT_METHODS
    assert_empty collisions("love.audio.getVolume")
  end

  def test_overriding_rubys_own_methods_fits_two_rules
    assert_includes collisions("ImageData:clone"), [:several_rules, [13]]
    assert_includes collisions("love.data.hash"), [:several_rules, [13]]
    assert_includes collisions("love.sensor.getName"), [:several_rules, [13]]
  end

  # The open collision ADR 001 already names (File:open, wrap_File.cpp).
  def test_file_open_collides_with_rule_11
    assert_includes collisions("File:open"), [:several_rules, [11]]
    assert_empty collisions("love.graphics.push")
    assert_includes collisions("Channel:push"), [:open, [11]]
    assert_empty collisions("love.filesystem.mount"), "rule 11 decides mount and unmount have no block"
  end

  # ADR 001 decides that a Source's play and stop are not a rule 11 pair:
  # a sound plays across frames (section 7, after the table).
  def test_playing_and_stopping_a_source_is_no_pair
    assert_empty collisions("Source:play")
    assert_empty collisions("love.audio.play")
    assert_includes collisions("RecordingDevice:start"), [:open, [11]]
  end

  # Every function gets exactly one Ruby name, or a collision saying no
  # rule gives one.
  def test_every_function_is_named_exactly_once
    survey.entries.each do |entry|
      translation = entry.translation
      no_rule = translation.collisions.any? { |collision| collision.kind == :no_rule && collision.rules.empty? }
      assert(translation.name || no_rule, "#{entry.function.love_name} has no name and no collision")
    end
    named = survey.entries.select { |entry| entry.translation.name && entry.source != :lua }
    clashing = named.group_by { |entry| entry.translation.ruby_name }.select { |_, group| group.size > 1 }
    clashing.each_value do |group|
      group.each { |entry| assert_includes entry.collisions.map(&:kind), :several_rules, entry.function.love_name }
    end
  end

  # The report counts and lists every collision for the maintainer.
  def test_the_report_lists_collisions_by_module_and_counts_them
    report = Bindings::Report.new(survey)
    text = report.to_s

    assert_includes text, "== love.filesystem"
    assert_includes text, "File:open  src/modules/filesystem/wrap_File.cpp:75  (rule 11) opens a rule 11 pair"
    assert_includes text, "love.graphics.clear  src/modules/graphics/wrap_Graphics.cpp:69  reads the stack"
    assert_includes text, "RandomGenerator:random  src/modules/math/wrap_RandomGenerator.lua:46  defined in Lua (l, u)"
    assert_includes text, "SoundData:getSample  src/modules/sound/wrap_SoundData.lua:79  defined in Lua (i, channel), " \
      "which replaces its C++ (src/modules/sound/wrap_SoundData.cpp:"
    assert_match %r{    ImageData:getPixel  src/modules/image/wrap_ImageData.cpp:105  by src/modules/image/wrap_ImageData.lua:395 when }, text
    counts = report.counts

    assert_equal 1133, counts.fetch(:functions)
    assert_equal counts.fetch(:functions),
      counts.fetch(:readable) + counts.fetch(:unreadable) + counts.fetch(:lua) + counts.fetch(:outside)
  end

  # ADR 001 names its rule 7 setters by Lua name alone, and setFilter is
  # also a writer on Font, Texture, and Video.
  def test_the_report_checks_adr_001s_rule_7_list
    missing, returning_nothing, unread = Bindings::Report.new(survey).rule_7_difference

    assert_empty missing
    assert_equal %w[Font:setFilter Texture:setFilter Video:setFilter], returning_nothing.sort
    assert_includes unread, "love.window.setMode"
  end
end
