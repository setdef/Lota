# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
  # SPDX-License-Identifier: Zlib

  # The record of deprecated names a game has used, ported from LÖVE's
  # src/common/deprecation.cpp, which LÖVE's wrap functions mark through
  # luax_markdeprecated (src/common/runtime.cpp:1074-1091). Where Lota
  # ports a wrap function that marks a name, as Lota::Window.set_mode marks
  # its +highdpi+ setting, it marks it here.
  #
  # The first use of each name prints a notice, as LÖVE prints one, while
  # output is on. Lota::Boot turns output on unless the game is fused, as
  # boot.lua does. LÖVE begins its notices with its own name; Lota's
  # begin with Lota's.
  #
  # === Example
  #
  #   Lota::Deprecation.mark("window.highdpi", :field, :replaced, "t.highdpi in Lota.conf")
  #   # Lota - Warning: main.rb:4: Using deprecated field window.highdpi (replaced by t.highdpi in Lota.conf)
  module Deprecation
    # The kinds of API a name can be, LÖVE's APIType names
    # (deprecation.cpp:192-203), each with the words its notice puts
    # before the name.
    API_TYPES = {
      function: "function ",
      functionvariant: "function variant in ",
      method: "method ",
      methodvariant: "method variant in ",
      callback: "callback ",
      field: "field ",
      constant: "constant ",
      custom: "",
    }.freeze

    # How a name was deprecated, LÖVE's DeprecationType names
    # (deprecation.cpp:205-211).
    DEPRECATION_TYPES = %i[noreplacement replaced renamed].freeze

    # One deprecated name's record, as DeprecationInfo holds it
    # (common/deprecation.h). :nodoc:
    Info = Struct.new(:type, :api_type, :uses, :name, :replacement, :where)

    @deprecated = {} #: Hash[String, Info]
    @output = false

    # Marks +name+ used, as luax_markdeprecated does, and prints its notice
    # on its first use while output is on.
    #
    # [name] The deprecated name, as a String.
    # [api] Which kind of API it is, a key of API_TYPES.
    # [type] How it was deprecated, one of DEPRECATION_TYPES.
    # [replacement] What replaced it, or its new name; ignored for
    #   +:noreplacement+.
    # [where] Where it was used, as luaL_where gives it: a file and line
    #   and a colon and space, or an empty String.
    #
    # Raises ArgumentError for an unknown +api+ or +type+, as LÖVE does.
    def self.mark(name, api, type = :noreplacement, replacement = nil, where: "")
      raise ArgumentError, "Invalid API type '#{api}'" unless API_TYPES.key?(api)
      raise ArgumentError, "Invalid deprecation type '#{type}'" unless DEPRECATION_TYPES.include?(type)

      info = @deprecated[name]
      if info
        info.uses += 1
      else
        info = Info.new(type, api, 1, name, replacement.to_s, where)
        @deprecated[name] = info
        print_notice(info) if @output
      end
      nil
    end

    # Turns the printing of notices on or off, as
    # setDeprecationOutputEnabled does: turning it on prints the notice of
    # each name used exactly once so far.
    def self.output=(enable)
      return if enable == @output

      @output = enable
      @deprecated.each_value { |info| print_notice(info) if info.uses == 1 } if enable
    end

    # Whether notices are printed, as isDeprecationOutputEnabled answers.
    def self.output?
      @output
    end

    # The notice of +info+, as getDeprecationNotice writes it with where
    # it was used. :nodoc:
    def self.notice(info)
      notice = +"#{info.where}Using deprecated #{API_TYPES.fetch(info.api_type)}#{info.name}"
      unless info.replacement.empty?
        notice << " (replaced by #{info.replacement})" if info.type == :replaced
        notice << " (renamed to #{info.replacement})" if info.type == :renamed
      end
      notice
    end

    # printDeprecationNotice (deprecation.cpp:69-73).
    private_class_method def self.print_notice(info)
      $stdout.puts("Lota - Warning: #{notice(info)}")
    end
  end
  # SPDX-SnippetEnd
end
