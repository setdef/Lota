# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require "json"

# The notices of deprecated names drawn over a frame, which the engine's
# own present draws (vendor/love/src/modules/graphics/Deprecations.cpp:
# 41-130, called from opengl/Graphics.cpp:1223, vulkan/Graphics.cpp:597
# and metal/Graphics.mm:1689) from the record in src/common/deprecation.cpp,
# which Lota::Deprecation keeps beside its own. The text, font, and
# fade are the engine's code, so these tests check that Lota reaches it:
# the band LÖVE draws is on the frame exactly when the notices are on, and
# a notice Lota::Deprecation marks is in it.
#
# A notice stays on the frame for 20 seconds of the real clock, and the
# engine's record cannot be cleared, so a process that drew one would
# show it on the frames of the tests that run after. These tests run in a
# process of their own.
class DeprecationDrawingTest < Minitest::Test
  include NativeHelper

  LIB = File.expand_path("../../lib", __dir__)

  # What the process draws and prints, in order. The band is black at 0.85
  # alpha over the white frame (Deprecations.cpp:113-114), so 0.15 where
  # no text is drawn, and at least 600 pixels wide, the whole window's.
  SCRIPT = <<~RUBY
    require "json"
    require #{File.expand_path('../engine_helper', __dir__).dump}

    def frame
      frames = []
      Lota::Native::Graphics.capture_screenshot(-> (image) { frames << image })
      Lota::Graphics.clear(1, 1, 1)
      Lota::Graphics.present
      Lota::Image::ImageData.__send__(:from_native, frames.fetch(0))
    end

    def corner(image) = image.pixel(image.width - 1, image.height - 1).first

    def lit(image)
      ((image.height - 40)...image.height).sum { |y| (0...image.width).count { |x| image.pixel(x, y).first > 0.5 && image.pixel(x, y).first < 1 } }
    end

    EngineHelper.open_window
    Lota::Deprecation.output = false
    Lota::Deprecation.mark("silent.hidden", :function, where: "a.rb:1: ")
    image = frame
    puts "RESULT " + JSON.generate(step: "hidden", top: image.pixel(0, 0), corner: corner(image))

    Lota::Deprecation.output = true
    image = frame
    puts "RESULT " + JSON.generate(step: "shown", corner: corner(image))

    Lota::Deprecation.mark("silent.band", :field, :replaced, "silent.other", where: "a.rb:2: ")
    image = frame
    puts "RESULT " + JSON.generate(step: "marked", top: image.pixel(0, 0), corner: corner(image), lit: lit(image))
  RUBY

  def self.process
    @run ||= new("run").capture2e({}, RbConfig.ruby, "-I", LIB, "-e", SCRIPT)
  end

  def results
    output, status = self.class.process
    assert_predicate status, :success?, output
    output.lines.grep(/\ARESULT /).to_h { |line| JSON.parse(line.delete_prefix("RESULT ")).then { |hash| [hash.delete("step"), hash] } }
  end

  # Names marked while output was off are drawn once it is turned on, as
  # they are printed, and not before.
  def test_names_marked_with_output_off_are_drawn_when_it_is_turned_on
    hidden = results.fetch("hidden")

    assert_equal [1.0, 1.0, 1.0, 1.0], hidden.fetch("top")
    assert_equal 1.0, hidden.fetch("corner")
    assert_in_delta 0.15, results.fetch("shown").fetch("corner"), 0.02
  end

  def test_a_notice_marked_with_output_on_is_drawn_over_the_frame_in_a_dark_band
    marked = results.fetch("marked")

    assert_equal [1.0, 1.0, 1.0, 1.0], marked.fetch("top")
    assert_in_delta 0.15, marked.fetch("corner"), 0.02
  end

  # The engine prints a notice as it marks one ("LOVE - Warning:",
  # deprecation.cpp:69-73); Lota prints its own and the engine's record
  # must stay silent, while it draws what it recorded.
  def test_the_engine_draws_what_it_records_without_printing_it
    output, = self.class.process

    assert_in_delta 0.15, results.fetch("marked").fetch("corner"), 0.02
    assert_empty output.lines.grep(/LOVE - Warning/)
    assert_equal [
      "Lota - Warning: a.rb:1: Using deprecated function silent.hidden\n",
      "Lota - Warning: a.rb:2: Using deprecated field silent.band (replaced by silent.other)\n",
    ], output.lines.grep(/Warning:.*silent\./)
  end

  # Text of the colour (1, 0.9, 0.8) (Deprecations.cpp:116-120) lights
  # some pixels of the band above its dark fill.
  def test_the_band_holds_text
    assert_operator results.fetch("marked").fetch("lit"), :>, 20
  end
end
