# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "strscan"
require_relative "../../tasks/bindings/rules"

# Lövetest's tests and their skips, read from its own Lua
# (vendor/love/testing/tests), so that what Lota's translation must hold
# comes from LÖVE's source and not from the translation itself: a test
# Lota drops, or one it adds, differs from this list, and so does a skip
# Lövetest does not have.
#
# A test is a function Lövetest's files assign to love.test.MODULE.NAME,
# as its TestModule runs them (vendor/love/testing/classes/TestModule.lua).
# A skip is a call of test:skipTest with a string, with the conditions of
# the ifs it is inside, as the Lua writes them. It reads Lua as far as
# Lövetest's files need: strings, long strings, and comments hide what
# they hold, and blocks open at function, then, do, and repeat.
#
# It needs nothing loaded, so tasks ask it as the tests do.
module LovetestLua
  # Lövetest's test files.
  FOLDER = File.expand_path("../../vendor/love/testing/tests", __dir__)

  # One of Lövetest's tests: +module_name+ is the module it tests, as in
  # love.test.audio, and +name+ the function it is assigned to, as in
  # RecordingDevice.
  class Test < Data.define(:module_name, :name)
    # Lövetest's name for it: love.test.audio.RecordingDevice.
    def to_s = "love.test.#{module_name}.#{name}"

    # The method Lota's translation names it by: test_ and its name in
    # snake_case, by rules 13 and 36 of doc/contributors/design/
    # translation.md (Bindings::Rules.snake_case), so
    # love.test.window.getVSync is test_get_vsync.
    def method_name = "test_#{Bindings::Rules.snake_case(name)}"
  end

  # One of Lövetest's skips: the Test it skips, the +reason+ it gives, and
  # the +condition+ under which it skips, the conditions of the ifs around
  # it joined with "and", each written as the Lua writes it and, in an
  # else, inside "not (...)"; "" for a skip in no if.
  Skip = Data.define(:test, :reason, :condition)

  # A source the reader cannot follow, such as an if whose condition it
  # cannot find, or a skip outside any test.
  class Unreadable < StandardError; end

  # What the reader stops at: comments, strings, a skip with its reason,
  # and the keywords that open and close Lua's blocks.
  TOKEN = /
    (?<comment>--\[(?<level>=*)\[.*?\]\k<level>\]|--[^\n]*)
    | (?<skip>test:skipTest\(\s*(?<reason>'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*"))
    | (?<string>\[(?<long>=*)\[.*?\]\k<long>\]|'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*")
    | (?<!\.|:)\b(?<keyword>if|elseif|then|else|end|function|do|repeat|until)\b
  /mx

  # Where a test starts: love.test.MODULE.NAME = function, at the start of
  # a line.
  TEST_START = /^love\.test\.(\w+)\.(\w+)\s*=\s*\z/

  # A block the reader is inside: an if, with the conditions of its
  # branches so far (+negated+, those the branch it is in is the else of,
  # and +current+, the branch's own, or nil in an else), or another block,
  # with the Test it starts when it is a test's function.
  Block = Struct.new(:if, :negated, :current, :test)

  class << self
    # Every test of Lövetest's, in its files' order.
    def tests = read.fetch(:tests)

    # Every skip of Lövetest's, in its files' order.
    def skips = read.fetch(:skips)

    # The tests and skips of every file of Lövetest's, read once.
    def read
      @read ||= Dir[File.join(FOLDER, "*.lua")].map { |file| parse(File.read(file)) }.then do |files|
        { tests: files.flat_map { |file| file.fetch(:tests) }.freeze, skips: files.flat_map { |file| file.fetch(:skips) }.freeze }
      end
    end

    # The tests and skips of the Lua +source+ of one of Lövetest's files.
    def parse(source)
      tests = []
      skips = []
      blocks = []
      scanner = StringScanner.new(source)
      while scanner.skip_until(TOKEN)
        if (keyword = scanner[:keyword])
          keyword(keyword, scanner, source, blocks, tests)
        elsif scanner[:skip]
          skips << skip(scanner[:reason], blocks)
        end
      end
      raise Unreadable, "#{blocks.size} blocks never end" unless blocks.empty?

      { tests:, skips: }
    end

    private def keyword(keyword, scanner, source, blocks, tests)
      case keyword
      when "function" then blocks << Block.new(false, [], nil, test_at(scanner, source, blocks, tests))
      when "if" then blocks << Block.new(true, [], condition(scanner), nil)
      when "elseif", "else"
        block = branch(blocks)
        block.negated << block.current
        block.current = (keyword == "elseif") ? condition(scanner) : nil
      when "do", "repeat" then blocks << Block.new(false, [], nil, nil)
      when "end", "until" then blocks.pop || raise(Unreadable, "an #{keyword} closes no block")
      end
    end

    # The Test a function starts, when the line before it assigns it to
    # love.test.MODULE.NAME at the top of the file. The scanner counts in
    # bytes, as does this.
    private def test_at(scanner, source, blocks, tests)
      start = scanner.pos - scanner.matched_size
      line_start = source.byterindex("\n", start - 1)&.succ || 0
      match = source.byteslice(line_start...start).match(TEST_START)
      return unless match && blocks.empty?

      Test.new(module_name: match[1], name: match[2]).tap { |test| tests << test }
    end

    # The if's condition: the source between if (or elseif) and then.
    private def condition(scanner)
      start = scanner.pos
      text = nil
      while scanner.skip_until(TOKEN)
        next unless scanner[:keyword]
        raise Unreadable, "an if at #{start} has #{scanner[:keyword]} before then" unless scanner[:keyword] == "then"

        text = scanner.string.byteslice(start...(scanner.pos - scanner.matched_size))
        break
      end
      text&.strip&.gsub(/\s+/, " ") || raise(Unreadable, "an if at #{start} has no then")
    end

    private def branch(blocks)
      blocks.last&.if ? blocks.last : raise(Unreadable, "an else or elseif outside an if")
    end

    private def skip(literal, blocks)
      test = blocks.first&.test || raise(Unreadable, "a skip outside a test: #{literal}")
      conditions = blocks.select(&:if).flat_map { |block| [*block.negated.map { |c| "not (#{c})" }, *block.current] }
      Skip.new(test:, reason: literal[1...-1].gsub(/\\(.)/, '\1'), condition: conditions.join(" and "))
    end
  end
end
