# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2025 Aliet Exposito
# SPDX-License-Identifier: MIT
#
# Translated to Ruby from FLASH-BLIP's lib/overlayStats.lua
# (test/fixtures/flash_blip/game/lib/overlayStats.lua, lines 1-384), by
# the rules of doc/contributors/design/translation.md: the getters drop get
# and return Arrays (rules 3 and 4), so getRendererInfo is renderer_info,
# getStats stats, getSupported supported, getDimensions dimensions,
# getVSync vsync, getOS os, and getProcessorCount processor_count; setVSync
# and setColor become writers (rules 5 and 6) and setNewFont stays
# set_new_font, since it returns the font it makes (rule 7); isGamepadDown
# and isActive become gamepad_down? and active? (rule 8), the keys and
# buttons symbols (rule 9), push("all") ... pop() a block (rule 11), and
# getCount count. The module table's fields are its accessors, snake_cased
# as its functions are (isActive is is_active, renderInfo render_info), and
# its nested tables read by field are Structs; metrics, walked with pairs
# and keyed by name, is a Hash of Arrays keyed by the Lua's names.
#
# LÖVE 12's getStats has no canvases or images, so Lua's
# string.format("%d", nil) raises when the overlay draws, and update
# stores the misspelled canvasses, also nil; Lota's stats answers [] with
# nil for a field it lacks (rule 28), so the Ruby reads those three the same
# way and fails the same way. handleController calls toggleOverlay and
# toggleVSync before the Lua defines them as locals, so it calls the
# globals of those names, which do not exist, and raises; the Ruby raises
# Lua's error there too. collectgarbage("count"), the kilobytes Lua's heap
# holds, is ObjectSpace.memsize_of_all in kilobytes, and ffi.arch is
# LuaJIT's name for the processor's architecture.

require "objspace"
require "rbconfig"
require "lua"

module OverlayStats
  # renderInfo: love.graphics.getRendererInfo's four values.
  RenderInfo = Struct.new(:name, :version, :vendor, :device, keyword_init: true)
  # sysInfo
  SysInfo = Struct.new(:arch, :os, :cpu_count, keyword_init: true)
  # supportedFeatures
  SupportedFeatures = Struct.new(:glsl3, :pixel_shader_highp, keyword_init: true)
  # touch.overlayArea
  OverlayArea = Struct.new(:x, :y, :width, :height, keyword_init: true)
  # touch: Touch activation parameters
  Touch = Struct.new(:corner_size, :last_tap_time, :double_tap_threshold, :overlay_area, keyword_init: true)

  # LuaJIT's ffi.arch for the processor Ruby runs on.
  def self.ffi_arch
    case RbConfig::CONFIG["host_cpu"]
    when /\A(x86_64|amd64|x64)\z/ then "x64"
    when /\A(arm64|aarch64)\z/ then "arm64"
    when /\Ai[3-6]86\z/ then "x86"
    when /\Aarm/ then "arm"
    else RbConfig::CONFIG["host_cpu"]
    end
  end
  private_class_method :ffi_arch

  class << self
    attr_accessor :is_active, :sample_size, :vsync_enabled, :last_controller_check, :controller_cooldown,
      :particle_systems, :render_info, :sys_info, :supported_features, :metrics, :current_sample, :touch
  end

  name, version, vendor, device = Lota::Graphics.renderer_info
  @is_active = false
  @sample_size = 60
  @vsync_enabled = nil
  @last_controller_check = 0
  @controller_cooldown = 0.2
  # Store active particle systems
  @particle_systems = {}
  @render_info = RenderInfo.new(
    name:,
    version:,
    vendor:,
    device:,
  )
  @sys_info = SysInfo.new(
    arch: (Lota::System.os == "Web") ? "Web" : ffi_arch,
    os: Lota::System.os,
    cpu_count: Lota::System.processor_count,
  )
  @supported_features = SupportedFeatures.new(
    glsl3: false,
    pixel_shader_highp: false,
  )
  @metrics = {
    "canvases" => [],
    "canvasSwitches" => [],
    "drawCalls" => [],
    "drawCallsBatched" => [],
    "frameTime" => [],
    "imageCount" => [],
    "memoryUsage" => [],
    "shaderSwitches" => [],
    "textureMemory" => [],
    "particleCount" => [],
  }
  @current_sample = 0
  # Touch activation parameters
  @touch = Touch.new(
    corner_size: 80, # Size of the activation area in pixels
    last_tap_time: 0, # Time of the last tap
    double_tap_threshold: 0.5, # Maximum time between taps to register as double-tap
    overlay_area: OverlayArea.new(x: 10, y: 10, width: 280, height: 340), # Will be updated in draw
  )

  # Private functions

  # Calculates averages for all performance metrics
  # Returns a Hash of averaged metric values, keyed by the metrics' names
  def self.get_averages
    return {} unless OverlayStats.is_active

    averages = {}
    OverlayStats.metrics.each do |metric, samples|
      sum = 0
      count = 0
      # ipairs: up to the first nil
      samples.each do |value|
        break if value.nil?

        sum += value
        count += 1
      end
      averages[metric] = count.positive? ? sum.fdiv(count) : 0
    end
    averages
  end
  private_class_method :get_averages

  # Checks and processes controller input for toggling the overlay
  # Called from update() function
  def self.handle_controller
    # Controller input with cooldown
    current_time = Lota::Timer.time
    return if current_time - OverlayStats.last_controller_check < OverlayStats.controller_cooldown

    joysticks = Lota::Joystick.joysticks
    joysticks.each do |joystick|
      next unless joystick.gamepad_down?(:back)

      # Lua calls the globals toggleOverlay and toggleVSync here, which
      # nothing defines: its local functions come later in the file.
      if joystick.gamepad_down?(:a)
        raise NoMethodError, "attempt to call global 'toggleOverlay' (a nil value)"
      elsif joystick.gamepad_down?(:b)
        raise NoMethodError, "attempt to call global 'toggleVSync' (a nil value)"
      end
    end
  end
  private_class_method :handle_controller

  # Toggles the visibility of the overlay
  # Resets all metrics on activation
  def self.toggle_overlay
    OverlayStats.is_active = !OverlayStats.is_active
    # Reset metrics when toggling
    OverlayStats.metrics.each_key do |k|
      OverlayStats.metrics[k] = []
    end
    OverlayStats.current_sample = 0
    puts format("Overlay %s", OverlayStats.is_active ? "enabled" : "disabled")
  end
  private_class_method :toggle_overlay

  # Toggles the VSync state in LÖVE
  # Only functions when the overlay is active
  def self.toggle_vsync
    return unless OverlayStats.is_active

    OverlayStats.vsync_enabled = !OverlayStats.vsync_enabled
    Lota::Window.vsync = OverlayStats.vsync_enabled ? 1 : 0
    puts format("VSync %s", OverlayStats.vsync_enabled ? "enabled" : "disabled")
  end
  private_class_method :toggle_vsync

  # Checks if the given touch position is in the top-right corner activation area
  # Returns true if touch is in the activation area
  def self.is_touch_in_corner(x, y)
    w, _h = Lota::Graphics.dimensions
    x >= w - OverlayStats.touch.corner_size && y <= OverlayStats.touch.corner_size
  end
  private_class_method :is_touch_in_corner

  # Checks if the given touch position is inside the overlay area
  # Returns true if touch is inside the overlay area
  def self.is_touch_inside_overlay(x, y)
    area = OverlayStats.touch.overlay_area
    x >= area.x && x <= area.x + area.width &&
      y >= area.y && y <= area.y + area.height
  end
  private_class_method :is_touch_inside_overlay

  # Processes touch input for the overlay toggle (Lua's local handleTouch,
  # named apart from the public handleTouch, which Ruby's handle_touch is)
  def self.handle_touch_at(x, y)
    current_time = Lota::Timer.time
    time_since_last_tap = current_time - OverlayStats.touch.last_tap_time

    if OverlayStats.is_active && is_touch_inside_overlay(x, y)
      # Handle touches inside the active overlay
      if time_since_last_tap <= OverlayStats.touch.double_tap_threshold
        # Double tap inside overlay - toggle VSync
        toggle_vsync
        OverlayStats.touch.last_tap_time = 0
      else
        OverlayStats.touch.last_tap_time = current_time
      end
    elsif is_touch_in_corner(x, y)
      # Original behavior for corner taps to toggle overlay
      if time_since_last_tap <= OverlayStats.touch.double_tap_threshold
        toggle_overlay
        OverlayStats.touch.last_tap_time = 0
      else
        OverlayStats.touch.last_tap_time = current_time
      end
    end
  end
  private_class_method :handle_touch_at

  # Public API

  # Initializes the overlay stats module
  def self.load
    # Initialize moving averages
    OverlayStats.metrics.each_key do |k|
      OverlayStats.metrics[k] = []
    end
    # Get initial vsync state from LÖVE config
    OverlayStats.vsync_enabled = Lota::Window.vsync == 1

    # Get graphics feature support information
    supported = Lota::Graphics.supported
    OverlayStats.supported_features.glsl3 = supported.glsl3
    OverlayStats.supported_features.pixel_shader_highp = supported.pixelshaderhighp
  end

  # Draws the performance overlay when active
  def self.draw
    return unless OverlayStats.is_active

    averages = get_averages

    # Set up overlay drawing
    Lota::Graphics.push(:all) do
      font = Lota::Graphics.set_new_font(16)

      # Calculate dynamic width based on renderer version and other content
      padding = 20 # 10px padding on each side
      base_width = 280 # Minimum width

      render_info = OverlayStats.render_info
      sys_info = OverlayStats.sys_info
      system_text = "#{sys_info.os} #{sys_info.arch}: #{Lua.tostring(sys_info.cpu_count)}x CPU"

      # Check width needed for the renderer version text
      version_text_width = font.width(format("%s", render_info.version))
      renderer_info_width = font.width(
        format("Renderer: %s (%s)", render_info.name, render_info.vendor),
      )
      system_info_width = font.width(system_text)

      # Calculate rectangle width based on the widest content
      content_width = [version_text_width, renderer_info_width, system_info_width, base_width].max
      rectangle_width = content_width + padding

      # Update the overlay area dimensions for touch detection
      OverlayStats.touch.overlay_area = OverlayArea.new(
        x: 10,
        y: 10,
        width: rectangle_width,
        height: 340,
      )

      # Draw background rectangle with dynamic width
      Lota::Graphics.color = 0, 0, 0, 0.8
      Lota::Graphics.rectangle(:fill, 10, 10, rectangle_width, 340)
      Lota::Graphics.color = 0.678, 0.847, 0.902, 1

      # System Info
      y = 20
      Lota::Graphics.print(system_text, 20, y)
      y += 30

      Lota::Graphics.color = 1, 1, 1, 1
      Lota::Graphics.print(
        format("Renderer: %s (%s)", render_info.name, render_info.vendor),
        20,
        y,
      )
      y += 20

      Lota::Graphics.print(format("%s", render_info.version), 20, y)
      y += 30

      # Safely handle frameTime with nil/zero checks
      Lota::Graphics.color = 0, 1, 0, 1
      frame_time = averages["frameTime"] || 0
      fps = frame_time.positive? ? 1.0 / frame_time : 0
      Lota::Graphics.print(format("FPS: %.1f (%.1fms)", fps, frame_time * 1000), 20, y)
      y += 20

      # Reset canvases each frame
      current_canvases = Lota::Graphics.stats[:canvases]
      Lota::Graphics.print(format("Canvases: %d", current_canvases), 20, y)
      y += 20

      # Reset canvas switches each frame
      current_canvas_switches = Lota::Graphics.stats.canvasswitches
      Lota::Graphics.print(format("Canvas Switches: %d", current_canvas_switches), 20, y)
      y += 20

      # Reset shader switches each frame
      current_shader_switches = Lota::Graphics.stats.shaderswitches
      Lota::Graphics.print(format("Shader Switches: %d", current_shader_switches), 20, y)
      y += 20

      # Reset draw calls each frame
      current_draw_calls = Lota::Graphics.stats.drawcalls
      current_draw_calls_batched = Lota::Graphics.stats.drawcallsbatched
      Lota::Graphics.print(format("Draw Calls: %d (%d batched)", current_draw_calls, current_draw_calls_batched),
        20, y)
      y += 20

      Lota::Graphics.print(format("RAM: %.1f MB", averages["memoryUsage"] / 1024.0), 20, y)
      y += 20

      # Reset texture memory usage  each frame
      current_texture_memory = Lota::Graphics.stats.texturememory.fdiv(1024 * 1024)
      Lota::Graphics.print(format("VRAM: %.1f MB", current_texture_memory), 20, y)
      y += 20

      # Reset images each frame
      current_images = Lota::Graphics.stats[:images]
      Lota::Graphics.print(format("Images: %d", current_images), 20, y)
      y += 20

      # Display particle count
      current_particle_count = averages["particleCount"] || 0
      Lota::Graphics.print(format("Particles: %d", current_particle_count.floor), 20, y)
      y += 20

      # Add GLSL 3 support indicator
      Lota::Graphics.color = OverlayStats.supported_features.glsl3 ? [0, 1, 0, 1] : [1, 0, 0, 1]
      Lota::Graphics.print(format("GLSL 3: %s", OverlayStats.supported_features.glsl3 ? "Yes" : "No"), 20, y)
      y += 20

      # Add pixel shader highp support indicator
      Lota::Graphics.color = OverlayStats.supported_features.pixel_shader_highp ? [0, 1, 0, 1] : [1, 0, 0, 1]
      Lota::Graphics.print(
        format("Pixel Shader highp: %s", OverlayStats.supported_features.pixel_shader_highp ? "Yes" : "No"), 20, y,
      )
      y += 20

      # Add VSync status with color indication
      Lota::Graphics.color = OverlayStats.vsync_enabled ? [0, 1, 0, 1] : [1, 0, 0, 1]
      Lota::Graphics.print(format("VSync: %s", OverlayStats.vsync_enabled ? "ON" : "OFF"), 20, y)
    end
  end

  # Updates performance metrics and handles controller input
  def self.update(dt)
    handle_controller

    return unless OverlayStats.is_active

    OverlayStats.current_sample += 1
    OverlayStats.current_sample = 1 if OverlayStats.current_sample > OverlayStats.sample_size

    # Get draw call stats before any drawing occurs
    stats = Lota::Graphics.stats
    i = OverlayStats.current_sample - 1
    metrics = OverlayStats.metrics
    metrics["canvases"][i] = stats[:canvasses]
    metrics["canvasSwitches"][i] = stats.canvasswitches
    metrics["drawCalls"][i] = stats.drawcalls
    metrics["drawCallsBatched"][i] = stats.drawcallsbatched
    metrics["imageCount"][i] = stats[:images]
    metrics["shaderSwitches"][i] = stats.shaderswitches
    metrics["textureMemory"][i] = stats.texturememory.fdiv(1024 * 1024)
    metrics["memoryUsage"][i] = ObjectSpace.memsize_of_all / 1024.0
    metrics["frameTime"][i] = dt

    # Calculate total particle count from all registered systems
    total_particles = 0
    OverlayStats.particle_systems.each_key do |ps|
      total_particles += ps.count if ps.active?
    end
    metrics["particleCount"][i] = total_particles
  end

  # Processes keyboard input for the overlay
  def self.handle_keyboard(key)
    case key
    when :f3
      toggle_overlay
    when :f5
      toggle_vsync
    end
  end

  # Handles touch press events for toggling the overlay
  def self.handle_touch(_id, x, y, _dx, _dy, _pressure)
    handle_touch_at(x, y)
  end

  # Register a particle system to be tracked
  def self.register_particle_system(particle_system)
    OverlayStats.particle_systems[particle_system] = true
  end

  # Unregister a particle system from tracking
  def self.unregister_particle_system(particle_system)
    OverlayStats.particle_systems.delete(particle_system)
  end
end
# SPDX-SnippetEnd
