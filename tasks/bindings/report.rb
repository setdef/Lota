# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "rules"
require_relative "survey"

module Bindings
  # The collision report: every LÖVE function the rules cannot translate
  # alone, for the maintainer to settle by new rules.
  #
  # ADR 001 settles names by rule, never case by case, and a function that
  # fits no rule or several becomes a question for a new rule (section 7).
  # Report lists them all, grouped by LÖVE module, each with the file and
  # line of its C++ and why it collides, then the functions the parser
  # could not read, which no rule can be checked against yet. It answers
  # nothing itself.
  class Report
    KINDS = {
      no_rule: "Fits no rule",
      several_rules: "Fits more than one rule",
      open: "A rule fits but leaves a decision open",
    }.freeze

    # [survey] A Survey.
    def initialize(survey)
      @survey = survey
    end

    # The report, as text.
    def to_s
      [header, *modules.map { |name, entries| section(name, entries) }, rule_7, summary].join("\n")
    end

    # How many functions each kind of collision holds, and how many the
    # parser could not read.
    def counts
      entries = @survey.entries
      KINDS.keys.to_h { |kind| [kind, entries.count { |entry| entry.collisions.any? { |c| c.kind == kind } }] }.merge(
        unreadable: entries.count { |entry| entry.source == :cpp && !entry.analysis.readable? },
        lua: entries.count { |entry| entry.source == :lua },
        outside: entries.count { |entry| entry.source == :outside },
        functions: entries.size,
        readable: entries.count(&:readable?)
      )
    end

    # The setters that return a value, by the wrap files, against the list
    # ADR 001 gives after its rule table: [missing from the list, listed
    # but returning nothing].
    # The third Array lists the listed setters the parser cannot read.
    def rule_7_difference
      setters = @survey.entries.select { |entry| entry.source == :cpp && entry.function.lua_name.start_with?("set") }
      readable, unreadable = setters.partition(&:readable?)
      returning = readable.select { |entry| entry.translation.rules.include?(7) }
      listed = Rules::RULE_7_SETTERS
      names = -> (entries) { entries.map { |entry| entry.function.love_name } }
      [
        names.(returning.reject { |entry| listed.include?(entry.function.lua_name) }),
        names.(readable.select { |entry| listed.include?(entry.function.lua_name) } - returning),
        names.(unreadable.select { |entry| listed.include?(entry.function.lua_name) }),
]
    end

    private def header
      <<~TEXT
        Lota binding report: every LÖVE function the rules of ADR 001 cannot translate alone.

        Each entry gives the function in LÖVE's notation, where its C++ is, and why it fits no rule,
        fits several, or leaves a rule's decision open. Settle each by a new rule in ADR 001's table,
        never case by case. Unreadable functions follow; the parser does not guess at their shape.
      TEXT
    end

    private def modules
      @survey.entries.group_by { |entry| entry.function.module_name }.sort
    end

    private def section(name, entries)
      lines = ["== love.#{name} (#{entries.size} functions)"]
      KINDS.each do |kind, title|
        hits = entries.flat_map { |entry| entry.collisions.select { |c| c.kind == kind }.map { |c| [entry, c] } }
        next if hits.empty?

        lines << "  #{title}:"
        hits.each { |entry, collision| lines << "    #{entry.function.love_name}  #{entry.function.location}  #{rules(collision)}#{collision.why}" }
      end
      unreadable = entries.select { |entry| entry.source != :cpp || !entry.analysis.readable? }
      if unreadable.any?
        lines << "  Not read by the parser:"
        unreadable.each { |entry| lines << "    #{entry.function.love_name}  #{entry.function.location}  #{unread(entry)}" }
      end
      replaced = entries.select { |entry| entry.source == :cpp && @survey.replaced_by_lua(entry.function.love_name) }
      if replaced.any?
        lines << "  Replaced by Lua, which Lota ports by hand rather than generate:"
        replaced.each do |entry|
          lua = @survey.replaced_by_lua(entry.function.love_name)
          lines << "    #{entry.function.love_name}  #{entry.function.location}  by #{lua.location} #{lua.condition}"
        end
      end
      "#{lines.join("\n")}\n"
    end

    private def rules(collision)
      collision.rules.empty? ? "" : "(rule #{collision.rules.join(', ')}) "
    end

    private def unread(entry)
      case entry.source
      when :lua then "defined in Lua (#{entry.function.parameters.join(', ')})#{replacing(entry)}, so it is ported by hand"
      when :outside then "its C++ is outside the wrap files"
      else entry.analysis.problems.uniq.join("; ")
      end
    end

    # For a Lua function that replaces a C++ one, which and when.
    private def replacing(entry)
      replaced = @survey.replaced_by_lua(entry.function.love_name)
      return "" unless replaced.equal?(entry.function)

      cpp = @survey.entries.find { |other| other.source == :cpp && other.function.love_name == entry.function.love_name }
      ", which replaces its C++ (#{cpp.function.location}) #{replaced.condition}"
    end

    private def rule_7
      missing, extra, unread = rule_7_difference.map { |names| names.empty? ? "none" : names.join(", ") }
      <<~TEXT
        == ADR 001's list of rule 7 setters, against the wrap files
          Setters that return a value but are not on the list: #{missing}
          Setters of a listed name that return nothing: #{extra}
          Setters of a listed name the parser cannot read: #{unread}
      TEXT
    end

    private def summary
      counts => { functions:, readable:, unreadable:, lua:, outside:, no_rule:, several_rules:, open: }
      <<~TEXT
        == Summary
          #{functions} functions: #{readable} read, #{unreadable} not readable, #{lua} defined in Lua, #{outside} outside the wrap files
          #{no_rule} fit no rule, #{several_rules} fit more than one, #{open} leave a rule's decision open
      TEXT
    end
  end
end
