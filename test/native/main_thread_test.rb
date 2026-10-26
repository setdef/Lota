# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Graphics and Lota::Window run only on the process's main thread,
# as LÖVE keeps love.graphics and love.window there (ADR 001, section 6);
# every other call raises ThreadError there. Lota::Image and
# Lota::Filesystem run anywhere, as LÖVE lets love.image and
# love.filesystem run on its threads.
class MainThreadTest < Minitest::Test
  include NativeHelper

  PNG = File.binread(File.join(ROOT, "vendor/love/testing/output/expected/love.test.graphics.clear-1.png"))

  def setup
    EngineHelper.open_window
  end

  # Runs the block on another thread and returns what it raised.
  def raised_off_the_main_thread(&block)
    Thread.new do
      block.call
      nil
    rescue ThreadError => e
      e
    end.value
  end

  def test_this_suite_runs_on_the_main_thread
    assert_same Thread.main, Thread.current
  end

  def test_graphics_works_on_the_main_thread
    texture = Lota::Graphics::Canvas.new(2, 2)
    Lota::Graphics.canvas = texture
    Lota::Graphics.clear(0, 1, 0)
    Lota::Graphics.canvas = nil

    assert_equal [0.0, 1.0, 0.0, 1.0], Lota::Graphics.readback_texture(texture).pixel(1, 1)
  end

  def test_graphics_raises_off_the_main_thread
    texture = Lota::Graphics::Canvas.new(2, 2)
    font = Lota::Graphics::Font.new(8)
    font_data = Lota::Filesystem::FileData.new(File.binread(File.join(ROOT, "vendor/love/testing/resources/font.ttf")),
      "font.ttf")
    image_file = Lota::Filesystem::FileData.new(File.binread(File.join(ROOT, "vendor/love/testing/resources/love.png")),
      "love.png")
    image_data = Lota::Image::ImageData.new(image_file)
    calls = {
      "Canvas.new" => -> { Lota::Graphics::Canvas.new(2, 2) },
      "canvas=" => -> { Lota::Graphics.canvas = texture },
      "canvas = nil" => -> { Lota::Graphics.canvas = nil },
      "clear" => -> { Lota::Graphics.clear },
      "readback_texture" => -> { Lota::Graphics.readback_texture(texture) },
      "canvas?" => -> { texture.canvas? },
      "open" => -> { Lota::Native::Graphics.open },
      "open?" => -> { Lota::Native::Graphics.open? },
      "set_gamma_correct" => -> { Lota::Native::Graphics.set_gamma_correct(false) },
      "set_low_power_preferred" => -> { Lota::Native::Graphics.set_low_power_preferred(false) },
      "default_renderers" => -> { Lota::Native::Graphics.default_renderers },
      "set_renderers" => -> { Lota::Native::Graphics.set_renderers(["metal"]) },
      "active?" => -> { Lota::Graphics.active? },
      "origin" => -> { Lota::Graphics.origin },
      "background_color" => -> { Lota::Graphics.background_color },
      "present" => -> { Lota::Graphics.present },
      "width" => -> { Lota::Graphics.width },
      "height" => -> { Lota::Graphics.height },
      "dimensions" => -> { Lota::Graphics.dimensions },
      "color=" => -> { Lota::Graphics.color = 1, 1, 1 },
      "color" => -> { Lota::Graphics.color },
      "rectangle" => -> { Lota::Graphics.rectangle(:fill, 0, 0, 1, 1) },
      "circle" => -> { Lota::Graphics.circle(:fill, 0, 0, 1) },
      "ellipse" => -> { Lota::Graphics.ellipse(:fill, 0, 0, 1, 2) },
      "arc" => -> { Lota::Graphics.arc(:fill, 0, 0, 1, 0, 1) },
      "line" => -> { Lota::Graphics.line(0, 0, 1, 1) },
      "draw" => -> { Lota::Graphics.draw(texture) },
      "Canvas.new(msaa:)" => -> { Lota::Graphics::Canvas.new(2, 2, msaa: 2) },
      "Texture.new(data)" => -> { Lota::Graphics::Texture.new(image_file) },
      "Texture.new(image data)" => -> { Lota::Graphics::Texture.new(image_data) },
      "line_width=" => -> { Lota::Graphics.line_width = 1 },
      "line_width" => -> { Lota::Graphics.line_width },
      "line_style=" => -> { Lota::Graphics.line_style = :rough },
      "line_style" => -> { Lota::Graphics.line_style },
      "capture_screenshot" => -> { Lota::Native::Graphics.capture_screenshot(-> (_image) {}) },
      "Font.new" => -> { Lota::Graphics::Font.new },
      "Font.new(size)" => -> { Lota::Graphics::Font.new(8) },
      "Font.new(data)" => -> { Lota::Graphics::Font.new(font_data) },
      "Font.new(data, size)" => -> { Lota::Graphics::Font.new(font_data, 8) },
      "font=" => -> { Lota::Graphics.font = font },
      "font" => -> { Lota::Graphics.font },
      "print" => -> { Lota::Graphics.print("off", 0, 0) },
      "printf" => -> { Lota::Graphics.printf("off", 0, 0, 100, :center) },
      "default_filter=" => -> { Lota::Graphics.default_filter = :nearest },
      "default_filter" => -> { Lota::Graphics.default_filter },
    }

    calls.each do |label, call|
      error = raised_off_the_main_thread(&call)

      assert_instance_of ThreadError, error, label
      assert_equal "Lota::Graphics runs only on the main thread", error.message, label
    end
  end

  def test_window_raises_off_the_main_thread
    calls = {
      "open" => -> { Lota::Native::Window.open },
      "set_mode" => -> { Lota::Native::Window.set_mode(360, 240, Lota::Native::WindowSettings.new) },
      "Lota::Window.set_mode" => -> { Lota::Window.set_mode(360, 240) },
      "title=" => -> { Lota::Window.title = "Elsewhere" },
      "title" => -> { Lota::Window.title },
      "set_high_dpi_allowed" => -> { Lota::Native::Window.set_high_dpi_allowed(false) },
    }

    calls.each do |label, call|
      error = raised_off_the_main_thread(&call)

      assert_instance_of ThreadError, error, label
      assert_equal "Lota::Window runs only on the main thread", error.message, label
    end
  end

  # Only the main thread drains the release queue (release_queue_test.rb).
  def test_draining_the_release_queue_raises_off_the_main_thread
    error = raised_off_the_main_thread { Lota::Native.drain_release_queue }

    assert_instance_of ThreadError, error
    assert_equal "Lota::Native.drain_release_queue runs only on the main thread", error.message
  end

  def test_image_and_filesystem_work_off_the_main_thread
    pixel = Thread.new do
      Lota::Image::ImageData.new(Lota::Filesystem::FileData.new(PNG, "clear-1.png")).pixel(0, 0)
    end.value

    assert_equal [1.0, 1.0, 0.0, 1.0], pixel
  end
end
