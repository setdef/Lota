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
# Translated to Ruby from moonshine's crt effect, as FLASH-BLIP carries it
# (test/fixtures/flash_blip/game/lib/shaders/crt.lua, lines 1-86), by the
# rules of doc/contributors/design/translation.md: newShader becomes
# Lota::Graphics::Shader.new (rule 2); Shader#send keeps LÖVE's name. The
# function the Lua module returns is Moonshine::Crt.call, registered as
# the effect "crt" (see init.rb), and its setters keep moonshine's
# property names, distortionFactor and scaleFactor among them. Lua's
# { unpack(v) } copies the Array. The shader's source is the Lua's, byte
# for byte. Shader#send is called through __send__(:send, ...), as
# RuboCop's Style/Send takes a call of send for Ruby's own Object#send.

module Moonshine
  # crt.lua: the function that makes the CRT effect.
  module Crt
    def self.call(moonshine)
      # Barrel distortion adapted from Daniel Oaks (see commit cef01b67fd)
      # Added feather to mask out outside of distorted texture
      distortion_factor = nil
      shader = Lota::Graphics::Shader.new(<<-GLSL.chomp)
    extern vec2 distortionFactor;
    extern vec2 scaleFactor;
    extern number feather;

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
      // to barrel coordinates
      uv = uv * 2.0 - vec2(1.0);

      // distort
      uv *= scaleFactor;
      uv += (uv.yx*uv.yx) * uv * (distortionFactor - 1.0);
      number mask = (1.0 - smoothstep(1.0-feather,1.0,abs(uv.x)))
                  * (1.0 - smoothstep(1.0-feather,1.0,abs(uv.y)));

      // to cartesian coordinates
      uv = (uv + vec2(1.0)) / 2.0;

      return color * Texel(tex, uv) * mask;
    }
  
      GLSL

      setters = {}

      setters["distortionFactor"] = lambda do |v|
        raise "Invalid value for `distortionFactor'" unless v.is_a?(Array) && v.size == 2

        distortion_factor = v.dup
        shader.__send__(:send, "distortionFactor", v)
      end

      setters["x"] = lambda do |v|
        setters["distortionFactor"].call([v, distortion_factor[1]])
      end
      setters["y"] = lambda do |v|
        setters["distortionFactor"].call([distortion_factor[0], v])
      end

      setters["scaleFactor"] = lambda do |v|
        if v.is_a?(Array) && v.size == 2
          shader.__send__(:send, "scaleFactor", v)
        elsif v.is_a?(Numeric)
          shader.__send__(:send, "scaleFactor", [v, v])
        else
          raise "Invalid value for `scaleFactor'"
        end
      end

      setters["feather"] = lambda do |v|
        shader.__send__(:send, "feather", v)
      end

      defaults = {
        "distortionFactor" => [1.06, 1.065],
        "feather" => 0.02,
        "scaleFactor" => 1,
      }

      moonshine::Effect.new(
        name: "crt",
        shader:,
        setters:,
        defaults:,
      )
    end
  end

  effect_modules["crt"] = Crt
end
# SPDX-SnippetEnd
