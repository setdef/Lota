# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2017 Tim Moore
# SPDX-License-Identifier: MIT
#
# The MIT License (MIT)
#
# Copyright (c) 2017 Tim Moore
# Adapted for new moonshine API by Matthias Richter
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Translated to Ruby from moonshine's fastgaussianblur effect, as
# FLASH-BLIP carries it
# (test/fixtures/flash_blip/game/lib/shaders/fastgaussianblur.lua, lines
# 1-141), by the rules of doc/contributors/design/translation.md: newShader
# becomes Lota::Graphics::Shader.new (rule 2), and getWidth and getHeight
# width and height (rule 3); Shader#send keeps LÖVE's name. The function
# the Lua module returns is Moonshine::Fastgaussianblur.call, registered as
# the effect "fastgaussianblur" (see init.rb), and its local functions are
# lambdas over its locals, as Lua's closures are over their upvalues. The
# Lua's divisions divide as Floats, and its loop to the Float steps counts
# in Floats, as Lua's does; the shader's source is the Lua's, byte for
# byte. Shader#send is called through __send__(:send, ...), as RuboCop's
# Style/Send takes a call of send for Ruby's own Object#send.

require "lua"

module Moonshine
  # fastgaussianblur.lua: the function that makes the fast Gaussian blur.
  #
  # Bilinear Gaussian blur filter as detailed here: http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/
  # Produces near identical results to a standard Gaussian blur by using sub-pixel sampling,
  # this allows us to do ~1/2 the number of pixel lookups.
  module Fastgaussianblur
    # unroll convolution loop
    def self.build_shader(taps, offset, offset_type, sigma)
      taps = taps.floor
      sigma = (taps - 1) * offset / 6.0 unless sigma >= 1
      sigma = [sigma, 1].max

      steps = (taps + 1) / 2.0

      # Calculate gaussian function.
      g_offsets = []
      g_weights = []
      1.step(steps, 1) do |i|
        g_offsets << (offset * (i - 1))

        # We don't need to include the constant part of the gaussian function as we normalize later.
        # 1 / math.sqrt(2 * sigma ^ math.pi) * math.exp(-0.5 * ((offset - 0) / sigma) ^ 2 )
        g_weights << Math.exp(-0.5 * ((g_offsets.last - 0) ** 2) * 1 / (sigma ** 2))
      end

      # Calculate offsets and weights for sub-pixel samples.
      offsets = []
      weights = []
      g_weights.size.step(2, -2) do |i|
        o_a = g_offsets[i - 1]
        o_b = g_offsets[i - 2]
        w_a = g_weights[i - 1]
        w_b = g_weights[i - 2]
        w_b /= 2 if o_b.zero? # On center tap the middle is getting sampled twice so half weight.
        weight = w_a + w_b
        offsets << ((offset_type == "center") ? (o_a + o_b) / 2.0 : ((o_a * w_a) + (o_b * w_b)) / weight)
        weights << weight
      end

      code = [<<-GLSL.chomp]
    extern vec2 direction;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      GLSL

      norm = 0
      if g_weights.size.even?
        code << "vec4 c = vec4( 0.0 );"
      else
        weight = g_weights[0]
        norm += weight
        code << format("vec4 c = %f * texture2D(tex, tc);", weight)
      end

      tmpl = "c += %f * ( texture2D(tex, tc + %f * direction)+ texture2D(tex, tc - %f * direction));\n"
      offsets.each_index do |i|
        offset = offsets[i]
        weight = weights[i]
        norm += weight * 2
        code << format(tmpl, weight, offset, offset)
      end
      code << format("return c * vec4(%f) * color; }", 1.0 / norm)

      shader = code.join
      Lota::Graphics::Shader.new(shader)
    end
    private_class_method :build_shader

    def self.call(moonshine)
      taps = 7
      offset = 1
      offset_type = "weighted"
      sigma = -1
      shader = build_shader(taps, offset, offset_type, sigma)

      draw = lambda do |buffer, _shader|
        shader.__send__(:send, "direction", [1.0 / Lota::Graphics.width, 0.0])
        moonshine.draw_shader(buffer, shader)

        shader.__send__(:send, "direction", [0.0, 1.0 / Lota::Graphics.height])
        moonshine.draw_shader(buffer, shader)
      end

      setters = {}

      # Number of effective samples to take per pass. e.g. 3-tap is the current pixel and the neighbors each side.
      # More taps = larger blur, but slower.
      setters["taps"] = lambda do |v|
        num = Lua.tonumber(v)
        raise "Invalid value for `taps': Must be >= 3" unless num && num >= 3
        raise "Invalid value for `taps': Must be odd" unless num % 2 == 1

        taps = num.floor
        shader = build_shader(taps, offset, offset_type, sigma)
      end

      # Offset of each tap.
      # For highest quality this should be <=1 but if the image has low entropy we
      # can approximate the blur with a number > 1 and less taps, for better performance.
      setters["offset"] = lambda do |v|
        offset = Lua.tonumber(v) || 0
        shader = build_shader(taps, offset, offset_type, sigma)
      end

      # Offset type, either 'weighted' or 'center'.
      # 'weighted' gives a more accurate gaussian decay but can introduce modulation
      # for high frequency details.
      setters["offset_type"] = lambda do |v|
        unless v == "weighted" || v == "center"
          raise "Invalid value for 'offset_type': Must be 'weighted' or 'center'."
        end

        offset_type = v
        shader = build_shader(taps, offset, offset_type, sigma)
      end

      # Sigma value for gaussian distribution. You don't normally need to set this.
      setters["sigma"] = lambda do |v|
        sigma = Lua.tonumber(v) || -1
        shader = build_shader(taps, offset, offset_type, sigma)
      end

      moonshine::Effect.new(
        name: "fastgaussianblur",
        draw:,
        setters:,
        # no defaults here, as we dont want the shader to be built 3 times on startup
      )
    end
  end

  effect_modules["fastgaussianblur"] = Fastgaussianblur
end
# SPDX-SnippetEnd
