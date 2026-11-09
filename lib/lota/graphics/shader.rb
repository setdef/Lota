# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # A program the graphics card runs for every vertex and every pixel it
    # draws, matching LÖVE's Shader class (src/modules/graphics/Shader.h).
    #
    # Glows, blurs, dissolves, and soft lighting are shaders. A shader is
    # written in LÖVE's dialect of GLSL: a pixel shader's +effect+ function
    # returns each pixel's color, and a vertex shader's +position+ function
    # places each vertex. Lota::Graphics.shader= draws with one until you
    # set another, or +nil+ for LÖVE's own.
    #
    # Values the shader reads, its uniforms, come from the game through
    # send and send_color.
    #
    # === Example
    #
    #   glow = Lota::Graphics::Shader.new(<<~GLSL)
    #     uniform float strength;
    #     vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
    #       return Texel(tex, tc) * color * strength;
    #     }
    #   GLSL
    #   glow.send("strength", 1.5)
    #   Lota::Graphics.shader = glow
    #   Lota::Graphics.draw(card, 100, 100)
    #   Lota::Graphics.shader = nil
    class Shader < Object
      # One member of a buffer a shader declares, which #buffer_format
      # returns, translated from the table love.graphics's
      # Shader:getBufferFormat makes (src/modules/graphics/wrap_Shader.cpp,
      # w_Shader_getBufferFormat): a frozen value with LÖVE's field names
      # (rule 28 of doc/contributors/design/translation.md).
      #
      # [name] The member's String name.
      # [format] Symbol of its data format, such as +:floatvec2+.
      # [arraylength] Integer length of the array the member is, or 0.
      #
      # === Example
      #
      #   shader.buffer_format("Particles").first.name # => "position"
      class BufferFormat < ::Data.define(:name, :format, :arraylength)
        include Record
      end

      # Wraps a Shader the engine made. The same engine shader always comes
      # back as the same Ruby object, so the one Lota::Graphics.shader
      # returns is the one that was set. :nodoc:
      private_class_method def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        shader = allocate
        shader.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, shader)
        shader
      end

      # Compiles a shader, matching love.graphics.newShader
      # (src/modules/graphics/wrap_Graphics.cpp, w_newShader).
      #
      # [first] The source of a pixel shader, a vertex shader, or both in
      #   one, as GLSL in a String; the name of a file in the game's
      #   folder that holds it; or a Lota::Filesystem::FileData of it.
      # [second] Another such source, the other stage, or +nil+.
      # [defines] A Hash of names to define before the source, each with a
      #   String, number, or boolean value (true is 1, false 0), or an
      #   Array of names to define with no value.
      # [debugname] A String name for the shader, which debug_name returns
      #   and graphics debuggers show.
      # [write] Whether the vertex and pixel stages may write to storage
      #   buffers and storage textures.
      #
      # LÖVE tells the stages apart by the functions each defines. A String
      # that names no file but looks like a file name, short and with an
      # extension, is taken for a misspelled one. Uses of names LÖVE 12
      # deprecated in the source, such as texture2D, print a notice, as in
      # LÖVE.
      #
      # Raises RuntimeError with LÖVE's message when the source does not
      # compile, a file cannot be read, or no window is open;
      # ArgumentError for a malformed +defines+; TypeError for a source
      # that is not a String or a FileData; and ThreadError off the main
      # thread.
      #
      # === Examples
      #
      #   Lota::Graphics::Shader.new("shaders/dissolve.glsl")
      #   Lota::Graphics::Shader.new(pixelcode, vertexcode, debugname: "card glow")
      #   Lota::Graphics::Shader.new(pixelcode, defines: { "SAMPLES" => 9 })
      #
      # :call-seq:
      #   new(first, second = nil, defines: nil, debugname: nil, write: nil)
      def self.new(first, second = nil, defines: nil, debugname: nil, write: nil)
        stages, pairs, name = source(first, second, defines, debugname)
        native = begin
          Native::Graphics.new_shader(stages, name, pairs, write ? true : false)
        rescue RuntimeError => e
          raise e.exception(transform_glsl_error_messages(e.message))
        end
        mark_deprecated_uses(native, caller_locations(1, 1)&.first)
        from_native(native)
      end

      # Compiles a compute shader for ComputeShader.new, matching
      # love.graphics.newComputeShader
      # (src/modules/graphics/wrap_Graphics.cpp, w_newComputeShader), as new
      # does a shader; +location+ is where a notice says it was made. :nodoc:
      private_class_method def self.compute(first, location, defines: nil, debugname: nil, write: nil)
        stages, pairs, name = source(first, nil, defines, debugname)
        native = begin
          Native::Graphics.new_compute_shader(stages, name, pairs, write ? true : false)
        rescue RuntimeError => e
          raise e.exception(transform_glsl_error_messages(e.message))
        end
        mark_deprecated_uses(native, location)
        from_native(native)
      end

      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # w_getShaderSource (src/modules/graphics/wrap_Graphics.cpp:
      # 1481-1607), for Shader.new and Lota::Graphics.validate_shader: the
      # sources of +first+ and +second+, each read from its file or its
      # FileData, +defines+ as pairs of Strings, and +debugname+, empty
      # when nil. :nodoc:
      private_class_method def self.source(first, second, defines, debugname)
        Native::Graphics.check_created
        stages = [first, second].filter_map { |argument| source_of(argument) }
        raise TypeError, "wrong argument type nil (expected String)" if stages.empty?

        [stages, defines_of(defines), debugname_of(debugname)]
      end

      # One source argument (lines 1490-1530): its file's contents, when it
      # names a file; nil when it is nil.
      private_class_method def self.source_of(argument)
        case argument
        when nil then nil
        when Filesystem::FileData then argument.string
        when String then file_source(argument)
        else raise TypeError, "wrong argument type #{argument.class} (expected String or Lota::Filesystem::FileData)"
        end
      end

      # A String source: the contents of the file it names, or the String
      # itself, as LÖVE reads it (lines 1503-1529).
      private_class_method def self.file_source(code)
        if Filesystem.info(code)
          contents, message = Filesystem.read(code)
          raise message.to_s unless contents

          return contents
        end
        raise "Could not open file #{code}. Does not exist." if file_name?(code)

        code
      end

      # Whether a String that names no file looks like a file's name, for
      # LÖVE's nicer error (lines 1520-1528): short, on one line, with an
      # extension that has no semicolon or space.
      private_class_method def self.file_name?(code)
        return false unless code.bytesize.between?(1, 63) && !code.include?("\n")

        _name, dot, rest = code.partition(".")
        !dot.empty? && !rest.match?(/[; ]/)
      end

      # The defines field (lines 1547-1582): an Array's names define
      # nothing, and a Hash's String or Symbol names a value, which LÖVE
      # turns into a String as Lua does.
      private_class_method def self.defines_of(defines)
        case defines
        when nil then []
        when Array then defines.map { |name| [define_name(name), ""] }
        when Hash then defines.map { |name, value| [define_name(name), define_value(value)] }
        else raise ArgumentError, "expected 'defines' field to be a table"
        end
      end

      # A define's name, which must be a String, or a Symbol as a Ruby
      # Hash's key writes one.
      private_class_method def self.define_name(name)
        case name
        when String then name
        when Symbol then name.name
        else raise ArgumentError, "all fields in the 'defines' table must use string keys."
        end
      end

      # A define's value as the String LÖVE passes the compiler.
      private_class_method def self.define_value(value)
        case value
        when true then "1"
        when false then "0"
        when String then value
        when Integer then value.to_s
        when Float then lua_number_string(value)
        else raise ArgumentError, "'defines' table values must be strings, numbers, or booleans."
        end
      end

      # A Float as Lua's tostring writes it (LUAI_NUMFFORMAT, "%.14g"), so
      # that 1.0 defines 1, as in LÖVE.
      private_class_method def self.lua_number_string(value)
        return "inf" if value == Float::INFINITY
        return "-inf" if value == -Float::INFINITY
        return "nan" if value.nan?

        format("%.14g", value)
      end

      # The debugname option, luax_checkstring'd, or empty when nil.
      private_class_method def self.debugname_of(debugname)
        case debugname
        when nil then ""
        when String then debugname
        else raise TypeError, "wrong argument type #{debugname.class} for debugname (expected String)"
        end
      end

      # The deprecated uses w_newShader marks (wrap_Graphics.cpp:
      # 1618-1626), where the game called Shader.new, as luaL_where gives
      # it for level 1.
      private_class_method def self.mark_deprecated_uses(native, location)
        where = location ? "#{location.path}:#{location.lineno}: " : ""
        if native.deprecated_texture_functions?
          Deprecation.mark("texture2D() or texture3D() or textureCube() function calls in shader code", :custom,
            :replaced, "texture() function calls", where:)
        end
        if native.deprecated_texture_uniform?
          Deprecation.mark("'texture' uniform variable name in shader code", :custom, :noreplacement, "", where:)
        end
        unset = native.unset_vertex_input_locations
        return if unset.empty?

        Deprecation.mark("vertex input attribute(s) #{unset} without a 'location' layout qualifier in shader code",
          :custom, :replaced, "layout(location = #) qualifier for vertex inputs", where:)
      end

      # The message of a shader that does not compile, its lines from each
      # driver's format rewritten as "Line n: what: message", ported from
      # _transformGLSLErrorMessages (src/modules/graphics/
      # wrap_Graphics.lua:99-132), which w_newShader calls on the message
      # before raising it. A Lua pattern's %a is an ASCII letter, %w an
      # ASCII letter or digit, and %d, %s, and . as in Ruby's own.
      private_class_method def self.transform_glsl_error_messages(message)
        shadertype = message[/Cannot compile ([A-Za-z]+) shader code/, 1]
        compiling = !shadertype.nil?
        shadertype ||= message[/Error validating ([A-Za-z]+) shader/, 1]
        return message unless shadertype

        lines = ["#{compiling ? 'Cannot compile ' : 'Error validating '}#{shadertype} shader code:"]
        message.scan(/[^\n]+/) do |line|
          error_line = glsl_error_line(line.to_s)
          lines << error_line if error_line
        end
        # did not match any known error messages
        return message if lines.size == 1

        lines.join("\n")
      end

      # One line of a driver's message, rewritten, or nil when it is none
      # LÖVE recognizes.
      private_class_method def self.glsl_error_line(line)
        # nvidia: 0(<linenumber>) : error/warning [NUMBER]: <error message>
        linenumber, what, text = line.match(/\A0\((\d+)\)\s*:\s*([A-Za-z0-9]+)[^:]+:\s*(.+)\z/)&.captures
        # AMD: ERROR 0:<linenumber>: error/warning(#[NUMBER]) [ERRORNAME]: <errormessage>
        linenumber, what, text = line.match(/\A[A-Za-z0-9]+: 0:(\d+):\s*([A-Za-z0-9]+)\([^)]+\)\s*(.+)\z/)&.captures unless linenumber
        # macOS (?): ERROR: 0:<linenumber>: <errormessage>
        what, linenumber, text = line.match(/\A([A-Za-z0-9]+): \d+:(\d+): (.+)\z/)&.captures unless linenumber
        what = line if !linenumber && line.start_with?("ERROR:")
        return "Line #{linenumber.to_i}: #{what}: #{text}" if linenumber && what && text

        what
      end

      # SPDX-SnippetEnd

      # The warnings the compiler gave, matching Shader:getWarnings
      # (src/modules/graphics/wrap_Shader.cpp, w_Shader_getWarnings): a
      # String, empty when there were none.
      #
      # Raises ThreadError off the main thread.
      #
      # === Example
      #
      #   shader.warnings # => ""
      def warnings
        native.warnings
      end

      # Sends values to the uniform +name+, matching Shader:send
      # (src/modules/graphics/wrap_Shader.cpp, w_Shader_send).
      #
      # [name] The uniform's name in the shader, as a String, such as
      #   <tt>"strength"</tt>, <tt>"lights[2]"</tt>, or
      #   <tt>"light.color"</tt>.
      # [values] One value for each element of an array uniform, from its
      #   first on: a number for a float, int, or uint; true or false for
      #   a bool; an Array of numbers or booleans for a vector; an Array
      #   for a matrix, flat or of rows, or a Lota::Math::Transform for a
      #   mat4, after an optional +:row+ or +:column+ layout (row by
      #   default); a Lota::Graphics::Texture for a sampler; or a
      #   Lota::Graphics::GraphicsBuffer for a texel or storage buffer.
      #
      # A Lota::Data sends its bytes instead, as LÖVE packs the uniform:
      # <tt>send(name, data, offset = 0, size = nil)</tt>, with a matrix's
      # layout before +data+ or, LÖVE's older order, after it.
      #
      # Ruby's own Object#send is still +__send__+ and +public_send+.
      #
      # Raises RuntimeError with LÖVE's message for a uniform the shader
      # does not have or does not use; TypeError for a value of the wrong
      # kind; ArgumentError for an unknown layout; and ThreadError off the
      # main thread.
      #
      # === Examples
      #
      #   shader.send("strength", 1.5)
      #   shader.send("offsets", [0, 1], [1, 0], [0, -1])
      #   shader.send("rotation", :column, [[1, 0], [0, 1]])
      #   shader.send("noise", noise_texture)
      def send(name, *values)
        native.send_values(name, values.map { |value| native_value(value) })
        nil
      end

      # Sends colors to the vec3 or vec4 uniform +name+, matching
      # Shader:sendColor (src/modules/graphics/wrap_Shader.cpp,
      # w_Shader_sendColors).
      #
      # [name] The uniform's name, as a String.
      # [colors] One Array of red, green, blue, and alpha, each from 0 to
      #   1, for each element of the uniform; or a Lota::Data of them, as
      #   send takes one.
      #
      # Each component is clamped from 0 to 1, and red, green, and blue
      # become linear while gamma correction is on, as
      # Lota::Graphics.color= treats a color. Returns true, as LÖVE does.
      #
      # Raises RuntimeError for a uniform that is not a vec3 or a vec4, and
      # as send raises.
      #
      # === Example
      #
      #   shader.send_color("tint", [1, 0.5, 0, 1])
      def send_color(name, *colors)
        native.send_color(name, colors.map { |value| native_value(value) })
      end

      # The format of one element of a buffer the shader declares, as an
      # Array of BufferFormat, matching Shader:getBufferFormat
      # (src/modules/graphics/wrap_Shader.cpp, w_Shader_getBufferFormat).
      #
      # [name] The buffer's String name in the shader.
      #
      # Raises RuntimeError with LÖVE's message for a buffer the shader
      # does not declare, and ThreadError off the main thread.
      #
      # === Example
      #
      #   shader.buffer_format("Particles").map(&:name) # => ["position", "velocity"]
      def buffer_format(name)
        native.buffer_format(name).map do |member, format, arraylength|
          BufferFormat.new(name: member, format: format.to_sym, arraylength:)
        end
      end

      # Whether the shader has the uniform +name+ and uses it, matching
      # Shader:hasUniform (src/modules/graphics/wrap_Shader.cpp,
      # w_Shader_hasUniform).
      #
      # [name] The uniform's name, as a String.
      #
      # Raises ThreadError off the main thread.
      #
      # === Example
      #
      #   shader.uniform?("strength") # => true
      def uniform?(name)
        native.uniform?(name)
      end

      # Whether the shader has the stage +stage+, matching Shader:hasStage
      # (src/modules/graphics/wrap_Shader.cpp, w_Shader_hasStage).
      #
      # [stage] +:vertex+, +:pixel+, or +:compute+.
      #
      # Raises ArgumentError for an unknown stage, and ThreadError off the
      # main thread.
      #
      # === Example
      #
      #   shader.stage?(:pixel) # => true
      def stage?(stage)
        native.stage?(EnumName.of(stage))
      end

      # The size of a compute shader's local thread groups, matching
      # Shader:getLocalThreadgroupSize
      # (src/modules/graphics/wrap_Shader.cpp,
      # w_Shader_getLocalThreadgroupSize).
      #
      # Returns an Array of the Integer x, y, and z sizes, or of +nil+ for a
      # shader with no compute stage, as LÖVE returns nil (rule 4 of
      # doc/contributors/design/translation.md). Raises ThreadError off the main
      # thread.
      #
      # === Example
      #
      #   x, y, z = shader.local_threadgroup_size # => [nil]
      def local_threadgroup_size
        native.local_threadgroup_size
      end

      # The name the shader was given with +debugname+, or +nil+, matching
      # Shader:getDebugName (src/modules/graphics/wrap_Shader.cpp,
      # w_Shader_getDebugName).
      #
      # Raises ThreadError off the main thread.
      #
      # === Example
      #
      #   Lota::Graphics::Shader.new(code, debugname: "glow").debug_name # => "glow"
      def debug_name
        native.debug_name
      end

      # What the engine reads of a value send passes: an engine object for
      # Lota's objects, and a layout's name as a String.
      private def native_value(value)
        case value
        when Symbol then value.name
        when Texture, GraphicsBuffer, Math::Transform, Lota::Data then value.native
        else value
        end
      end
    end
  end
end
