# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "engine_helper"

# lota is always there, and each module has a lowercase accessor, so a
# tutorial's love. becomes lota. and nothing else changes (ADR 003,
# section 4). An accessor returns its module once the module is open, so
# the tests that read them open the engine first. That a module the
# settings turn off is nil is test/native/lota_run_test.rb's to prove, in
# a process of its own.
class LotaTest < Minitest::Test
  def test_lota_returns_lota_from_anywhere
    assert_same Lota, lota
    assert_same Lota, Object.new.instance_eval { lota }
  end

  def test_lota_is_private
    refute_respond_to Object.new, :lota
    assert_includes Kernel.private_instance_methods, :lota
  end

  def test_each_module_has_a_lowercase_accessor
    EngineHelper.open_window
    modules = {
      filesystem: Lota::Filesystem,
      image: Lota::Image,
      graphics: Lota::Graphics,
      timer: Lota::Timer,
      event: Lota::Event,
      window: Lota::Window,
      keyboard: Lota::Keyboard,
      font: Lota::Font,
      system: Lota::System,
      physics: Lota::Physics,
      data: Lota::Data,
    }

    modules.each { |name, mod| assert_same mod, lota.public_send(name), name }
  end

  # Every module Lota translates from LÖVE has an accessor; its native
  # extension, its callbacks, its command line, the methods every engine
  # object has, and the enum names it passes the engine are not LÖVE
  # modules. Lota::Data is both LÖVE's root type Data and love.data's
  # module (ADR 001, section 7), so it has one.
  def test_no_module_lacks_an_accessor
    EngineHelper.open_window
    own = %w[Lota::Native Lota::Callbacks Lota::DefaultCallbacks Lota::CLI Lota::Object Lota::EnumName]
    modules = Lota.constants.map { |name| Lota.const_get(name) }.grep(Module)
    modules.reject! { |mod| mod.is_a?(Class) || own.include?(mod.name) }

    modules.each do |mod|
      accessor = mod.name.split("::").last.downcase

      assert_same mod, Lota.public_send(accessor), accessor
    end
  end

  def test_a_callback_defined_through_lota_is_a_method_on_lota
    def lota.lota_test_callback(value) = value * 2

    assert_equal 4, Lota.lota_test_callback(2)
  ensure
    Lota.singleton_class.remove_method(:lota_test_callback)
  end
end
