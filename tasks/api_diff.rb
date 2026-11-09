# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "pathname"
require "rbs"

# Lota's public API as two trees of signatures declare it, compared
# (doc/contributors/releasing.md). A release that removes or changes what
# a game calls must say so with a Breaking: entry in CHANGELOG.md, which
# bumps MINOR; this is the check that one was not forgotten.
#
# The API is every public method, attribute, alias, constant, type alias,
# class, module, interface, and include declared under Lota, in sig/,
# which mirrors lib/ and the extension's generated signatures. A name
# gone from the after tree is removed. A name whose declaration the
# after tree no longer accepts is changed: for a method, an overload no
# overload after it accepts (every argument it took is still taken, as
# the same type or a wider one, no new argument is required, and what it
# returns is the same or narrower); for anything else, a declaration
# that differs. Widening and narrowing see through type aliases,
# optional types, unions, superclasses and included modules, and generic
# arguments, taken as covariant. Anything it cannot prove compatible
# counts as changed, so it errs toward asking for a Breaking: entry.
class ApiDiff
  # The namespace whose declarations are Lota's API.
  NAMESPACE = "::Lota"

  # Types that accept any value.
  UNIVERSAL = %w[top untyped ::BasicObject ::Object].freeze

  # Instance methods Ruby makes private whatever the signature says;
  # initialize is the signature of new.
  PRIVATE = %i[initialize_copy initialize_clone initialize_dup respond_to_missing?].freeze

  # [before] A directory of .rbs files, as the last release had them.
  # [after] A directory of .rbs files, as the release would have them.
  def initialize(before, after)
    @before = Api.new(before)
    @after = Api.new(after)
  end

  # The names the after tree declares and the before tree did not.
  def added
    (@after.names - @before.names).sort
  end

  # Each name removed, and each declaration changed, one line each.
  def breaks
    removed + changed
  end

  private def removed
    (@before.names - @after.names).sort.map { |name| "removed #{name}: #{@before.shapes(name).join(' | ')}" }
  end

  private def changed
    (@before.names & @after.names).sort.filter_map do |name|
      lost = @before.shapes(name).reject { |old| @after.shapes(name).any? { |new| kept?(old, new) } }
      next if lost.empty?

      "changed #{name}: #{lost.join(' | ')} is no longer accepted; now #{@after.shapes(name).join(' | ')}"
    end
  end

  private def kept?(old, new)
    return old == new unless old.is_a?(RBS::MethodType) && new.is_a?(RBS::MethodType)

    Overload.new(old, new, before: @before, after: @after).kept?
  end

  # The public declarations under NAMESPACE in one tree of signatures,
  # by name, each with the shapes it is declared with: the method types of
  # a method, or a string for anything else.
  class Api
    # The environment, with every type name absolute.
    attr_reader :env

    # [dir] A directory of .rbs files.
    def initialize(dir)
      @env = Api.environment(dir)
      @shapes = Hash.new { |hash, name| hash[name] = [] }
      collect
    end

    # RBS's core signatures and +dir+'s, with every type name absolute.
    def self.environment(dir)
      loader = RBS::EnvironmentLoader.new
      loader.add(path: Pathname(dir))
      RBS::Environment.from_loader(loader).resolve_type_names
    end

    # The names declared.
    def names
      @shapes.keys
    end

    # How +name+ is declared.
    def shapes(name)
      @shapes.fetch(name)
    end

    # The member types of +type+: a union's, an optional's with nil, and
    # an alias's, expanded; anything else is its own.
    def members(type, seen = [])
      case type
      when RBS::Types::Union then type.types.flat_map { |member| members(member, seen) }
      when RBS::Types::Optional then members(type.type, seen) + [RBS::Types::Bases::Nil.new(location: nil)]
      when RBS::Types::Alias then alias_members(type, seen)
      else [type]
      end
    end

    # The classes and modules +name+ inherits from or includes, itself
    # first, as type names.
    def ancestors(name, seen = [])
      return [] if seen.include?(name)

      entry = @env.class_decls[name]
      return [name] unless entry

      seen << name
      parents = entry.each_decl.flat_map do |decl|
        supers = decl.is_a?(RBS::AST::Declarations::Class) && decl.super_class ? [decl.super_class.name] : []
        supers + decl.members.grep(RBS::AST::Members::Include).map(&:name)
      end
      [name] + parents.uniq.flat_map { |parent| ancestors(parent, seen) }
    end

    private def alias_members(type, seen)
      entry = @env.type_alias_decls[type.name]
      return [type] if entry.nil? || !type.args.empty? || seen.include?(type.name)

      members(entry.decl.type, seen + [type.name])
    end

    private def lota?(name)
      text = name.to_s
      text == NAMESPACE || text.start_with?("#{NAMESPACE}::")
    end

    private def display(name)
      name.to_s.delete_prefix("::")
    end

    private def add(name, shape)
      @shapes[name] << shape unless @shapes[name].include?(shape)
    end

    private def collect
      @env.class_decls.each { |name, entry| entry.each_decl { |decl| collect_module(name, decl) } if lota?(name) }
      @env.interface_decls.each { |name, entry| collect_members(display(name), entry.decl.members, interface: true) if lota?(name) }
      @env.constant_decls.each { |name, entry| add(display(name), entry.decl.type.to_s) if lota?(name) }
      @env.type_alias_decls.each { |name, entry| add(display(name), "type #{entry.decl.type}") if lota?(name) }
      @env.class_alias_decls.each { |name, entry| add(display(name), "= #{display(entry.decl.old_name)}") if lota?(name) }
    end

    private def collect_module(name, decl)
      owner = display(name)
      if decl.is_a?(RBS::AST::Declarations::Class)
        add(owner, decl.super_class ? "class < #{decl.super_class.name}" : "class")
      else
        add(owner, "module")
      end
      collect_members(owner, decl.members)
    end

    private def collect_members(owner, members, interface: false)
      visibility = :public
      members.each do |member|
        case member
        when RBS::AST::Members::Public, RBS::AST::Members::Private
          visibility = member.is_a?(RBS::AST::Members::Public) ? :public : :private
        when RBS::AST::Members::Include, RBS::AST::Members::Extend, RBS::AST::Members::Prepend
          add("#{owner} #{member.class.name.split('::').last.downcase}s #{display(member.name)}", "yes")
        else
          next if !interface && (member_visibility(member) || visibility) == :private

          collect_member(owner, member)
        end
      end
    end

    private def member_visibility(member)
      member.visibility if member.respond_to?(:visibility)
    end

    private def collect_member(owner, member)
      case member
      when RBS::AST::Members::MethodDefinition then collect_method(owner, member)
      when RBS::AST::Members::AttrReader then add_attribute(owner, member, reader: true, writer: false)
      when RBS::AST::Members::AttrWriter then add_attribute(owner, member, reader: false, writer: true)
      when RBS::AST::Members::AttrAccessor then add_attribute(owner, member, reader: true, writer: true)
      when RBS::AST::Members::Alias then add(method_name(owner, member.kind, member.new_name), "alias of #{member.old_name}")
      end
    end

    private def collect_method(owner, member)
      return if member.kind == :instance && PRIVATE.include?(member.name)

      name =
        if member.kind == :instance && member.name == :initialize
          "#{owner}.new"
        else
          method_name(owner, member.kind == :instance ? :instance : :singleton, member.name)
        end
      member.overloads.each { |overload| add(name, overload.method_type) }
    end

    private def add_attribute(owner, member, reader:, writer:)
      kind = member.kind == :singleton ? :singleton : :instance
      add(method_name(owner, kind, member.name), RBS::Parser.parse_method_type("() -> #{member.type}")) if reader
      add(method_name(owner, kind, :"#{member.name}="), RBS::Parser.parse_method_type("(#{member.type} value) -> #{member.type}")) if writer
    end

    private def method_name(owner, kind, name)
      "#{owner}#{kind == :instance ? '#' : '.'}#{name}"
    end
  end

  # One overload of a method in the last release, and one in the next,
  # and whether the next accepts every call the last accepted and returns
  # nothing the last did not promise.
  class Overload
    # [old] The last release's overload, an RBS::MethodType.
    # [new] The next release's overload.
    # [before] The last release's Api, which expands +old+'s aliases.
    # [after] The next release's Api, which expands +new+'s aliases, and
    #         whose classes say what inherits from what.
    def initialize(old, new, before:, after:)
      @old = old
      @new = new
      @before = before
      @after = after
    end

    # Whether every call +old+ accepts, +new+ accepts, returning what
    # +old+ promised or less.
    def kept?
      return true if @old.to_s == @new.to_s
      return false unless @old.type_params.map(&:to_s) == @new.type_params.map(&:to_s)
      return false unless function?(@old.type) && function?(@new.type)

      positionals_kept? && keywords_kept? && block_kept? && narrower?(@new.type.return_type, @old.type.return_type)
    end

    private def function?(type)
      type.is_a?(RBS::Types::Function) && type.trailing_positionals.empty?
    end

    private def positionals_kept?
      old = @old.type
      new = @new.type
      return false if new.required_positionals.size > old.required_positionals.size

      slots = old.required_positionals.size + old.optional_positionals.size
      reach = old.rest_positionals ? [slots, new.required_positionals.size + new.optional_positionals.size].max + 1 : slots
      (0...reach).all? do |index|
        wanted = slot(old, index)
        given = slot(new, index)
        given && wider?(given.type, wanted.type)
      end
    end

    private def slot(function, index)
      list = function.required_positionals + function.optional_positionals
      index < list.size ? list[index] : function.rest_positionals
    end

    private def keywords_kept?
      old = @old.type
      new = @new.type
      return false unless (new.required_keywords.keys - old.required_keywords.keys).empty?
      return false if old.rest_keywords && !(new.rest_keywords && wider?(new.rest_keywords.type, old.rest_keywords.type))

      old.required_keywords.merge(old.optional_keywords).all? do |name, param|
        given = new.required_keywords[name] || new.optional_keywords[name] || new.rest_keywords
        given && wider?(given.type, param.type)
      end
    end

    private def block_kept?
      old = @old.block
      new = @new.block
      return new.nil? || !new.required if old.nil?
      return false if new.nil? || (new.required && !old.required)

      shape(old.type) == shape(new.type)
    end

    # A function's parameter types and return type, without the names of
    # its parameters.
    private def shape(function)
      return function.to_s unless function.is_a?(RBS::Types::Function)

      params = function.required_positionals.map { |param| param.type.to_s } +
        function.optional_positionals.map { |param| "?#{param.type}" } +
        [function.rest_positionals && "*#{function.rest_positionals.type}"].compact +
        function.trailing_positionals.map { |param| param.type.to_s } +
        function.required_keywords.map { |name, param| "#{name}: #{param.type}" } +
        function.optional_keywords.map { |name, param| "?#{name}: #{param.type}" } +
        [function.rest_keywords && "**#{function.rest_keywords.type}"].compact
      "(#{params.join(', ')}) -> #{function.return_type}"
    end

    # Whether +given+, the next release's parameter type, accepts every
    # value +wanted+, the last release's, did.
    private def wider?(given, wanted)
      wide = @after.members(given)
      @before.members(wanted).all? { |member| covered?(wide, member) }
    end

    # Whether +given+, the next release's return type, is one the last
    # release's, +promised+, covers.
    private def narrower?(given, promised)
      return true if promised.is_a?(RBS::Types::Bases::Void)

      wide = @before.members(promised)
      @after.members(given).all? { |member| covered?(wide, member) }
    end

    private def covered?(wide, member)
      wide.any? { |candidate| covers?(candidate, member) }
    end

    private def covers?(wide, narrow)
      return true if wide.to_s == narrow.to_s || UNIVERSAL.include?(wide.to_s)
      return true if wide.is_a?(RBS::Types::Bases::Bool) && narrow.is_a?(RBS::Types::Literal) && [true, false].include?(narrow.literal)
      return tuple_covers?(wide, narrow) if wide.is_a?(RBS::Types::Tuple) && narrow.is_a?(RBS::Types::Tuple)
      return false unless wide.is_a?(RBS::Types::ClassInstance) && narrow.is_a?(RBS::Types::ClassInstance)
      return arguments_cover?(wide.args, narrow.args) if wide.name == narrow.name

      wide.args.empty? && @after.ancestors(narrow.name).include?(wide.name)
    end

    private def tuple_covers?(wide, narrow)
      arguments_cover?(wide.types, narrow.types)
    end

    private def arguments_cover?(wide, narrow)
      return true if wide.empty?
      return false unless wide.size == narrow.size

      wide.zip(narrow).all? do |given, wanted|
        members = @after.members(given)
        @after.members(wanted).all? { |member| members.any? { |candidate| covers?(candidate, member) } }
      end
    end
  end
end
