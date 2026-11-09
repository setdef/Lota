# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # A shape of vertices that the graphics card draws as triangles,
    # lines, or points, matching LÖVE's Mesh class
    # (src/modules/graphics/Mesh.h).
    #
    # A Mesh is the way to draw something that is not a rectangle or a
    # circle: a 3D model, a landscape, a rope, a sprite bent by a
    # shader. Each vertex has a position and, usually, a texture
    # coordinate and a color, or attributes of any format you give it.
    # Draw it with Lota::Graphics.draw, or many times at once with
    # Lota::Graphics.draw_instanced.
    #
    # === Example
    #
    #   image = Lota::Graphics::Image.new("assets/logo.png")
    #   w, h = image.dimensions
    #   quad = Lota::Graphics::Mesh.new([[0, 0, 0, 0], [w, 0, 1, 0], [w, h, 1, 1], [0, h, 0, 1]], :fan)
    #   quad.texture = image
    #   Lota::Graphics.draw(quad, 100, 100)
    class Mesh < Object
      # One attribute of the format of a mesh's vertices, which
      # Mesh#vertex_format returns, translated from the table
      # love.graphics's Mesh:getVertexFormat makes
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_getVertexFormat): a
      # frozen value with LÖVE's field names (rule 28 of
      # doc/contributors/design/translation.md).
      #
      # [name] The attribute's String name, such as +"VertexPosition"+.
      # [location] Integer binding location, or -1 if it has none.
      # [format] Symbol of its data format, such as +:floatvec2+.
      # [arraylength] Integer length of the array the attribute is, or 0.
      # [offset] Integer bytes from the start of a vertex to the attribute.
      #
      # === Example
      #
      #   mesh.vertex_format.first.format # => :floatvec2
      class VertexFormat < ::Data.define(:name, :location, :format, :arraylength, :offset)
        include Record
      end

      # Wraps a Mesh the engine made. :nodoc:
      private_class_method def self.from_native(native)
        found = native.instance_variable_get(:@lota)
        return found if found

        mesh = allocate
        mesh.instance_variable_set(:@native, native)
        native.instance_variable_set(:@lota, mesh)
        mesh
      end

      # Makes a mesh, matching love.graphics.newMesh
      # (src/modules/graphics/wrap_Graphics.cpp, w_newMesh), named by
      # rule 2 of doc/contributors/design/translation.md. LÖVE chooses among
      # three forms by the types of the arguments, as this does:
      #
      # :call-seq:
      #   new(vertices, mode, usage = :dynamic)
      #   new(format, vertices, mode, usage = :dynamic)
      #   new(attributes, mode)
      #
      # The first makes a mesh of vertices with a position, texture
      # coordinate, and color, and the second of vertices of a format of
      # your own; the third gathers attributes from Lota::Graphics::Buffer.
      #
      # [vertices] An Array with an Array of numbers for each vertex: for
      #   the first form its x and y, and optionally its texture
      #   coordinates s and t and its color's red, green, blue, and alpha
      #   from 0 to 1, which are 0, 0, and 1 when left out; for the second,
      #   the numbers of every attribute of the format, one after
      #   another. Or the Integer number of vertices, which start zeroed;
      #   or, for the second form, a Lota::Data of their bytes.
      # [format] An Array with a Hash for each attribute of a vertex, as
      #   Lota::Graphics::Buffer.new takes it, each with a +:format+ and a
      #   +:location+. LÖVE's older form, an Array of the attribute's name,
      #   data type, and component count, is read too, and prints
      #   LÖVE's deprecation notice.
      # [attributes] An Array with a Hash for each attribute: its
      #   +:buffer+ and its Integer +:location+, and optionally its
      #   +:name+, its +:step+ (+:pervertex+, the default, or
      #   +:perinstance+), its +:locationinbuffer+, its +:nameinbuffer+,
      #   and the Integer +:startindex+ in the buffer, counting from 1.
      # [mode] How the vertices make shapes: +:fan+, +:strip+,
      #   +:triangles+, or +:points+.
      # [usage] How often the vertices change: +:dynamic+ (the default),
      #   +:static+, or +:stream+.
      #
      # Raises TypeError for arguments of the wrong type, ArgumentError for
      # an unknown mode or usage, RuntimeError with LÖVE's message when no
      # window is open, and ThreadError off the main thread.
      #
      # === Examples
      #
      #   Lota::Graphics::Mesh.new(1000, :points)
      #   Lota::Graphics::Mesh.new([[0, 0, 0, 0, 1, 0, 0, 1], [32, 0], [0, 32]], :triangles, :static)
      #   Lota::Graphics::Mesh.new([{format: :floatvec2, location: 0, name: "VertexPosition"}], [[0, 0], [8, 0]], :strip)
      def self.new(first, second, third = nil, fourth = nil)
        unless first.is_a?(Array) || first.is_a?(Numeric)
          raise ArgumentError, "table or number expected"
        end

        location = caller_locations(1, 1)&.first
        where = location ? "#{location.path}:#{location.lineno}: " : ""
        attributes = buffer_attributes(first)
        native = if attributes
          Native::Graphics.new_mesh_from_buffers(attributes, name_of(second))
        elsif first.is_a?(Array) && vertices?(second)
          custom(first, second, third, fourth, where)
        else
          Native::Graphics.new_standard_mesh(first, name_of(second), (third.is_a?(Symbol) || third.is_a?(String)) ? EnumName.of(third) : nil)
        end
        GraphicsBuffer.__send__(:mark_deprecated_bindings, native, where)
        from_native(native)
      end

      # Whether +value+ is what newCustomMesh reads its vertices from, as
      # w_newMesh tells it by the type of argument 2: a table, a number, or
      # a Data.
      private_class_method def self.vertices?(value)
        value.is_a?(Array) || value.is_a?(Numeric) || value.is_a?(Lota::Data)
      end

      # A mode's name, which LÖVE requires to be a string. :nodoc:
      private_class_method def self.name_of(mode)
        return EnumName.of(mode) if mode.is_a?(Symbol) || mode.is_a?(String)

        raise TypeError, "wrong argument type #{mode.class} (expected Symbol)"
      end

      # luax_isbufferattributetable and luax_checkbufferattributetable
      # (wrap_Graphics.cpp:2208-2274): when +value+ is an Array whose first
      # Hash has a Buffer for its +:buffer+, every attribute of it for the
      # engine, as an Array of the buffer, location, name, step, location
      # in the buffer, name in the buffer, and start index; otherwise +nil+.
      private_class_method def self.buffer_attributes(value)
        return nil unless value.is_a?(Array)

        first = value.first
        return nil unless first.is_a?(Hash) && first[:buffer].is_a?(GraphicsBuffer)

        value.map do |attribute|
          raise TypeError, "wrong argument type #{attribute.class} (expected Hash)" unless attribute.is_a?(Hash)

          buffer = attribute[:buffer]
          raise TypeError, "wrong argument type #{buffer.class} (expected Lota::Graphics::GraphicsBuffer)" unless buffer.is_a?(GraphicsBuffer)

          step = attribute[:step]
          [
            buffer.__send__(:native),
            attribute[:location],
            attribute[:name]&.to_s,
            step && EnumName.of(step),
            attribute[:locationinbuffer],
            attribute[:nameinbuffer]&.to_s,
            attribute[:startindex],
          ]
        end
      end

      # newCustomMesh (wrap_Graphics.cpp:2052-2206), which reads a format
      # of declarations, or LÖVE's older arrays of an attribute's name,
      # data type, and component count.
      private_class_method def self.custom(format, vertices, mode, usage, where)
        raise ArgumentError, "table of tables expected" if format.empty?

        declarations = format.map.with_index(1) do |entry, index|
          (legacy_declaration?(entry) && entry.is_a?(Array)) ? legacy_declaration(entry) : GraphicsBuffer.__send__(:declaration, entry, index, true)
        end
        mark_legacy_format(format, where)
        Native::Graphics.new_custom_mesh([
          declarations,
          GraphicsBuffer.__send__(:native_content, vertices),
          name_of(mode),
          usage && EnumName.of(usage),
])
      end

      # Whether +entry+ is LÖVE's older array of a name, a data type, and
      # a component count: an Array, where the newer is a Hash.
      private_class_method def self.legacy_declaration?(entry)
        entry.is_a?(Array) && !entry.empty?
      end

      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
      # SPDX-License-Identifier: Zlib

      # The older format of an attribute, {name, datatype, components}
      # (wrap_Graphics.cpp:2078-2125), as a declaration.
      private_class_method def self.legacy_declaration(entry)
        name, type, components = entry
        type = type.to_s
        count = case components
        when Integer then components
        when Float then components.to_i
        else raise TypeError, "wrong argument type #{components.class} (expected Integer)"
        end
        format = legacy_format(type, count)
        unless format
          raise ArgumentError, "Invalid vertex data type '#{type}', expected one of: 'float', 'byte', 'unorm8', 'unorm16'"
        end

        [name.to_s, format, 0, nil]
      end

      # The data format a type and component count name.
      private_class_method def self.legacy_format(type, components)
        case type
        when "byte", "unorm8" then legacy_components(type, components, 4 => "unorm8vec4")
        when "unorm16" then legacy_components(type, components, 2 => "unorm16vec2", 4 => "unorm16vec4")
        when "float" then legacy_components(type, components, 1 => "float", 2 => "floatvec2", 3 => "floatvec3", 4 => "floatvec4")
        end
      end

      # The data format +formats+ names for +components+ of +type+, or the
      # RuntimeError LÖVE raises for a count the type has no format for.
      private_class_method def self.legacy_components(type, components, formats)
        formats.fetch(components) do
          raise "Invalid component count (#{components}) for vertex data type #{type}"
        end
      end

      # SPDX-SnippetEnd

      # The deprecation LÖVE marks for a format of older arrays
      # (wrap_Graphics.cpp:2127-2129).
      private_class_method def self.mark_legacy_format(format, where)
        return unless format.any? { |entry| legacy_declaration?(entry) }

        Deprecation.mark("vertex format array values in Lota::Graphics::Mesh.new", :custom, :replaced,
          "named table fields 'format' and 'location'", where:)
      end

      # Replaces vertices, matching Mesh:setVertices
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_setVertices). Its first
      # argument is itself an Array or a Data, so it stays a method rather
      # than a writer (rule 6 of doc/contributors/design/translation.md).
      #
      # [data] An Array of Arrays of numbers, each the numbers of every
      #   attribute of a vertex, or a Lota::Data of bytes.
      # [start] Integer vertex to start at, counting from 1; the first
      #   when left out.
      # [count] Integer number of vertices to copy; all of +data+ when
      #   left out.
      #
      # Raises RuntimeError with LÖVE's message for a start or count
      # outside the mesh, and TypeError for a value that is not a number.
      #
      # === Examples
      #
      #   mesh.set_vertices([[0, 0, 0, 0], [16, 0, 1, 0]])
      #   mesh.set_vertices([[8, 8, 0, 1]], 3) # the third vertex
      def set_vertices(data, start = nil, count = nil)
        @native.set_vertices([GraphicsBuffer.__send__(:native_content, data), start, count])
        nil
      end

      # Replaces one vertex, matching Mesh:setVertex
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_setVertex), whose
      # several values rule 6 of doc/contributors/design/translation.md makes
      # one Array.
      #
      # [arguments] The Integer index of the vertex, counting from 1,
      # followed by the numbers of its attributes, one after another or as
      # one Array.
      #
      # Raises RuntimeError with LÖVE's message for an index outside the
      # mesh, and TypeError for a value that is not a number.
      #
      # === Examples
      #
      #   mesh.vertex = 2, 32, 0, 1, 0, 1, 1, 1, 1
      #   mesh.vertex = 2, [32, 0, 1, 0, 1, 1, 1, 1]
      def vertex=(arguments)
        index, *row = arguments
        row = row.first if row.size == 1 && row.first.is_a?(Array)
        @native.set_vertex(index, row)
      end

      # The numbers of every attribute of a vertex, one after another,
      # matching Mesh:getVertex (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_getVertex), as an Array.
      #
      # [index] Integer index of the vertex, counting from 1.
      #
      # Raises RuntimeError with LÖVE's message for an index outside the
      # mesh.
      #
      # === Example
      #
      #   x, y, u, v, r, g, b, a = mesh.vertex(1)
      def vertex(index)
        @native.vertex(index)
      end

      # Replaces one attribute of one vertex, matching
      # Mesh:setVertexAttribute (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_setVertexAttribute), whose several values rule 6 of
      # doc/contributors/design/translation.md makes one Array.
      #
      # [arguments] The Integer index of the vertex and the Integer index
      # of the attribute in the format, each counting from 1, followed by
      # the attribute's numbers.
      #
      # Raises RuntimeError with LÖVE's message for an index outside the
      # mesh or its format.
      #
      # === Example
      #
      #   mesh.vertex_attribute = 4, 3, 1, 0, 1 # a purple fourth vertex
      def vertex_attribute=(arguments)
        @native.set_vertex_attribute(arguments)
      end

      # The numbers of one attribute of one vertex, as an Array, matching
      # Mesh:getVertexAttribute (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_getVertexAttribute).
      #
      # [vertex] Integer index of the vertex, counting from 1.
      # [attribute] Integer index of the attribute in the format, counting
      #   from 1.
      #
      # === Example
      #
      #   r, g, b, a = mesh.vertex_attribute(3, 3)
      def vertex_attribute(vertex, attribute)
        @native.vertex_attribute([vertex, attribute])
      end

      # The Integer number of vertices, matching Mesh:getVertexCount
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_getVertexCount).
      #
      # === Example
      #
      #   mesh.vertex_count # => 4
      def vertex_count
        @native.vertex_count
      end

      # The format of a vertex, as an Array of VertexFormat, one for each
      # attribute, matching Mesh:getVertexFormat
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_getVertexFormat).
      #
      # === Example
      #
      #   mesh.vertex_format.map(&:name) # => ["VertexPosition", "VertexTexCoord", "VertexColor"]
      def vertex_format
        @native.vertex_format.map do |name, location, format, arraylength, offset|
          VertexFormat.new(name:, location:, format: format.to_sym, arraylength:, offset:)
        end
      end

      # Turns an attribute on or off for drawing, matching
      # Mesh:setAttributeEnabled (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_setAttributeEnabled), whose two values rule 6 of
      # doc/contributors/design/translation.md makes one Array.
      #
      # [arguments] The attribute's String name or Integer binding
      #   location, and +true+ or +false+.
      #
      # Raises RuntimeError with LÖVE's message for an attribute the mesh
      # does not have, and TypeError for a flag that is not +true+ or
      # +false+.
      #
      # === Example
      #
      #   mesh.attribute_enabled = "VertexColor", false
      def attribute_enabled=(arguments)
        attribute, enable = arguments
        flag = case enable
        when true then true
        when false then false
        else raise TypeError, "wrong argument type #{enable.class} (expected true or false)"
        end
        @native.set_attribute_enabled(attribute, flag)
      end

      # Whether an attribute is used when drawing, matching
      # Mesh:isAttributeEnabled (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_isAttributeEnabled).
      #
      # [attribute] The attribute's String name or Integer binding location.
      #
      # Raises RuntimeError with LÖVE's message for an attribute the mesh
      # does not have.
      #
      # === Example
      #
      #   mesh.attribute_enabled?("VertexPosition") # => true
      def attribute_enabled?(attribute)
        @native.attribute_enabled?(attribute)
      end

      # Takes an attribute from another buffer or mesh, matching
      # Mesh:attachAttribute (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_attachAttribute).
      #
      # [attribute] The String name or Integer binding location the
      #   attribute takes in this mesh.
      # [source] The Lota::Graphics::GraphicsBuffer, or the Mesh with a vertex
      #   buffer of its own, that holds it.
      # [step] +:pervertex+ (the default) takes a value for each vertex,
      #   and +:perinstance+ one for each instance drawn.
      # [attach] The name or location it has in +source+; the same as
      #   +attribute+ when left out.
      # [startindex] Integer element of +source+ to start from, counting
      #   from 1.
      #
      # Raises RuntimeError with LÖVE's message for an attribute the
      # source lacks or a mesh with no vertex buffer, ArgumentError for an
      # unknown step, and TypeError for a source that is neither.
      #
      # === Example
      #
      #   mesh.attach_attribute("CustomValue1", other_mesh)
      def attach_attribute(attribute, source, step = nil, attach = nil, startindex = nil)
        native_source = (source.is_a?(GraphicsBuffer) || source.is_a?(Mesh)) ? source.native : source
        @native.attach_attribute(attribute, native_source, step && EnumName.of(step), attach, startindex)
      end

      # Stops using an attribute taken from another buffer, matching
      # Mesh:detachAttribute (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_detachAttribute).
      #
      # [name] The attribute's String name.
      #
      # Returns +true+ if it was detached, and +false+ for an attribute
      # that is one of the mesh's own, which cannot be detached.
      #
      # === Example
      #
      #   mesh.detach_attribute("CustomValue1") # => true
      def detach_attribute(name)
        @native.detach_attribute(name)
      end

      # The attributes attached to the mesh, as an Array, matching
      # Mesh:getAttachedAttributes (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_getAttachedAttributes). At the pinned commit LÖVE returns an
      # empty table, whatever is attached, because it sets each attribute's
      # table into itself rather than into the result, and so does this.
      #
      # === Example
      #
      #   mesh.attached_attributes # => []
      def attached_attributes
        @native.attached_attributes
      end

      # The Lota::Graphics::GraphicsBuffer that holds the vertices, matching
      # Mesh:getVertexBuffer (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_getVertexBuffer), or +nil+ for a mesh made from buffers.
      #
      # === Example
      #
      #   mesh.vertex_buffer.element_count # => 4
      def vertex_buffer
        native = @native.vertex_buffer
        native && GraphicsBuffer.__send__(:from_native, native)
      end

      # Sends changes to the vertices to the graphics card now, rather than
      # when the mesh is next drawn, matching Mesh:flush
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_flush).
      #
      # === Example
      #
      #   mesh.flush
      def flush
        @native.flush
      end

      # Sets the order the vertices are used in, matching Mesh:setVertexMap
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_setVertexMap). Its first
      # argument is itself an Array or a Data, so it stays a method rather
      # than a writer (rule 6 of doc/contributors/design/translation.md).
      #
      # [map] Integer vertex indices, counting from 1, as several
      #   arguments or one Array; or a Lota::Data of indices, then the
      #   Symbol type of them (+:uint16+ or +:uint32+), and optionally the
      #   Integer number of them; or nothing, or +nil+, for the default
      #   order.
      #
      # Raises ArgumentError for an unknown index type, and RuntimeError
      # with LÖVE's message for an index count outside the Data or an
      # index outside the mesh.
      #
      # === Examples
      #
      #   mesh.set_vertex_map(4, 1, 2, 3)
      #   mesh.set_vertex_map(index_data, :uint16)
      #   mesh.set_vertex_map
      def set_vertex_map(first = nil, *rest)
        if first.nil? && rest.empty?
          @native.clear_vertex_map
        elsif first.is_a?(Lota::Data)
          @native.set_vertex_map_data(first.native, EnumName.of(rest.fetch(0)), rest[1])
        else
          @native.set_vertex_map((first.is_a?(Array) && rest.empty?) ? first : [first, *rest])
        end
        nil
      end

      # The order the vertices are used in, as an Array of Integer
      # indices counting from 1, or +nil+ for the default order, matching
      # Mesh:getVertexMap (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_getVertexMap).
      #
      # === Example
      #
      #   mesh.vertex_map # => [4, 1, 2, 3]
      def vertex_map
        @native.vertex_map
      end

      # Sets the Lota::Graphics::GraphicsBuffer of indices that says which
      # vertices are used, matching Mesh:setIndexBuffer
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_setIndexBuffer), or
      # +nil+ for none.
      #
      # Raises TypeError for a buffer that is not a GraphicsBuffer, and
      # RuntimeError with LÖVE's message for one that is not an index buffer.
      #
      # === Example
      #
      #   mesh.index_buffer = indices
      def index_buffer=(buffer)
        raise TypeError, "wrong argument type #{buffer.class} (expected Lota::Graphics::GraphicsBuffer)" unless buffer.nil? || buffer.is_a?(GraphicsBuffer)

        @native.set_index_buffer(buffer&.native)
      end

      # The Lota::Graphics::GraphicsBuffer of indices, or +nil+, matching
      # Mesh:getIndexBuffer (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_getIndexBuffer).
      #
      # === Example
      #
      #   mesh.index_buffer # => nil
      def index_buffer
        native = @native.index_buffer
        native && GraphicsBuffer.__send__(:from_native, native)
      end

      # Sets the texture the mesh is drawn with, or +nil+ for none,
      # matching Mesh:setTexture (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_setTexture).
      #
      # Raises TypeError for a texture that is not a Texture.
      #
      # === Example
      #
      #   mesh.texture = image
      def texture=(texture)
        raise TypeError, "wrong argument type #{texture.class} (expected Lota::Graphics::Texture)" unless texture.nil? || texture.is_a?(Texture)

        @native.set_texture(texture&.native)
      end

      # The Lota::Graphics::Texture the mesh is drawn with, or +nil+,
      # matching Mesh:getTexture (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_getTexture).
      #
      # === Example
      #
      #   mesh.texture.width # => 256
      def texture
        native = @native.texture
        native && Texture.__send__(:from_native, native)
      end

      # Sets how the vertices make shapes, matching Mesh:setDrawMode
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_setDrawMode).
      #
      # [mode] +:fan+, +:strip+, +:triangles+, or +:points+.
      #
      # Raises ArgumentError for an unknown mode.
      #
      # === Example
      #
      #   mesh.draw_mode = :triangles
      def draw_mode=(mode)
        @native.set_draw_mode(EnumName.of(mode))
      end

      # How the vertices make shapes, a Symbol, matching Mesh:getDrawMode
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_getDrawMode).
      #
      # === Example
      #
      #   mesh.draw_mode # => :fan
      def draw_mode
        @native.draw_mode.to_sym
      end

      # Draws only some of the vertices, matching Mesh:setDrawRange
      # (src/modules/graphics/wrap_Mesh.cpp, w_Mesh_setDrawRange).
      #
      # [range] The Integer first vertex to draw, counting from 1, and the
      #   Integer number of vertices, as two values or an Array; or +nil+
      #   to draw every vertex again.
      #
      # Raises ArgumentError for any count of values but 2, and
      # RuntimeError with LÖVE's message for a range outside the mesh.
      #
      # === Examples
      #
      #   mesh.draw_range = 1, 10
      #   mesh.draw_range = nil
      def draw_range=(range)
        if range.nil?
          @native.set_draw_range
        else
          values = Array(range)
          raise ArgumentError, "wrong number of arguments (given #{values.size}, expected 2)" unless values.size == 2

          @native.set_draw_range(values.fetch(0), values.fetch(1))
        end
      end

      # The vertices drawn, as an Array of the first vertex, counting from
      # 1, and how many, or an empty Array when every vertex is drawn,
      # matching Mesh:getDrawRange (src/modules/graphics/wrap_Mesh.cpp,
      # w_Mesh_getDrawRange); a function that returns several values
      # returns an Array of all it returns (rule 4 of
      # doc/contributors/design/translation.md), so <tt>.first</tt> is +nil+
      # where Lua's first result is.
      #
      # === Examples
      #
      #   mesh.draw_range # => []
      #   mesh.draw_range = 1, 10
      #   mesh.draw_range # => [1, 10]
      def draw_range
        @native.draw_range
      end
    end
  end
end
