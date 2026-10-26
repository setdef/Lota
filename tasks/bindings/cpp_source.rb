# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Bindings
  # A C++ source file read for its structure, not compiled.
  #
  # LÖVE's wrap_*.cpp files follow a handful of patterns: functions of one
  # lua_State* argument, luaL_Reg tables that name them, and luaopen_*
  # functions that register those tables. Reading those patterns needs no
  # C++ parser, only text the patterns cannot be fooled by: comments
  # blanked out (LÖVE comments out whole calls, such as
  # luax_markdeprecated in wrap_Graphics.cpp) and preprocessor lines set
  # aside. CppSource blanks both with spaces, so every offset still points
  # at the same line and column of the file.
  class CppSource
    attr_reader :path, :text, :raw

    # [path] The file's path, as reports name it.
    # [raw] The file's contents.
    def initialize(path, raw)
      @path = path
      @raw = raw
      @text = self.class.blank_preprocessor(self.class.blank_comments(raw))
      @line_starts = [0]
      raw.each_char.with_index { |char, index| @line_starts << (index + 1) if char == "\n" }
    end

    # Reads +path+ from disk, naming it +label+ in reports.
    def self.read(path, label: path)
      new(label, File.read(path, encoding: "UTF-8"))
    end

    # The 1-based line of +offset+.
    def line_of(offset)
      @line_starts.bsearch_index { |start| start > offset } || @line_starts.size
    end

    # +source+ with every comment turned to spaces, newlines kept, and
    # string and character literals left whole.
    def self.blank_comments(source)
      out = +""
      index = 0
      while index < source.length
        finish = token_end(source, index)
        piece = source[index...finish]
        out << (piece.start_with?("//", "/*") ? blank(piece) : piece)
        index = finish
      end
      out
    end

    # +source+ with every preprocessor directive, continuation lines
    # included, turned to spaces.
    def self.blank_preprocessor(source)
      continued = false
      source.lines.map do |line|
        directive = continued || line.match?(/\A[ \t]*#/)
        continued = directive && line.chomp.end_with?("\\")
        directive ? blank(line) : line
      end.join
    end

    # The end of the comment, literal, or single character at +start+.
    private_class_method def self.token_end(source, start)
      case source[start, 2]
      when "//" then source.index("\n", start) || source.length
      when "/*" then (source.index("*/", start + 2) || (source.length - 2)) + 2
      else
        return raw_string_end(source, start) if source[start, 3] == 'R"('
        return literal_end(source, start) if ['"', "'"].include?(source[start])

        start + 1
      end
    end

    # The end of the raw string literal R"(...)" at +start+.
    private_class_method def self.raw_string_end(source, start)
      (source.index(')"', start + 3) || (source.length - 2)) + 2
    end

    # The end of the string or character literal at +start+.
    private_class_method def self.literal_end(source, start)
      quote = source[start]
      index = start + 1
      while index < source.length
        return index + 1 if source[index] == quote
        return index if source[index] == "\n"

        index += (source[index] == "\\") ? 2 : 1
      end
      index
    end

    # +text+ with everything but newlines turned to spaces.
    def self.blank(text)
      text.gsub(/[^\n]/, " ")
    end
  end
end
