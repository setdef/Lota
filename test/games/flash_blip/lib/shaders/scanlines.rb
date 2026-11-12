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
# Translated to Ruby from moonshine's scanlines effect, as FLASH-BLIP
# carries it (test/fixtures/flash_blip/game/lib/shaders/scanlines.lua,
# lines 1-73), by the rules of doc/contributors/design/translation.md:
# newShader becomes Lota::Graphics::Shader.new (rule 2), and getHeight
# height (rule 3); Shader#send keeps LÖVE's name. The function the Lua
# module returns is Moonshine::Scanlines.call, registered as the effect
# "scanlines" (see init.rb). Its defaults, a table its setters read by
# field and moonshine walks with pairs, are a Hash. The shader's source is
# the Lua's, byte for byte. Shader#send is called through
# __send__(:send, ...), as RuboCop's Style/Send takes a call of send for
# Ruby's own Object#send.
#
# The color setter falls back to defaults.color[0], [1], and [2], which in
# Lua's tables, counted from 1, are nil and the color's first two zeros:
# so the Ruby falls back to nothing for the red, and to the first and
# second elements for the green and blue.

require "lua"

module Moonshine
  # scanlines.lua: the function that makes the scanlines effect.
  module Scanlines
    def self.call(moonshine)
      shader = Lota::Graphics::Shader.new(<<-GLSL.chomp)
    extern number width;
    extern number phase;
    extern number thickness;
    extern number opacity;
    extern vec3 color;
    vec4 effect(vec4 c, Image tex, vec2 tc, vec2 _) {
      number v = 0.5*(sin(tc.y * 3.14159 / width * love_ScreenSize.y + phase) + 1.0);
      c = Texel(tex,tc);
      //c.rgb = mix(color, c.rgb, mix(1, pow(v, thickness), opacity));
      c.rgb -= (color - c.rgb) * (pow(v,thickness) - 1.0) * opacity;
      return c;
    }
      GLSL

      defaults = {
        "width" => 2,
        "phase" => 0,
        "thickness" => 1,
        "opacity" => 1,
        "color" => [0, 0, 0],
      }

      setters = {}
      setters["width"] = lambda do |v|
        shader.__send__(:send, "width", Lua.tonumber(v) || defaults["width"])
      end
      setters["frequency"] = lambda do |v|
        shader.__send__(:send, "width", Lota::Graphics.height.fdiv(Lua.tonumber(v) || Lota::Graphics.height))
      end
      setters["phase"] = lambda do |v|
        shader.__send__(:send, "phase", Lua.tonumber(v) || defaults["phase"])
      end
      setters["thickness"] = lambda do |v|
        shader.__send__(:send, "thickness", [0, Lua.tonumber(v) || defaults["thickness"]].max)
      end
      setters["opacity"] = lambda do |v|
        shader.__send__(:send, "opacity", (Lua.tonumber(v) || defaults["opacity"]).clamp(0, 1))
      end
      setters["color"] = lambda do |c|
        raise "Invalid value for `color'" unless c.is_a?(Array) && c.size == 3

        shader.__send__(:send, "color", [
          Lua.tonumber(c[0]) / 255.0, # Lua's fallback, defaults.color[0], is nil
          (Lua.tonumber(c[1]) || defaults["color"][0]) / 255.0,
          (Lua.tonumber(c[2]) || defaults["color"][1]) / 255.0,
        ])
      end

      moonshine::Effect.new(
        name: "scanlines",
        shader:,
        setters:,
        defaults:,
      )
    end
  end

  effect_modules["scanlines"] = Scanlines
end
# SPDX-SnippetEnd
