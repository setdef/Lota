# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Bindings
  # The translation rules (doc/contributors/design/translation.md), applied to one LÖVE function.
  #
  # The rules turn every LÖVE name into a Ruby one without a decision per
  # function (doc/contributors/design/translation.md): newSpriteBatch becomes
  # SpriteBatch.new, setTitle becomes title=, isDown becomes down?. Some rules
  # read only the name; others need the function's shape, which an Analysis
  # gives: what it returns, whether it takes an option table or a function.
  # Rules reports the Ruby name, the rules that gave it, and every way the
  # function fits no rule or more than one, which goes to the maintainer
  # as a question, never answered here.
  class Rules
    # A function's Ruby translation.
    #
    # [scope] Where the method lives: "Lota::Graphics" for a module
    #   function, "Lota::Graphics::Texture" for a method.
    # [singleton] Whether it is a module function (Lota::Graphics.x)
    #   rather than an instance method (texture.x).
    # [name] The Ruby method name, or nil when no rule gives one.
    # [rules] The rule numbers that shaped it, in order.
    # [collisions] Collision objects: why it fits no rule or several.
    class Translation < Data.define(:scope, :singleton, :name, :rules, :collisions)
      # The method as Ruby writes it: Lota::Graphics.width,
      # Lota::Graphics::Texture#width, or Lota::Graphics::Canvas.new.
      def ruby_name
        return "#{scope}::#{name}" if name&.end_with?(".new")

        "#{scope}#{singleton ? '.' : '#'}#{name}"
      end
    end

    # Why a function fits no rule, or fits more than one.
    #
    # [kind] :no_rule, :several_rules, or :open (one rule fits but leaves
    #   a decision to make).
    # [rules] The rule numbers involved.
    # [why] A sentence for the maintainer.
    class Collision < Data.define(:kind, :rules, :why)
    end

    # The rule table's decisions that live in the prose of
    # doc/contributors/design/translation.md rather than in its table, each
    # cited, so that every decision the rules depend on is written down
    # once.
    #
    # Rule 11's explicit pairs, as its examples name them:
    # love.graphics.push and pop, File:open and close.
    PAIRS = { "love.graphics.push" => "love.graphics.pop", "File:open" => "File:close" }.freeze
    # Pairs rule 11 decides against: mount and unmount, which "get no
    # block form until a game needs one", and a Source's play and stop,
    # since "a sound plays across frames while the game runs"
    # (doc/contributors/design/translation.md, under the table), whether the
    # Source's own methods or love.audio's, which play and stop the Sources they
    # are given; a ParticleSystem's start and stop, which run across frames
    # likewise; and a Mesh's attachAttribute and detachAttribute, which follow
    # mount and unmount: an attribute stays attached as long as the mesh lives,
    # so the pair gets no block form until a game needs one.
    NOT_PAIRS = {
      "love.filesystem.mount" => "love.filesystem.unmount",
      "Source:play" => "Source:stop",
      "love.audio.play" => "love.audio.stop",
      "Mesh:attachAttribute" => "Mesh:detachAttribute",
      "ParticleSystem:start" => "ParticleSystem:stop",
    }.freeze
    # Verbs that often open and close a pair, to find pairs rule 11 has
    # not decided.
    ANTONYMS = {
      "push" => "pop",
      "open" => "close",
      "mount" => "unmount",
      "lock" => "unlock",
      "begin" => "end",
      "start" => "stop",
      "attach" => "detach",
      "acquire" => "release",
      "enable" => "disable",
      "map" => "unmap",
      "grab" => "ungrab",
      "play" => "stop",
    }.freeze
    # Rule 2's module factories whose === is decided, with what it asks:
    # Canvas === texture asks texture.canvas?, and Image === is true of
    # every Texture (rule 2's text), as RectangleShape === is of every
    # PolygonShape, which newRectangleShape makes (wrap_Physics.cpp,
    # w_newRectangleShape), as the maintainer decided, and by the same
    # precedent ImageFont === is true of every Font and Text === of every
    # TextBatch, whose products the engine cannot tell apart. CompressedData
    # === is true of every CompressedImageData, which only
    # newCompressedData makes (wrap_Image.cpp, w_newCompressedData), so
    # rule 26's "what that factory makes" is the whole class. A texture
    # factory of one type makes the Textures whose getTextureType names
    # it, a getter answering what a predicate answers for newCanvas, so
    # CubeTexture === asks the type, as do the modules of LÖVE 11's names
    # for the same factories; a view is a Texture LÖVE cannot tell from
    # any other, so TextureView === is true of every Texture, as Image ===
    # is. The deprecated newFixture's Fixture === is true of every Shape,
    # the one it makes being a Shape (wrap_Physics.cpp, w_newFixture), as
    # the maintainer decided.
    MODULE_FACTORY_MATCHES = {
      "newCanvas" => "Texture:isCanvas",
      "newImage" => "Texture",
      "newRectangleShape" => "PolygonShape",
      "newImageFont" => "Font",
      "newText" => "TextBatch",
      "newComputeShader" => "Shader:hasStage",
      "newCompressedData" => "CompressedImageData",
      "newFixture" => "Shape",
      "newCubeTexture" => "Texture:getTextureType",
      "newArrayTexture" => "Texture:getTextureType",
      "newVolumeTexture" => "Texture:getTextureType",
      "newCubeImage" => "Texture:getTextureType",
      "newArrayImage" => "Texture:getTextureType",
      "newVolumeImage" => "Texture:getTextureType",
      "newTextureView" => "Texture",
    }.freeze
    # The pushes of an engine object: luax_pushtype, and luax_pushshape and
    # luax_pushjoint, which push a Shape or a Joint as the class its type
    # names (wrap_Shape.cpp:36-63, wrap_Joint.cpp:44-76), as the
    # generator's port reads them (Port::OBJECT_PUSHERS).
    OBJECT_PUSHERS = %w[luax_pushtype luax_pushshape luax_pushjoint].freeze
    # The Ruby class a LÖVE type's methods belong to, where LÖVE's Lua type
    # name differs from the name its wrap file registers: Buffer.cpp's type
    # is "GraphicsBuffer" (rule 2 then makes Buffer a module, as it makes
    # Image one for Texture), and LuaThread.cpp's is "Thread".
    RUBY_TYPE_NAMES = { "Buffer" => "GraphicsBuffer", "LuaThread" => "Thread" }.freeze
    # The setters whose first value is itself an Array or a Data, which
    # stay methods, since a writer cannot tell that value from a list of
    # several (rule 35).
    PLAIN_SETTERS = %w[Buffer:setArrayData Mesh:setVertices Mesh:setVertexMap].freeze
    # The methods rules 16, 33, and 42 give every LÖVE object, from
    # Object:type and Object:typeOf (src/common/runtime.cpp, w__type and
    # w__typeOf), which no wrap file lists: object_type, type as another
    # name for it, and type_of?, each with the rule that gives it.
    OBJECT_METHODS = %w[object_type type type_of?].freeze
    # The rule that gives each of OBJECT_METHODS.
    OBJECT_METHOD_RULES = { "object_type" => 42, "type" => 16, "type_of?" => 33 }.freeze
    # The functions rule 34 keeps prefixed on a class that also has
    # getType, where type would be ambiguous in LÖVE itself (rule 41).
    OWN_TYPE = %w[getType setType].freeze
    # Rule 36's spelling of the words LÖVE capitalizes inside: UInt is C's
    # uint (uint8_t), one word as Int is int, so getUInt8 becomes uint8.
    # The V of VSync stands for "vertical", so getVSync becomes get_vsync.
    ONE_WORD = { "UInt" => "Uint", "VSync" => "Vsync" }.freeze
    # Rule 38: Lua's metamethods, by the name Ruby gives the same method,
    # its operator where it has one (Lua 5.1 reference manual, section
    # 2.8). One with no Ruby counterpart, such as __concat, fits no rule.
    METAMETHODS = {
      "__add" => "+",
      "__sub" => "-",
      "__mul" => "*",
      "__div" => "/",
      "__mod" => "%",
      "__pow" => "**",
      "__unm" => "-@",
      "__eq" => "==",
      "__lt" => "<",
      "__le" => "<=",
      "__call" => "call",
      "__tostring" => "to_s",
    }.freeze
    # LÖVE's root types, which keep their names inside Lota
    # (doc/contributors/design/translation.md): Data's methods are Lota::Data's,
    # a module every Data includes, as Object's are Lota::Object's. Data is
    # love.data's type, so Lota::Data is also that module, whose module
    # functions are love.data's.
    ROOT_TYPES = { "Data" => "Lota::Data" }.freeze
    # Rule 7's setters, as doc/contributors/design/translation.md lists them under the table.
    RULE_7_SETTERS = %w[
      setMode
      setFullscreen
      setVibration
      setIcon
      setRelativeMode
      setEffect
      setFilter
      setOutputSpatialization
      setMixWithSystem
      setBuffer
      setGamepadMapping
      setPlaybackDevice
      setNewFont
].freeze

    # Ruby's keywords, which no method defined with def can be called by
    # without a receiver.
    KEYWORDS = %w[
      alias
      and
      begin
      break
      case
      class
      def
      defined?
      do
      else
      elsif
      end
      ensure
      false
      for
      if
      in
      module
      next
      nil
      not
      or
      redo
      rescue
      retry
      return
      self
      super
      then
      true
      undef
      unless
      until
      when
      while
      yield
].freeze

    # Rule 1: a LÖVE module's Ruby module.
    def self.module_constant(module_name)
      "Lota::#{module_name.capitalize}"
    end

    # Rule 13: a camelCase name in snake_case. An acronym is one word
    # (rule 36), and digits stay with the word they follow (rule 37), as in
    # Ruby's own use_ssl? and sha256: getDPIScale becomes dpi_scale, and
    # isAffine2DTransform affine2d_transform?. A word starts at a capital
    # after a lower-case letter, or at a capital followed by a lower-case
    # letter.
    def self.snake_case(name)
      one_word(name).gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end

    # +name+ with each of ONE_WORD's words spelled as one.
    def self.one_word(name)
      ONE_WORD.reduce(name) { |spelled, (word, one)| spelled.gsub(word, one) }
    end

    # [types] The class names LÖVE registers, with their modules.
    # [typed] The class names that have getType (rule 41).
    def initialize(types:, typed: [])
      @types = types
      @typed = typed
    end

    # The Translation of +function+ (a Catalog::LoveFunction or
    # LuaFunctions::Function), whose shape +analysis+ gives, or nil for a
    # function the analysis could not read or that is defined in Lua.
    def translate(function, analysis)
      Translator.new(function, analysis, @types, @typed).translation
    end

    # Applies the rules to one function.
    class Translator
      def initialize(function, analysis, types, typed)
        @function = function
        @analysis = analysis&.readable? ? analysis : nil
        @facts = analysis
        @types = types
        @typed = typed
        @name = function.lua_name
        @rules = [1]
        @collisions = []
      end

      def translation
        name = base_name
        shape_rules
        Translation.new(scope:, singleton: @function.type_name.nil?, name:, rules: @rules.uniq,
          collisions: @collisions)
      end

      private def scope
        return ROOT_TYPES.fetch(@function.type_name) if ROOT_TYPES.key?(@function.type_name)

        constant = Rules.module_constant(@function.module_name)
        @function.type_name ? "#{constant}::#{RUBY_TYPE_NAMES.fetch(@function.type_name, @function.type_name)}" : constant
      end

      private def base_name
        return metamethod if @name.start_with?("__")
        return internal if @name.start_with?("_")
        return own_type if OWN_TYPE.include?(@name) && @typed.include?(@function.type_name)
        return several_objects if @name.match?(/\Anew[A-Z]/) && several_objects?
        return factory(Regexp.last_match(1)) if @function.type_name.nil? && @name =~ /\Anew([A-Z]\w*)\z/
        return getter(Regexp.last_match(1)) if @name =~ /\Aget([A-Z]\w*)\z/
        return setter(Regexp.last_match(1)) if @name =~ /\Aset([A-Z]\w*)\z/
        return predicate(Regexp.last_match(2)) if @name =~ /\A(is|has|are)([A-Z]\w*)\z/

        @rules << 13
        snake(@name)
      end

      # Rule 22: a name that starts with one underscore is LÖVE's internal
      # and gets no Lota name, which the rule settles, so it is no
      # collision.
      private def internal
        @rules << 22
        nil
      end

      # Rule 38: a metamethod by the name Ruby gives the same method.
      private def metamethod
        name = METAMETHODS[@name] or return no_rule("is a Lua metamethod with no Ruby counterpart")

        @rules << 38
        name
      end

      # Rule 13's snake case, with rule 36 for a name that holds an
      # acronym or a word cut to one letter, and rule 37 for one that
      # holds digits.
      private def snake(name)
        @rules << 36 if name.match?(/[A-Z]{2}/) || ONE_WORD.keys.any? { |word| name.include?(word) }
        @rules << 37 if name.match?(/\d/)
        Rules.snake_case(name)
      end

      # Rule 34: getType and setType on a class that has getType keep
      # their prefixes, as methods, since type there would mean either
      # Object:type or getType (rule 41).
      private def own_type
        @rules << 34
        snake(@name)
      end

      # Rule 17 of doc/contributors/design/translation.md: factories that make
      # several objects stay methods. Rule 2 makes a factory a constructor, but
      # Ruby's new makes one object, so a factory that returns more than one, as
      # newCircleBody returns its Body and its CircleShape
      # (wrap_Physics.cpp:85-107) and newCubeFaces its six faces
      # (wrap_Image.cpp:131-139), or an object or nil and a message, as newFile
      # (wrap_Filesystem.cpp:278-306), keeps its name, in snake case, and returns
      # what it makes as an Array by rule 4, with no module and no ===.
      private def several_objects
        @rules.push(17, 4)
        snake(@name)
      end

      # Whether the function returns more than one engine object, as its
      # pushes and its counts of values say, which an analysis gives even
      # for a function it cannot read whole: two objects or more and a
      # literal count of more than one value, or an object pushed in a
      # loop and a count computed at run time, one value for each object.
      # A function that returns its object, or nil and a message, as
      # newFile does through luax_ioError and newFileData through
      # luax_getfiledata asked for an I/O error, makes several too: in Ruby
      # nil and a message are objects.
      private def several_objects?
        return false unless @facts

        objects = @facts.pushes.select { |push| OBJECT_PUSHERS.include?(push.pusher) }
        (@facts.result_count > 1 && objects.size > 1) || (@facts.computed_count && objects.any?(&:looped)) ||
          (@facts.io_error && objects.any?)
      end

      # Rule 2, for a module's functions: a method named new... reads the
      # object it is called on, and a Ruby constructor belongs to the class
      # it makes, so Texture:newImageData is rule 13's new_image_data.
      private def factory(class_name)
        @rules << 2
        made = made_type
        if @types.key?(class_name)
          if made && made != class_name && !@types.key?(made)
            several([2], "#{class_name} is a LÖVE class, but #{@name} pushes a #{made}")
          elsif made && made != class_name
            several([2], "rule 2 makes it #{class_name}.new, but it returns a #{made}, another LÖVE class")
          end
        elsif !MODULE_FACTORY_MATCHES.key?(@name)
          note = made ? "it returns a #{made}" : "the analysis cannot tell what it returns"
          note = "it returns #{results} values, the first a #{made}" if made && results > 1
          open_question([2], "LÖVE has no #{class_name} class, so rule 2 makes #{class_name} a module, " \
            "and no rule says what #{class_name} === asks (#{note})")
        end
        "#{class_name}.new"
      end

      # Rules 3 and 4.
      private def getter(rest)
        @rules << 3
        @rules << 4 if results > 1
        snake(rest)
      end

      # Rules 5, 6, and 7.
      private def setter(rest)
        spelled = snake(rest)
        if PLAIN_SETTERS.include?(@function.love_name)
          @rules << 35
          return "set_#{spelled}"
        end
        if returns_value?
          @rules << 7
          several([5, 7], "returns a value from some forms and nothing from others") if @analysis&.counts&.include?(0)
          "set_#{spelled}"
        else
          @rules << ((arguments > 1) ? 6 : 5)
          writer_collisions
          "#{spelled}="
        end
      end

      # Rule 8.
      private def predicate(rest)
        @rules << 8
        if @analysis && results > 1
          several([4, 8], "a predicate that returns #{results} values")
        elsif @analysis && non_boolean_result
          several([8], "a predicate whose result is not true or false (#{non_boolean_result})")
        end
        "#{snake(rest)}?"
      end

      # Rules 9, 10, 12, and 14 read what a function reads, which an
      # analysis gives even for a function it cannot read whole; the
      # results rules 4 and 7 need come only from a readable one.
      private def shape_rules
        return unless @facts

        @rules << 9 if @facts.enums.any? || @facts.enum_results.any?
        option_tables
        functions
        @rules << 14 if @facts.reads.any? { |read| %i[number integer].include?(read.kind) } ||
          @facts.pushes.any? { |push| %i[number integer].include?(push.kind) }

        several_results if @analysis
      end

      private def option_tables
        keyed = @facts.tables.select(&:key).map(&:index).grep(Integer).uniq
        return if keyed.empty?

        @rules << 10
        return unless @analysis

        last = @analysis.indices.grep(Integer).max
        keyed.each do |index|
          next if index == last

          several([10], "takes an option table at argument #{argument_label(index)} but reads arguments after it, " \
            "and Ruby's keyword arguments come last")
        end
      end

      private def functions
        count = (@facts.reads.select { |read| read.kind == :function }.map(&:index) +
          @facts.tests.select { |test| test.predicate == "lua_isfunction" }.map(&:index)).uniq.size
        return if count.zero?

        @rules << 12
        several([12], "takes #{count} functions, and a Ruby method takes one block") if count > 1
      end

      # Rule 4 covers every function that returns several values, as its
      # own example, love.filesystem.write, shows; a predicate that does
      # is a collision of its own (predicate).
      private def several_results
        return if results <= 1 || @rules.include?(8)

        @rules << 4
      end

      private def writer_collisions
        return unless @facts

        if @facts.tables.any?(&:key)
          several([5, 10], "a writer takes one value, so it cannot take keyword arguments for its option table")
        end
        return unless @facts.reads.any? { |read| read.kind == :function }

        several([5, 12], "a writer cannot take a block")
      end

      private def made_type
        return nil unless @analysis

        @analysis.pushes.select { |push| push.kind == :object }.map do |push|
          @analysis.type_of(push.expression.split(",").first.to_s.strip)
        end.compact.first
      end

      # A setter that returns what a factory's wrap function returns
      # (w_setNewFont returns w_newFont's count) returns the object it
      # made.
      private def returns_value?
        return true if @facts&.delegate&.match?(/\Aw_new[A-Z]/)
        return @function.lua_name.then { |name| RULE_7_SETTERS.include?(name) } unless @analysis

        @analysis.pushes.any? { |push| !(push.kind == :argument && push.expression.strip == "1") } &&
          @analysis.result_count.positive?
      end

      private def results
        @analysis ? @analysis.result_count : 0
      end

      private def arguments
        return 1 unless @analysis

        indices = @analysis.indices
        own = @function.type_name ? indices - [1] : indices
        (own.include?(:varargs) || @analysis.tables.any? { |table| table.access == "lua_rawgeti" }) ? 2 : own.size
      end

      private def non_boolean_result
        kinds = @analysis.pushes.map(&:kind).uniq - [:boolean]
        kinds.empty? ? nil : kinds.join(", ")
      end

      private def argument_label(index)
        @function.type_name ? index - 1 : index
      end

      private def no_rule(why)
        @collisions << Collision.new(kind: :no_rule, rules: [], why:)
        nil
      end

      private def several(rules, why)
        @collisions << Collision.new(kind: :several_rules, rules:, why:)
      end

      private def open_question(rules, why)
        @collisions << Collision.new(kind: :open, rules:, why:)
      end
    end
  end
end
