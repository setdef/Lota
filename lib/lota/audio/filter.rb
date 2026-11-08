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
    # The settings of a Source's filter, as Source#filter and
    # Source#effect return them, matching the table Source:getFilter
    # returns (src/modules/audio/wrap_Source.cpp, getFilterWriteFilter), a
    # frozen record with LÖVE's field names (ADR 001, rule 10).
    #
    # Its +type+, the one String setting the engine gives, is
    # <tt>:lowpass</tt>, <tt>:highpass</tt>, or <tt>:bandpass</tt> (rule
    # 9), and +volume+, +lowgain+, and +highgain+ are Floats, or +nil+ for
    # a setting the filter's type does not have
    # (src/modules/audio/Filter.cpp:81-101): a low-pass filter has no
    # +lowgain+, as Lua reads a missing key.
    #
    # === Example
    #
    #   source.set_filter(type: :lowpass, volume: 0.5, highgain: 0.3)
    #   source.filter.lowgain # => nil
    class Filter < ::Data.define(:type, :volume, :lowgain, :highgain)
      include Record

      # The Filter of +pairs+, the names and values the engine gives, with
      # every other field +nil+. :nodoc:
      private_class_method def self.of(pairs)
        given = pairs.to_h { |name, value| [name.to_sym, value.is_a?(String) ? value.to_sym : value] }
        new(*%i[type volume lowgain highgain].map { |member| given[member] })
      end
    end
    # SPDX-SnippetEnd
  end
end
