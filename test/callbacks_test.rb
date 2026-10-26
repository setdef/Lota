# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "callback_helper"

# Lota calls a game's callbacks as LÖVE's callbacks.lua does: only those
# the game defined, with as many of LÖVE's arguments as each declares
# (ADR 003, sections 2 and 3), through LÖVE's handler for each event.
class CallbacksTest < Minitest::Test
  include CallbackHelper

  def test_an_undefined_callback_is_skipped
    assert_nil Lota::Callbacks.call(:update, 0.016)
  end

  def test_a_defined_callback_receives_the_arguments_and_returns_its_value
    define_callback(:update) { |dt| "updated by #{dt}" }

    assert_equal "updated by 0.016", Lota::Callbacks.call(:update, 0.016)
  end

  def test_a_callback_receives_only_the_arguments_it_declares
    received = nil
    define_callback(:keypressed) { |key| received = [key] }

    Lota::Callbacks.call(:keypressed, :escape, :escape, false)

    assert_equal [:escape], received
  end

  def test_a_callback_with_optional_parameters_receives_as_many_as_it_names
    received = nil
    define_callback(:keypressed) { |key, scancode = :none| received = [key, scancode] }

    Lota::Callbacks.call(:keypressed, :a, :q, true)

    assert_equal %i[a q], received
  end

  def test_a_callback_with_a_splat_receives_every_argument
    received = nil
    define_callback(:keypressed) { |*arguments| received = arguments }

    Lota::Callbacks.call(:keypressed, :a, :q, true)

    assert_equal [:a, :q, true], received
  end

  def test_a_callback_that_declares_none_receives_none
    calls = 0
    define_callback(:draw) { calls += 1 }

    Lota::Callbacks.call(:draw, :ignored)

    assert_equal 1, calls
  end

  # Lua gives nil for every parameter its caller left out.
  def test_a_callback_that_declares_more_than_love_passes_receives_nil_for_the_rest
    define_callback(:keyreleased) { |key, scancode, extra| [key, scancode, extra] }

    assert_equal [:a, :q, nil], Lota::Callbacks.call(:keyreleased, :a, :q)
  end

  # Lua has no defaults, so a default is the game's own Ruby.
  def test_an_optional_parameter_love_does_not_pass_keeps_its_default
    define_callback(:textinput) { |text, extra = :default| [text, extra] }

    assert_equal ["é", :default], Lota::Callbacks.call(:textinput, "é")
  end

  def test_a_required_parameter_after_an_optional_one_receives_nil
    define_callback(:textinput) { |text, extra = :default, last| [text, extra, last] }

    assert_equal ["é", :default, nil], Lota::Callbacks.call(:textinput, "é")
  end

  def test_a_callback_with_a_splat_receives_nil_for_parameters_love_does_not_pass
    define_callback(:keyreleased) { |key, scancode, extra, *rest| [key, scancode, extra, rest] }

    assert_equal [:a, :q, nil, []], Lota::Callbacks.call(:keyreleased, :a, :q)
  end

  # LÖVE passes no keywords.
  def test_a_keyword_parameter_keeps_its_default
    define_callback(:keypressed) { |key, mode: :default| [key, mode] }

    assert_equal %i[a default], Lota::Callbacks.call(:keypressed, :a, :q, false)
  end

  def test_a_required_keyword_parameter_raises_as_ruby_does
    define_callback(:keypressed) { |key, mode:| [key, mode] }

    error = assert_raises(ArgumentError) { Lota::Callbacks.call(:keypressed, :a, :q, false) }
    assert_equal "missing keyword: :mode", error.message
  end

  def test_a_callback_defined_with_def_is_called
    Lota.singleton_class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def textinput(text)
        "typed \#{text}"
      end
    RUBY

    assert_equal "typed é", Lota::Callbacks.call(:textinput, "é")
  end

  # A Ruby method can return early, as a Lua callback can.
  def test_a_callback_can_return_early
    define_callback(:update) do |dt|
      next :paused if dt.zero?

      :moved
    end

    assert_equal :paused, Lota::Callbacks.call(:update, 0)
    assert_equal :moved, Lota::Callbacks.call(:update, 1)
  end

  # Game-state libraries wrap callbacks with prepend (ADR 003).
  def test_a_prepended_wrapper_receives_every_argument_and_calls_super
    calls = []
    define_callback(:keypressed) { |key| calls << [:game, key] }
    wrapper = Module.new do
      define_method(:keypressed) do |*arguments|
        calls << [:wrapper, *arguments]
        super(arguments.first)
      end
    end
    Lota.singleton_class.prepend(wrapper)

    Lota::Callbacks.call(:keypressed, :a, :a, false)

    assert_equal [[:wrapper, :a, :a, false], [:game, :a]], calls
  ensure
    wrapper&.remove_method(:keypressed)
  end

  def test_a_handler_passes_loves_arguments_to_its_callback
    received = nil
    define_callback(:keypressed) { |*arguments| received = arguments }

    Lota::Callbacks.handle(:keypressed, :a, :q, false, nil, nil, nil, nil, nil)

    assert_equal [:a, :q, false], received
  end

  def test_a_handler_passes_nil_for_arguments_the_message_lacks
    received = nil
    define_callback(:mousepressed) { |*arguments| received = arguments }

    Lota::Callbacks.handle(:mousepressed, 1.0, 2.0)

    assert_equal [1.0, 2.0, nil, nil, nil], received
  end

  def test_a_handler_returns_what_its_callback_returns
    define_callback(:focus) { |focused| focused ? :gained : :lost }

    assert_equal :gained, Lota::Callbacks.handle(:focus, true)
  end

  def test_the_quit_handler_calls_nothing
    define_callback(:quit) { flunk "the quit handler called quit" }

    assert_nil Lota::Callbacks.handle(:quit, 0)
  end

  def test_the_resize_handler_collects_garbage_only_without_a_resize_callback
    collections = GC.count
    Lota::Callbacks.handle(:resize, 800.0, 600.0)

    assert_operator GC.count, :>, collections

    define_callback(:resize) { |width, height| [width, height] }

    assert_equal [800.0, 600.0], Lota::Callbacks.handle(:resize, 800.0, 600.0)
  end

  def test_the_lowmemory_handler_calls_lowmemory_then_collects_garbage
    collections = nil
    define_callback(:lowmemory) { collections = GC.count }

    Lota::Callbacks.handle(:lowmemory)

    refute_nil collections
    assert_operator GC.count, :>=, collections + 2
  end

  def test_an_unknown_event_raises_loves_error
    error = assert_raises(RuntimeError) { Lota::Callbacks.handle(:nonsense) }

    assert_equal "Unknown event: nonsense", error.message
  end

  def test_every_handler_but_threaderror_and_audiodisconnected_is_ported
    callbacks_lua = File.read(File.expand_path("../vendor/love/src/modules/love/callbacks.lua", __dir__))
    handlers = callbacks_lua[/love\.handlers = setmetatable\(\{(.*?)\n\t\}, \{/m, 1]
    names = handlers.scan(/^\t\t(\w+) = function/).flatten.map(&:to_sym)

    assert_equal names - %i[threaderror audiodisconnected], Lota::Callbacks::HANDLERS.keys
  end
end
