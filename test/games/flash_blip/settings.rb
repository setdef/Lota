# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's settings.lua
# (test/fixtures/flash_blip/game/settings.lua, lines 1-139), by the rules of
# doc/contributors/design/translation.md: love.system.getOS becomes
# Lota::System.os and love.graphics.getRendererInfo renderer_info, whose
# values are an Array (rules 3 and 4), so select(2, ...) is its second
# element; getSupported becomes supported, whose table is a frozen record
# (rules 3 and 28); love.filesystem.getInfo becomes Lota::Filesystem.info
# (rule 3), and read and write return Arrays (rule 4).
#
# The Settings table becomes the module Settings, and each of its fields a
# reader and writer named the field's name downcased (WINDOW_WIDTH is
# window_width). settings.lua also reads and writes the fields by name, as
# Settings[key], and options.lua does too, so Settings[] and Settings[]=
# take the Lua name, IS_SFX_VOLUME, and reach the same reader and writer.
# Lua's "love and love.system" asks whether a module is open, which
# Lota.system asks. Lua's arg, the command line, is ARGV.
#
# LuaJIT's ffi.arch names the processor LuaJIT was built for, "arm" or
# "arm64" on ARM. Ruby has no FFI module to ask, so the processor Ruby was
# built for, RbConfig's host_cpu, stands in: "aarch64" or "arm64" is
# "arm64", any other name that starts with "arm" is "arm", and anything else
# is neither, so is_arm_linux asks the same question.
#
# SCHEMA, a local table keyed by name, is a Hash, and each spec in it a
# record with its type, default, min, and max. Lua visits it with pairs, in
# LuaJIT's hash order, which Ruby cannot reproduce: where the order does not
# matter, in setting the defaults and in reading the file, it visits them
# in the Lua order; where it does, in the text save writes, it is marked.

require "rbconfig"
require "lua"

module Settings
  # The processor LuaJIT's ffi.arch would name, as described above.
  def self.ffi_arch
    cpu = RbConfig::CONFIG["host_cpu"].to_s
    if %w[aarch64 arm64].include?(cpu)
      "arm64"
    elsif cpu.start_with?("arm")
      "arm"
    else
      cpu
    end
  end
  private_class_method :ffi_arch

  is_mobile = (Lota.system && (Lota::System.os == "Android" || Lota::System.os == "iOS")) || false
  is_web = (Lota.system && Lota::System.os == "Web") || false

  is_debug_env = ENV["LOCAL_LUA_DEBUGGER_VSCODE"] == "1"
  if !is_debug_env && ARGV
    ARGV.each do |v|
      if v == "--debug" || v == "debug"
        is_debug_env = true
        break
      end
    end
  end

  has_ffi = true
  ffi_arch = self.ffi_arch
  is_arm_linux = (Lota.system &&
    Lota::System.os == "Linux" &&
    has_ffi &&
    (ffi_arch == "arm" || ffi_arch == "arm64")) ||
    false

  class << self
    attr_accessor :config_file, :internal_width, :internal_height, :is_debug_enabled, :scale_factor,
      :is_mobile, :is_arm_linux, :opengl_version, :is_web, :supports_glsl3, :aspect_ratio, :window_width,
      :window_height, :dpi_scale, :max_levels, :is_music_enabled, :is_sfx_enabled, :is_glow_enabled,
      :has_passed_glow_test, :is_blur_enabled, :is_music_volume, :is_sfx_volume
  end

  @config_file = "settings_config.txt"
  @internal_width = 120
  @internal_height = 160
  # Enables debug statistics (the on-screen info can be toggled with F3)
  @is_debug_enabled = is_debug_env
  # The scale factor and window size will be calculated dynamically in main.lua
  @scale_factor = 1
  # Platform detection
  @is_mobile = is_mobile
  @is_arm_linux = is_arm_linux
  @opengl_version = (Lota.graphics && Lota::Graphics.renderer_info[1]) || "OpenGL"
  @is_web = is_web
  @supports_glsl3 = (Lota.graphics && Lota::Graphics.respond_to?(:supported) && Lota::Graphics.supported.glsl3) ||
    false
  @aspect_ratio = nil
  @window_width = 120
  @window_height = 160
  # DPI scale for mobile devices
  @dpi_scale = 1
  # Maximum number of levels for Arcade Mode
  @max_levels = 100

  # The value of the field Lua names +key+, as Settings[key] reads it.
  def self.[](key)
    public_send(key.downcase)
  end

  # Sets the field Lua names +key+ to +value+, as Settings[key] = value.
  def self.[]=(key, value)
    public_send(:"#{key.downcase}=", value)
  end

  # A spec of SCHEMA: its type, default, and, for a number, min and max.
  Spec = Data.define(:type, :default, :min, :max)

  # Options
  SCHEMA = {
    "IS_MUSIC_ENABLED" => Spec.new(type: "boolean", default: true, min: nil, max: nil),
    "IS_SFX_ENABLED" => Spec.new(type: "boolean", default: true, min: nil, max: nil),
    "IS_GLOW_ENABLED" => Spec.new(type: "boolean", default: !is_mobile && !is_web, min: nil, max: nil),
    "HAS_PASSED_GLOW_TEST" => Spec.new(type: "boolean", default: false, min: nil, max: nil),
    "IS_BLUR_ENABLED" => Spec.new(type: "boolean", default: !is_mobile && !is_web, min: nil, max: nil),
    "IS_MUSIC_VOLUME" => Spec.new(type: "number", default: 1.0, min: 0.0, max: 1.0),
    "IS_SFX_VOLUME" => Spec.new(type: "number", default: 1.0, min: 0.0, max: 1.0),
  }.freeze

  # Initialize default values from schema
  SCHEMA.each do |key, spec|
    Settings[key] = spec.default
  end

  @save_pending = false
  @save_timer = 0

  def self.save_debounced
    @save_pending = true
    @save_timer = 0.5
  end

  def self.update(dt)
    return unless @save_pending

    @save_timer -= dt
    Settings.save if @save_timer <= 0
  end

  def self.save
    @save_pending = false
    lines = []
    # Lua writes the lines in pairs' order, which LuaJIT changes from run to
    # run and the parity harness makes sorted (test/parity/lua/conf.lua,
    # sorted_pairs), so the lines are in the order of the keys' names.
    SCHEMA.sort.each do |key, spec|
      val = Settings[key]
      val = if spec.type == "number"
        format("%.2f", (val.nil? ? spec.default : val).clamp(spec.min, spec.max))
      else
        Lua.tostring(val)
      end
      lines << "#{key}=#{val}"
    end
    content = "#{lines.join("\n")}\n"

    return unless Lota.filesystem

    ok, err = Lota::Filesystem.write(Settings.config_file, content)
    puts("[Settings] Error writing config: #{Lua.tostring(err)}") unless ok
  end

  def self.load
    return false unless Lota.filesystem

    return false unless Lota::Filesystem.info(Settings.config_file)

    content, = Lota::Filesystem.read(Settings.config_file)
    return false unless content

    loaded_has_passed_glow_test = false
    content.scan(/[^\r\n]+/) do |line|
      k, v = line.match(/\A\s*([^=]+)\s*=\s*(.*?)\s*\z/)&.captures
      spec = SCHEMA[k]
      next unless spec

      loaded_has_passed_glow_test = true if k == "HAS_PASSED_GLOW_TEST"
      if spec.type == "boolean"
        Settings[k] = (v == "true")
      elsif spec.type == "number"
        num = (Lua.tonumber(v) || Lua.tonumber(spec.default) || 0).to_f
        Settings[k] = num.clamp(spec.min, spec.max)
      end
    end

    Settings.has_passed_glow_test = true if !loaded_has_passed_glow_test && Settings.is_glow_enabled

    true
  end
end
# SPDX-SnippetEnd
