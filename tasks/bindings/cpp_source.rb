# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    # One token for blank_comments: a comment, a raw string literal, or a
    # string or character literal, each to its end (a literal ends at its
    # line's end if no quote closes it, and a comment or raw string that
    # never closes runs to the file's end); else a run of text that can
    # start none of those, or one character. One pass of one expression
    # reads a file in milliseconds, where a loop that indexed it character
    # by character took up to seconds on a file with non-ASCII text, which
    # Ruby indexes by counting from the start.
    TOKEN = %r{
      //[^\n]* |
      /\*(?:.*?\*/|.*\z) |
      R"\((?:.*?\)"|.*\z) |
      "(?:[^"\\\n]|\\.)*(?:"|(?=\n)|\z) |
      '(?:[^'\\\n]|\\.)*(?:'|(?=\n)|\z) |
      [^/"'R]+ |
      .
    }mx

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
      source.gsub(TOKEN) { |piece| piece.start_with?("//", "/*") ? blank(piece) : piece }
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

    # +text+ with everything but newlines turned to spaces.
    def self.blank(text)
      text.gsub(/[^\n]/, " ")
    end
  end
end
