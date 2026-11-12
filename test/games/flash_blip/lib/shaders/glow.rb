# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2017 Matthias Richter
# SPDX-License-Identifier: 0BSD
#
# Public domain:
#
# Copyright (C) 2017 by Matthias Richter <vrld@vrld.org>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
# FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.
#
# Translated to Ruby from moonshine's glow effect, as FLASH-BLIP carries it
# (test/fixtures/flash_blip/game/lib/shaders/glow.lua, lines 1-168), by the
# rules of doc/contributors/design/translation.md: newShader and newCanvas
# become Lota::Graphics::Shader.new and Lota::Graphics::Canvas.new (rules
# 2 and 25), getWidth and getHeight width and height (rule 3), the setters
# writers (rules 5 and 6), and the blend modes symbols (rule 9);
# Shader#send keeps LÖVE's name. The function the Lua module returns is
# Moonshine::Glow.call, registered as the effect "glow" (see init.rb), and
# its local functions are lambdas over its locals, as Lua's closures are
# over their upvalues. The shaders' source is the Lua's, byte for byte.
# Shader#send is called through __send__(:send, ...), as RuboCop's
# Style/Send takes a call of send for Ruby's own Object#send.

require "lua"

module Moonshine
  # glow.lua: the function that makes the glow effect.
  module Glow
    # One weight of the blur's kernel.
    Weight = Struct.new(:offset, :w)

    # Optimizations:
    #  - mediump precision
    #  - compile-time normalized weights
    #  - fewer temporaries and less vector construction
    #  - early-out for sigma == 0
    def self.make_blur_shader(sigma)
      # ensure numeric
      sigma = [0, Lua.tonumber(sigma) || 0].max
      if sigma.zero?
        # passthrough shader (very cheap)
        return Lota::Graphics::Shader.new(<<-GLSL.chomp)
      extern vec2 direction;
      vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
        // use direction to avoid it being optimized out
        vec2 d = direction * 0.0;
        return Texel(texture, tc) * color;
      }
        GLSL
      end

      # support radius (same heuristic as original)
      support = [1, ((3 * sigma) + 0.5).floor].max
      one_by_two_sigma_sq = 1.0 / (2.0 * sigma * sigma)

      # compute gaussian weights and normalize (done in Lua at "compile" time)
      weights = []
      norm = 0.0
      (-support..support).each do |i|
        w = Math.exp(-(i * i) * one_by_two_sigma_sq)
        weights << Weight.new(i, w)
        norm += w
      end
      weights.each do |weight|
        weight.w /= norm
      end

      # Build shader source with unrolled samples.
      # Small micro-optimizations:
      #  * store direction into local 'd'
      #  * avoid constructing vec4 repeatedly where possible
      #  * use float literals with limited decimals to keep shader text compact
      lines = []
      lines << <<-GLSL.chomp
    extern vec2 direction;
    vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
      // prefer mediump computations on ES mobile GPUs when possible
      vec2 d = direction;
      vec4 c = vec4(0.0);
  
      GLSL

      # center sample (offset 0) will always exist
      # find center weight (offset 0)
      weights.each do |weight|
        if weight.offset.zero?
          lines << format("  c += vec4(%0.8f) * Texel(texture, tc);", weight.w)
          break
        end
      end

      # Unroll the rest. We'll produce one Texel fetch per offset (explicit),
      # but we avoid extra vec4 constructors and keep literals short.
      # This is still explicit convolution but avoids runtime loops/cost.
      weights.each do |weight|
        off = weight.offset
        # produce a line like: c += vec4(0.05000000) * Texel(texture, tc + d * 1.000000);
        lines << format("  c += vec4(%0.8f) * Texel(texture, tc + d * %0.6f);", weight.w, off) if off != 0
      end

      lines << <<-GLSL.chomp
      // multiply by input color once
      return c * color;
    }
      GLSL
      src = lines.join("\n")
      Lota::Graphics::Shader.new(src)
    end
    private_class_method :make_blur_shader

    def self.call(moonshine)
      blurshader = nil # set by setters.strength

      # threshold shader (kept minimal and optimized)
      threshold = Lota::Graphics::Shader.new(<<-GLSL.chomp)
    extern number min_luma;
    vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
      // Use mediump-ish ops implicitly; keep constants as const for compiler
      const vec3 luma_weights = vec3(0.299, 0.587, 0.114);
      vec4 px = Texel(texture, tc);
      float l = dot(px.rgb, luma_weights);
      // step(min_luma, l) returns 1.0 if l >= min_luma, else 0.0
      float m = step(min_luma, l);
      // multiply color and mask once
      return px * (m * color);
    }
      GLSL

      setters = {}
      setters["strength"] = lambda do |v|
        # constrain and rebuild blur shader
        s = [0, Lua.tonumber(v) || 1].max
        blurshader = make_blur_shader(s)
      end
      setters["min_luma"] = lambda do |v|
        threshold.__send__(:send, "min_luma", (Lua.tonumber(v) || 0.5).clamp(0, 1))
      end

      # keep the same canvas / draw flow as original
      scene = Lota::Graphics::Canvas.new
      draw = lambda do |buffer, _shader|
        front, back = buffer.call # scene so far is in `back'
        scene, back = back, scene # swap

        # 1: threshold (extract bright parts)
        Lota::Graphics.canvas = front
        Lota::Graphics.clear
        Lota::Graphics.shader = threshold
        Lota::Graphics.draw(scene)

        # 2: blur horizontal
        blurshader.__send__(:send, "direction", [1.0 / Lota::Graphics.width, 0.0])
        Lota::Graphics.canvas = back
        Lota::Graphics.clear
        Lota::Graphics.shader = blurshader
        Lota::Graphics.draw(front)

        # 3: blur vertical and composite (add)
        Lota::Graphics.canvas = front
        Lota::Graphics.clear

        # original scene without blur shader
        Lota::Graphics.shader = nil
        Lota::Graphics.blend_mode = :add, :premultiplied
        Lota::Graphics.draw(scene) # original scene

        # second pass of light blurring
        blurshader.__send__(:send, "direction", [0.0, 1.0 / Lota::Graphics.height])
        Lota::Graphics.shader = blurshader
        Lota::Graphics.draw(back)

        # restore things as they were before entering draw()
        Lota::Graphics.blend_mode = :alpha, :premultiplied
        scene = back
      end

      moonshine::Effect.new(
        name: "glow",
        draw:,
        setters:,
        defaults: { "min_luma" => 0.7, "strength" => 5 },
      )
    end
  end

  effect_modules["glow"] = Glow
end
# SPDX-SnippetEnd
