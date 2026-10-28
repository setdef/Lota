# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "calls"
require_relative "cpp_source"
require_relative "statements"

module Bindings
  # What LÖVE's headers declare about a class: its methods' return and
  # parameter types, and its fields.
  #
  # Rule 14 turns a number LÖVE's C++ holds as an integer into an Integer
  # and the rest into Floats, but a wrap function pushes both with
  # lua_pushnumber. Only the C++ says which: Graphics::getLineWidth
  # returns a float, Graphics::getWidth an int. CppTypes reads class and
  # struct declarations from LÖVE's headers, following base classes and
  # typedefs (Colorf is ColorT<float>), to answer those questions, and
  # answers nil rather than guess when a declaration has a shape it does
  # not read.
  class CppTypes
    # One declared parameter.
    class Parameter < Data.define(:type, :name)
    end

    # One declared method. [const] says whether it is a const method.
    class Method < Data.define(:return_type, :parameters, :const)
    end

    # A class or struct: its header, body text, base classes, and
    # template parameter.
    class Declaration < Data.define(:path, :body, :bases, :template)
    end

    # Words the method pattern can take for a return type inside an inline
    # body (return random() * max), which declare nothing.
    KEYWORDS = %w[return else new delete throw case goto].freeze

    CLASS = /(?:template\s*<\s*typename\s+(?<template>\w+)\s*>\s*)?\b(?:class|struct)\s+(?:LOVE_EXPORT\s+)?(?<name>\w+)\s*(?:final\s*)?(?::\s*(?<bases>[^{;]+))?\{/
    TYPEDEF = /\btypedef\s+(?<target>[\w:<>\s]+?)\s+(?<name>\w+)\s*;|\busing\s+(?<name>\w+)\s*=\s*(?<target>[\w:<>\s]+?)\s*;/

    # Reads every header under +root+/src.
    def self.load(root)
      new(Dir.glob("src/**/*.h", base: root).sort.map { |path| CppSource.read(File.join(root, path), label: path) })
    end

    # [sources] CppSource objects of headers.
    def initialize(sources)
      @classes = Hash.new { |hash, name| hash[name] = [] }
      @typedefs = {}
      sources.each { |source| index(source) }
    end

    # The C++ type +name+ resolves to through typedefs, with a template's
    # argument split off: "Colorf" becomes ["ColorT", "float"].
    def resolve(name)
      seen = []
      name = name.to_s.strip.sub(/\Alove::(?:\w+::)?/, "")
      while @typedefs.key?(name) && !seen.include?(name)
        seen << name
        name = @typedefs.fetch(name)
      end
      match = name.match(/\A(?:\w+::)*(?<base>\w+)\s*(?:<\s*(?<argument>[^<>]+)\s*>)?\z/)
      match ? [match[:base], match[:argument]&.strip] : [name, nil]
    end

    # The methods named +method+ of class +name+, nearest class first,
    # preferring a declaration in +module_dir+ (src/modules/graphics) when
    # several classes share the name.
    def methods(name, method, module_dir: nil)
      each_declaration(name, module_dir) do |declaration, argument|
        found = declaration.body.to_enum(:scan, method_pattern(method)).filter_map do
          match = Regexp.last_match
          next if KEYWORDS.include?(match[:return].split.last)

          close = Statements.matching(declaration.body, match.end(0) - 1)
          Method.new(return_type: substitute(clean(match[:return]), declaration, argument),
            parameters: parameters(declaration.body[(match.end(0))...close]),
            const: declaration.body[(close + 1)..].match?(/\A\s*const\b/))
        end
        return found if found.any?
      end
      []
    end

    # The type of field +field+ of class +name+, or nil.
    def field(name, field, module_dir: nil)
      each_declaration(name, module_dir) do |declaration, argument|
        pattern = /^\s*(?<type>[\w:<>]+(?:\s*\*)?)(?:\s+|(?<=\*))(?<names>\w+(?:\s*,\s*\w+)*)\s*;/
        declaration.body.scan(pattern) do |type, names|
          return substitute(type.strip, declaration, argument) if names.split(",").map(&:strip).include?(field)
        end
      end
      nil
    end

    # Yields the declaration of +name+, then each of its bases'. A class
    # may share its name with its base in another namespace, as
    # love::physics::box2d::Body does love::physics::Body's, so a base is
    # looked for among the declarations not yet seen.
    private def each_declaration(name, module_dir, seen = [], &)
      base, argument = resolve(name)
      declaration = declaration(base, module_dir, seen) or return
      yield declaration, argument
      declaration.bases.each { |parent| each_declaration(parent, module_dir, seen + [declaration], &) }
    end

    # The declaration of +name+ in +module_dir+ itself, then in a folder
    # under it, then in src/common, or the only one.
    private def declaration(name, module_dir, seen = [])
      found = @classes[name] - seen
      found.find { |declaration| module_dir && File.dirname(declaration.path) == module_dir } ||
        found.find { |declaration| module_dir && declaration.path.start_with?(module_dir) } ||
        found.find { |declaration| declaration.path.start_with?("src/common/") } || ((found.size == 1) ? found.first : nil)
    end

    private def index(source)
      text = source.text
      text.to_enum(:scan, CLASS).each do
        match = Regexp.last_match
        close = Statements.matching(text, match.end(0) - 1)
        bases = match[:bases].to_s.split(",").map { |base| base.sub(/\A\s*(?:public|protected|private)\s+/, "").strip }
        @classes[match[:name]] << Declaration.new(path: source.path, body: text[(match.end(0))...close], bases:,
          template: match[:template])
      rescue Statements::Unreadable
        next
      end
      text.to_enum(:scan, TYPEDEF).each do
        match = Regexp.last_match
        @typedefs[match[:name]] ||= match[:target].strip.squeeze(" ")
      end
    end

    private def method_pattern(method)
      /^[ \t]*(?:(?:virtual|static|inline|explicit|LOVE_EXPORT)\s+)*(?<return>(?:const\s+)?[\w:]+(?:\s*<[^;(){}]*?>)?(?:\s*[*&])*)\s*\b#{Regexp.escape(method)}\s*\(/
    end

    private def parameters(text)
      return [] if text.strip.empty? || text.strip == "void"

      Calls.split(text).map do |parameter|
        declaration = parameter.sub(/=.*\z/m, "").strip
        name = declaration[/(\w+)\s*\z/, 1]
        Parameter.new(type: clean(declaration.delete_suffix(name).strip), name:)
      end
    end

    private def clean(type)
      type.strip.squeeze(" ")
    end

    private def substitute(type, declaration, argument)
      return type unless declaration.template && argument

      type.gsub(/\b#{Regexp.escape(declaration.template)}\b/, argument)
    end
  end
end
