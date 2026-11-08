# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # A block of the graphics card's memory that holds an array of
    # elements, each of one format, matching LÖVE's GraphicsBuffer class
    # (src/modules/graphics/Buffer.h).
    #
    # A buffer holds vertices for a Lota::Graphics::Mesh, indices that say
    # which vertices to draw, or data a shader reads or writes, such as
    # the positions of a thousand particles that a compute shader moves
    # without the game touching them. Say what it is for with the keywords
    # of Buffer.new, then send it to a shader with Shader#send, or give it
    # to a mesh.
    #
    # LÖVE has no class named Buffer: its Lua type is +GraphicsBuffer+, which
    # #object_type returns, and +newBuffer+ makes one. So Buffer is a
    # module, as Image is (ADR 001, rule 2): Buffer.new returns a
    # GraphicsBuffer, and <tt>Buffer === object</tt> is true of every
    # GraphicsBuffer.
    #
    # === Example
    #
    #   format = [
    #     {name: "VertexPosition", format: :floatvec2, location: 0},
    #     {name: "VertexColor", format: :unorm8vec4, location: 1},
    #   ]
    #   points = Lota::Graphics::Buffer.new(format, [[0, 0, 1, 0, 0, 1], [8, 0, 0, 1, 0, 1]], vertex: true)
    #   points.element_count # => 2
    class GraphicsBuffer < Object
      # One member of the format of a buffer, which GraphicsBuffer#format returns,
      # translated from the table love.graphics's GraphicsBuffer:getFormat
      # makes (src/modules/graphics/wrap_Buffer.cpp, w_Buffer_getFormat):
      # a frozen value with LÖVE's field names (ADR 001, rule 10).
      #
      # [name] The member's String name, empty if it has none.
      # [format] Symbol of its data format, such as +:floatvec2+.
      # [arraylength] Integer length of the array the member is, or 0.
      # [location] Integer binding location, or -1 if it has none.
      # [offset] Integer bytes from the start of an element to the member.
      # [size] Integer bytes the member takes.
      #
      # === Example
      #
      #   buffer.format.first.name # => "VertexPosition"
      class Format < ::Data.define(:name, :format, :arraylength, :location, :offset, :size)
        include Record
      end

      # Wraps a Buffer the engine made. :nodoc:
      private_class_method def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        buffer = allocate
        buffer.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, buffer)
        buffer
      end

      # Makes a buffer, matching love.graphics.newBuffer
      # (src/modules/graphics/wrap_Graphics.cpp, w_newBuffer and
      # luax_newbuffer), named by ADR 001, rule 2.
      #
      # [format] The format of one element: a Symbol of a data format, such
      #   as +:uint16+ for indices, or an Array with a Hash for each
      #   member of an element, with +:format+ (a Symbol), and +:name+
      #   (a String), +:arraylength+ (an Integer), and +:location+ (an
      #   Integer binding location, which vertex buffers require), each
      #   of which GraphicsBuffer::Format answers too.
      # [content] What the buffer starts with: the Integer number of
      #   elements, which start zeroed; an Array with an Array of the
      #   numbers of each element, or with the numbers of every element
      #   one after another; or a Lota::Data of the elements' bytes.
      # [vertex] Whether the buffer is used as vertices, +false+ if left out.
      # [index] Whether it is used as indices.
      # [texel] Whether it is used as a texel buffer.
      # [shaderstorage] Whether it is used as a shader storage buffer.
      # [indirectarguments] Whether it holds the arguments of indirect
      #   drawing or compute dispatches.
      # [usage] How often it changes, which tells the graphics card where
      #   to keep it: +:dynamic+ (the default), +:static+, or +:stream+.
      # [debugname] A String name that graphics debuggers show, and
      #   #debug_name returns.
      #
      # LÖVE requires its settings table, so a buffer with no use can only
      # be made with <tt>{}</tt>; keywords left out are the same table. Uses
      # LÖVE 12 spells with a +name+ and no +location+ print its
      # deprecation notice.
      #
      # Raises TypeError for content or a format of the wrong type,
      # ArgumentError for an unknown data format, usage, or a format Hash
      # missing its +:format+, or its +:location+ when the buffer is
      # a vertex buffer, RuntimeError with LÖVE's message when the
      # graphics card cannot make the buffer or no window is open, and
      # ThreadError off the main thread.
      #
      # === Examples
      #
      #   Lota::Graphics::Buffer.new(:uint16, 128, index: true)
      #   Lota::Graphics::Buffer.new([{name: "mass", format: :float}], [1, 2, 3], shaderstorage: true)
      def self.new(format, content, vertex: false, index: false, texel: false, shaderstorage: false,
        indirectarguments: false, usage: nil, debugname: nil
      )
        create(caller_locations(1, 1)&.first, format, content, vertex:, index:, texel:, shaderstorage:,
          indirectarguments:, usage:, debugname:)
      end

      # Makes the buffer for +location+, where a notice says it was made.
      # :nodoc:
      private_class_method def self.create(location, format, content, vertex: false, index: false, texel: false, shaderstorage: false,
        indirectarguments: false, usage: nil, debugname: nil
      )
        uses = { vertex:, index:, texel:, shaderstorage:, indirectarguments: }
        names = uses.select { |_name, used| used }.keys.map(&:name)
        declarations = declarations(format, vertex ? true : false)
        native = Native::Graphics.new_buffer([
          declarations,
          native_content(content),
          names,
          usage && EnumName.of(usage),
          debugname&.to_s,
])
        mark_deprecated_bindings(native, location ? "#{location.path}:#{location.lineno}: " : "")
        from_native(native)
      end

      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # luax_checkbufferformat and luax_checkdatadeclaration
      # (src/modules/graphics/wrap_Graphics.cpp:1743-1822) for Buffer.new
      # and Mesh.new: the declarations of +format+ as Arrays of the name,
      # the data format's name, the array length, and the binding
      # location or +nil+. A name is required for none, as LÖVE calls them
      # for a buffer and a mesh, and a location when +location+ is true.
      # :nodoc:
      private_class_method def self.declarations(format, location)
        Native::Graphics.check_created
        case format
        when Symbol, String then [["", EnumName.of(format), 0, nil]]
        when Array then format.each_with_index.map { |entry, index| declaration(entry, index + 1, location) }
        else raise TypeError, "wrong argument type #{format.class} (expected Array)"
        end
      end

      # One member of the format table (lines 1743-1793), the +index+th,
      # counting from 1. :nodoc:
      private_class_method def self.declaration(entry, index, location)
        fields = case entry
        when Hash then entry
        when Format then entry.to_h
        else raise TypeError, "wrong argument type #{entry.class} (expected Hash)"
        end

        name = fields[:name]
        raise TypeError, "wrong argument type #{name.class} (expected String)" unless name.nil? || name.is_a?(String)

        format = fields[:format]
        unless format.is_a?(Symbol) || format.is_a?(String)
          raise ArgumentError, "'format' field expected in array element ##{index} of format table"
        end

        binding_location = fields[:location]
        if location && !binding_location.is_a?(Numeric)
          raise ArgumentError, "'location' field expected in array element ##{index} of format table"
        end

        raise TypeError, "wrong argument type #{binding_location.class} (expected Integer)" unless binding_location.nil? || binding_location.is_a?(Numeric)

        [
          name.to_s,
          EnumName.of(format),
          integer(fields[:arraylength]),
          binding_location.is_a?(Numeric) ? Integer(binding_location) : nil,
]
      end

      # luax_intflag: an Integer field, 0 when nil.
      private_class_method def self.integer(value)
        case value
        when nil then 0
        when Numeric then Integer(value)
        else raise TypeError, "wrong argument type #{value.class} (expected Integer)"
        end
      end

      # SPDX-SnippetEnd

      # What the engine reads of the content: a Lota::Data's engine object,
      # and anything else as it is. :nodoc:
      private_class_method def self.native_content(content)
        content.is_a?(Lota::Data) ? content.__send__(:native) : content
      end

      # luax_validatebuffervertexbindings (wrap_Graphics.cpp:1824-1843): the
      # notice for a vertex format that names its attributes but gives no
      # location. :nodoc:
      private_class_method def self.mark_deprecated_bindings(native, where)
        return unless native.legacy_vertex_bindings?

        Deprecation.mark("vertex format 'name' fields in Meshes and Buffers", :custom, :replaced,
          "'location' field containing a binding location number value.", where:)
      end

      # Replaces elements of the buffer, matching
      # GraphicsBuffer:setArrayData
      # (src/modules/graphics/wrap_Buffer.cpp, w_Buffer_setArrayData).
      # Its first argument is itself an Array or a Data, so it stays a
      # method rather than a writer (ADR 001, rule 6).
      #
      # [data] An Array of Arrays of numbers, an Array of the numbers of
      #   every element one after another, or a Lota::Data of bytes.
      # [source] Integer element of +data+ to start from, counting from 1;
      #   the first when left out.
      # [destination] Integer element of the buffer to start at, counting
      #   from 1; the first when left out.
      # [count] Integer number of elements to copy; as many as fit when
      #   left out.
      #
      # A number a format does not store, such as a color component in
      # <tt>:unorm8vec4</tt>, is clamped as LÖVE clamps it, and one left
      # out takes the default LÖVE gives, 0 and 1 for alpha. Raises
      # RuntimeError with LÖVE's message for indices outside the buffer or
      # data, TypeError for a value that is not a number, and ThreadError
      # off the main thread.
      #
      # === Examples
      #
      #   buffer.set_array_data([[0, 0, 1, 0, 0, 1], [8, 0, 0, 1, 0, 1]])
      #   buffer.set_array_data(bytes)
      #   buffer.set_array_data(flat, 1, 3, 2) # two elements, put from the third element of the buffer
      def set_array_data(data, source = nil, destination = nil, count = nil)
        @native.set_array_data([GraphicsBuffer.__send__(:native_content, data), source, destination, count])
        nil
      end

      # Sets part of the buffer to zero, matching GraphicsBuffer:clear
      # (src/modules/graphics/wrap_Buffer.cpp, w_Buffer_clear).
      #
      # [offset] Float or Integer bytes from the start of the buffer to
      #   start at; the whole buffer when left out.
      # [size] Float or Integer bytes to clear, which LÖVE requires with an
      #   offset.
      #
      # Raises RuntimeError with LÖVE's message for a negative offset or
      # size, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   buffer.clear
      #   buffer.clear(8, 8)
      def clear(offset = nil, size = nil)
        @native.clear([offset, size])
      end

      # The Integer number of elements the buffer holds, matching
      # GraphicsBuffer:getElementCount
      # (src/modules/graphics/wrap_Buffer.cpp, w_Buffer_getElementCount).
      #
      # === Example
      #
      #   buffer.element_count # => 4
      def element_count
        @native.element_count
      end

      # The Integer bytes from the start of one element to the start of
      # the next, matching GraphicsBuffer:getElementStride
      # (src/modules/graphics/wrap_Buffer.cpp, w_Buffer_getElementStride).
      #
      # === Example
      #
      #   buffer.element_stride # => 20
      def element_stride
        @native.element_stride
      end

      # The Integer bytes the whole buffer takes, matching
      # GraphicsBuffer:getSize (src/modules/graphics/wrap_Buffer.cpp,
      # w_Buffer_getSize).
      #
      # === Example
      #
      #   buffer.size # => 80
      def size
        @native.size
      end

      # The format of one element, as an Array of Format, one for each
      # member, matching GraphicsBuffer:getFormat
      # (src/modules/graphics/wrap_Buffer.cpp, w_Buffer_getFormat).
      #
      # === Example
      #
      #   buffer.format.map(&:name) # => ["VertexPosition", "VertexTexCoord", "VertexColor"]
      def format
        @native.format.map do |name, format, arraylength, location, offset, size|
          Format.new(name:, format: format.to_sym, arraylength:, location:, offset:, size:)
        end
      end

      # Whether the buffer was made for a use, matching
      # GraphicsBuffer:isBufferType
      # (src/modules/graphics/wrap_Buffer.cpp, w_Buffer_isBufferType).
      #
      # [type] +:vertex+, +:index+, +:texel+, +:shaderstorage+, or
      #   +:indirectarguments+.
      #
      # Raises ArgumentError for an unknown type, and ThreadError off the
      # main thread.
      #
      # === Example
      #
      #   buffer.buffer_type?(:vertex) # => true
      def buffer_type?(type)
        @native.buffer_type?(EnumName.of(type))
      end

      # The name the buffer was given with +debugname+, or +nil+, matching
      # GraphicsBuffer:getDebugName (src/modules/graphics/wrap_Buffer.cpp,
      # w_Buffer_getDebugName).
      #
      # === Example
      #
      #   buffer.debug_name # => "particles"
      def debug_name
        @native.debug_name
      end
    end

    # Makes buffers, matching love.graphics.newBuffer: LÖVE has no Buffer
    # class, so by ADR 001, rule 2, Buffer is a module whose new returns a
    # GraphicsBuffer and whose <tt>===</tt> is true of every GraphicsBuffer,
    # as Image is for Texture.
    #
    # === Example
    #
    #   Lota::Graphics::Buffer === Lota::Graphics::Buffer.new(:uint16, 4, index: true) # => true
    module Buffer
      # Makes a GraphicsBuffer; see GraphicsBuffer.new for its arguments.
      #
      # === Example
      #
      #   Lota::Graphics::Buffer.new(:uint16, 128, index: true)
      def self.new(format, content, **settings)
        GraphicsBuffer.__send__(:create, caller_locations(1, 1)&.first, format, content, **settings)
      end

      # Whether +object+ is a GraphicsBuffer, which is what newBuffer makes.
      #
      # === Example
      #
      #   Lota::Graphics::Buffer === :buffer # => false
      def self.===(object)
        case object
        when GraphicsBuffer then true
        else false
        end
      end
    end
  end
end
