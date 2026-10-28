# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Bindings
  # Which LÖVE functions Lota::Native binds, and how, as ext/lota/bindings.rb
  # lists them.
  #
  # The generator writes a binding from a wrap function, but which
  # functions Lota binds, and which of a function's forms, is each story's
  # choice: Lota::Graphics.rectangle binds love.graphics.rectangle without
  # its rounded corners until a game needs them. Some bindings stay
  # hand-written because they are not a wrap function's straight-line
  # code (love.graphics.present hands LÖVE a screenshot callback). The
  # list records both, each hand-written one with its reason.
  class BindingList
    # A LÖVE function the generator binds.
    #
    # [love_name] Its name in LÖVE's notation (love.graphics.rectangle,
    #   Texture:isCanvas).
    # [arguments] How many of its arguments Lota binds, not counting a
    #   method's object; a form that reads more is left out.
    # [assume] Conditions in its body, by their C++ text, that pick the
    #   form Lota binds (lua_istable(L, 1) => false).
    # [reason] Why the form is limited, when it is.
    class Generated < Data.define(:love_name, :arguments, :assume, :reason)
    end

    # A LÖVE function bound by hand, with the reason it is not generated.
    class HandWritten < Data.define(:love_name, :reason)
    end

    # A LÖVE function whose wrap_*.lua code replaces its C++, which Lota
    # ports by hand from the Lua (ADR 001, section 7). The generator knows
    # which Lua replaces which C++, so the reason is its own: the file, the
    # line, and the guards it runs behind.
    #
    # [note] What else the port does, when it says more than the Lua.
    class FromLua < Data.define(:love_name, :note)
    end

    # Raised for an entry the list cannot hold.
    class Invalid < StandardError; end

    attr_reader :generated, :hand_written, :from_lua

    # Reads the list at +path+.
    def self.load(path)
      new.tap { |list| list.instance_eval(File.read(path), path) }
    end

    def initialize
      @generated = []
      @hand_written = []
      @from_lua = []
    end

    # Lists +love_name+ for the generator.
    def generate(love_name, arguments: nil, assume: {}, reason: nil)
      raise Invalid, "#{love_name} limits its form without a reason" if (arguments || assume.any?) && reason.nil?

      @generated << Generated.new(love_name:, arguments:, assume:, reason:)
    end

    # Lists +love_name+ as bound by hand, for +reason+.
    def bound_by_hand(love_name, reason:)
      @hand_written << HandWritten.new(love_name:, reason:)
    end

    # Lists +love_name+ as ported by hand from the Lua that replaces its
    # C++ in LÖVE.
    def bound_from_lua(love_name, note: nil)
      @from_lua << FromLua.new(love_name:, note:)
    end

    # Every function listed, of every kind.
    def love_names
      (generated + hand_written + from_lua).map(&:love_name)
    end
  end

  # Names the rules leave open, decided once and recorded with a reason,
  # as binding_exceptions.rb lists them.
  #
  # ADR 001 settles names by rule, and a function no rule fits goes to the
  # maintainer as a question. A few such functions were bound before the
  # generator existed, so their names were decided by hand. This file
  # records those decisions, each with why, so the generator reproduces
  # them and the collision report still lists the function.
  class BindingExceptions
    # A Lota::Native name decided outside the rules.
    class Name < Data.define(:love_name, :native, :reason)
    end

    # Raised for an exception without a reason.
    class Invalid < StandardError; end

    attr_reader :names

    # Reads the exceptions at +path+.
    def self.load(path)
      new.tap { |exceptions| exceptions.instance_eval(File.read(path), path) }
    end

    def initialize
      @names = []
    end

    # Records that Lota::Native binds +love_name+ as +as+, for +reason+.
    def native_name(love_name, as:, reason:)
      raise Invalid, "#{love_name}'s exception has no reason" if reason.to_s.strip.empty?

      @names << Name.new(love_name:, native: as, reason:)
    end

    # The Name recorded for +love_name+, or nil.
    def native_for(love_name)
      @names.find { |name| name.love_name == love_name }
    end
  end
end
