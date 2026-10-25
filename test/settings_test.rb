# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Lota::Settings starts with the defaults love.init gives its settings
# table (vendor/love/src/modules/love/boot.lua:178-238), under LÖVE's
# names, with enum strings as symbols (ADR 003, section 5).
class SettingsTest < Minitest::Test
  def settings
    @settings ||= Lota::Settings.new
  end

  def test_the_top_level_defaults_are_loves
    assert_equal "Untitled", settings.title
    assert_equal "12.0", settings.version
    refute settings.console
    refute settings.identity
    refute settings.appendidentity
    refute settings.externalstorage
    assert_nil settings.gammacorrect
    refute settings.highdpi
    assert_nil settings.renderers
    assert_nil settings.excluderenderers
    refute settings.trackpadtouch
  end

  def test_the_version_is_the_engines
    assert_equal Lota::Native::VERSION, settings.version
    assert_includes File.read(File.expand_path("../vendor/love/src/common/version.h", __dir__)),
      %(#define LOVE_VERSION_STRING "#{settings.version}")
  end

  def test_the_window_defaults_are_loves
    window = settings.window

    assert_equal [800, 600], [window.width, window.height]
    assert_nil window.x
    assert_nil window.y
    assert_equal [1, 1], [window.minwidth, window.minheight]
    refute window.fullscreen
    assert_equal :desktop, window.fullscreentype
    assert_equal 1, window.displayindex
    assert_equal 1, window.vsync
    assert_equal 0, window.msaa
    refute window.borderless
    refute window.resizable
    assert window.centered
    assert window.usedpiscale
    assert_nil window.title
    assert_nil window.stencil
    assert_nil window.depth
  end

  def test_the_graphics_defaults_are_loves
    graphics = settings.graphics

    refute graphics.gammacorrect
    refute graphics.lowpower
    assert_nil graphics.renderers
    assert_nil graphics.excluderenderers
  end

  # test_the_module_switches_match_boot_lua checks that these are
  # boot.lua's modules.
  def test_every_module_is_on_by_default
    switches = settings.modules.instance_variables

    assert_equal 19, switches.size
    switches.each { |switch| assert_equal true, settings.modules.instance_variable_get(switch), switch }
  end

  def test_the_audio_defaults_are_loves
    assert settings.audio.mixwithsystem
    refute settings.audio.mic
  end

  def test_every_setting_is_writable
    settings.window.width = 1280
    settings.window.fullscreentype = :exclusive
    settings.modules.physics = false
    settings.window = false

    refute settings.window
    refute settings.modules.physics
  end

  def test_a_misspelled_setting_raises
    assert_raises(NoMethodError) { settings.window.widht = 1280 }
  end

  # Every module boot.lua lists in its settings has a switch, and every
  # module it opens is one Lota::Boot knows, in boot.lua's order.
  def test_the_module_switches_match_boot_lua
    boot_lua = File.read(File.expand_path("../vendor/love/src/modules/love/boot.lua", __dir__))
    defaults = boot_lua[/modules = \{(.*?)\}/m, 1].scan(/(\w+) = true/).flatten.map(&:to_sym)
    order = boot_lua[/for k,v in ipairs\{(.*?)\} do/m, 1].scan(/"(\w+)"/).flatten.map(&:to_sym)

    assert_equal defaults.sort, settings.modules.instance_variables.map { |name| name.to_s.delete_prefix("@").to_sym }.sort
    assert_equal order, Lota::Boot::MODULES.keys
  end
end
