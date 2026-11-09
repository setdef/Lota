# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # The raw pointers Lota gives where LÖVE gives Lua an address, as
  # Lota::Data#pointer, Lota::Data#ffi_pointer, and Lota::Window.pointer
  # do: each is a Fiddle::Pointer, Ruby's own FFI's.
  #
  # Fiddle is a gem of its own, bundled with Ruby since 4.0.0, which Lota
  # does not depend on: a game that wants pointers adds
  # <tt>gem "fiddle"</tt> to its Gemfile. Fledge's iOS runtime leaves
  # Fiddle out, as the App Store asks, so depending on it would put it in
  # every phone build.
  #
  # === Example
  #
  #   Lota::Pointer.at(address, 16).size # => 16
  module Pointer
    # What a game is told when Fiddle will not load.
    MISSING = "Lota's raw pointers (Lota::Data#pointer, Lota::Data#ffi_pointer, and Lota::Window.pointer) are " \
      'Fiddle::Pointers, and Fiddle would not load. Add gem "fiddle" to your Gemfile and run bundle install.'

    # A Fiddle::Pointer to +address+, an Integer, of +size+ bytes, 0 when
    # LÖVE gives no size.
    #
    # Requires Fiddle the first time, and raises LoadError, saying to add
    # <tt>gem "fiddle"</tt> to the Gemfile, when it will not load.
    #
    # === Example
    #
    #   Lota::Pointer.at(0).null? # => true
    def self.at(address, size = 0)
      begin
        require "fiddle"
      rescue LoadError => e
        raise LoadError, "#{MISSING} (#{e.message})"
      end
      Fiddle::Pointer.new(address, size)
    end
  end
end
