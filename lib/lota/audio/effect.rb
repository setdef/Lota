# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Audio
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    #
    # The name of every setting of every type of effect LÖVE has
    # (src/modules/audio/Effect.cpp:179-292), each once, which are the
    # fields of an Effect.
    EFFECT_SETTINGS = %i[
      type
      volume
      gain
      highgain
      density
      diffusion
      decaytime
      decayhighratio
      earlygain
      earlydelay
      lategain
      latedelay
      roomrolloff
      airabsorption
      highlimit
      waveform
      phase
      rate
      depth
      feedback
      delay
      edge
      lowcut
      center
      bandwidth
      tapdelay
      damping
      spread
      frequency
      highcut
      enable
      lowgain
      lowmidgain
      lowmidfrequency
      lowmidbandwidth
      highmidgain
      highmidfrequency
      highmidbandwidth
].freeze

    # The settings of an effect, as Lota::Audio.effect returns them,
    # matching the table love.audio.getEffect returns
    # (src/modules/audio/wrap_Audio.cpp, w_getEffect), a frozen record
    # with LÖVE's field names (ADR 001, rule 10).
    #
    # LÖVE's table holds the settings the effect was given, which depend
    # on its type, so the record has a field for every setting of every
    # type LÖVE has (src/modules/audio/Effect.cpp:179-292), and those the
    # effect was not given are +nil+, as Lua reads a missing key. Its
    # +type+ and +waveform+, the String settings the engine gives, are
    # Symbols (rule 9), +enable+ is +true+ or +false+, and the rest are
    # Floats.
    #
    # === Example
    #
    #   Lota::Audio.set_effect("echo", type: :echo, delay: 0.1)
    #   Lota::Audio.effect("echo").delay # => 0.10000000149011612
    #   Lota::Audio.effect("echo")[:feedback] # => nil
    class Effect < ::Data.define(*EFFECT_SETTINGS)
      include Record

      # The Effect of +pairs+, the names and values the engine gives, with
      # every other field +nil+. :nodoc:
      def self.of(pairs)
        given = pairs.to_h { |name, value| [name.to_sym, value.is_a?(String) ? value.to_sym : value] }
        new(*EFFECT_SETTINGS.map { |member| given[member] })
      end
    end
    # SPDX-SnippetEnd
  end
end
