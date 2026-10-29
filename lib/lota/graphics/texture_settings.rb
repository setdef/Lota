# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # The settings a texture is made with, read from keyword arguments as
    # LÖVE reads its settings table, for Lota::Graphics::Texture.new and
    # the modules that make textures. :nodoc:
    #
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2006-2026 LOVE Development Team
    # SPDX-License-Identifier: Zlib
    module TextureSettings
      # luax_checktexturesettings (src/modules/graphics/wrap_Graphics.cpp:
      # 759-871): fills +settings+, a Native::TextureSettings, from
      # +options+, the keyword arguments, and returns whether they set a
      # DPI scale. +opt+ says whether the settings may be left out,
      # +check_type+ whether the type setting counts, +check_dimensions+
      # whether the width and height must be given, and +canvas+, when not
      # nil, makes a canvas or not whatever the settings say. A setting
      # name LÖVE does not know raises ArgumentError, as LÖVE raises.
      def self.read(settings, options, opt:, check_type:, check_dimensions:, canvas: nil)
        settings.canvas = canvas unless canvas.nil?
        return false if opt && options.empty?

        options.each_key { |name| Native::TextureSettings.check_name(name.to_s) }
        settings.canvas = flag(options[:canvas], settings.canvas) if canvas.nil?
        settings.debugname = string(options[:debugname], "debugname") unless options[:debugname].nil?
        settings.set_format(string(options[:format], "format")) unless options[:format].nil?
        settings.set_type(string(options[:type], "type")) if check_type && !options[:type].nil?
        read_dimensions(settings, options, check_dimensions)
        read_mipmaps(settings, options)
        settings.linear = flag(options[:linear], settings.linear)
        settings.msaa = integer(options[:msaa], settings.msaa)
        settings.computewrite = flag(options[:computewrite], settings.computewrite)
        read_view_formats(settings, options[:viewformats]) unless options[:viewformats].nil?
        settings.readable = boolean(options[:readable], "readable") unless options[:readable].nil?
        read_dpi_scale(settings, options[:dpiscale])
      end

      # The width, height, and, for an array or volume texture, the layer
      # count (wrap_Graphics.cpp:801-814).
      private_class_method def self.read_dimensions(settings, options, check)
        layered = %w[array volume].include?(settings.type)
        if check
          settings.width = check_integer(options[:width], "width")
          settings.height = check_integer(options[:height], "height")
          settings.layers = check_integer(options[:layers], "layers") if layered
        else
          settings.width = integer(options[:width], settings.width)
          settings.height = integer(options[:height], settings.height)
          settings.layers = integer(options[:layers], settings.layers) if layered
        end
      end

      # mipmaps, true for "manual" and false for "none" or a mode's name,
      # and mipmapcount (wrap_Graphics.cpp:816-832).
      private_class_method def self.read_mipmaps(settings, options)
        case (mipmaps = options[:mipmaps])
        when nil then nil
        when true, false then settings.set_mipmaps(mipmaps ? "manual" : "none")
        else settings.set_mipmaps(string(mipmaps, "mipmaps"))
        end
        settings.mipmapcount = check_integer(options[:mipmapcount], "mipmapcount") unless options[:mipmapcount].nil?
      end

      # viewformats, an Array of pixel formats (wrap_Graphics.cpp:837-853).
      private_class_method def self.read_view_formats(settings, formats)
        raise ArgumentError, "expected field 'viewformats' to be a table type" unless formats.is_a?(Array)

        formats.each { |format| settings.add_view_format(string(format, "viewformats")) }
      end

      # dpiscale, read only when it is a number (wrap_Graphics.cpp:860-866).
      private_class_method def self.read_dpi_scale(settings, dpiscale)
        return false unless dpiscale.is_a?(Integer) || dpiscale.is_a?(Float)

        settings.dpiscale = dpiscale.to_f
        true
      end

      # luax_boolflag (src/common/runtime.cpp:303-315): the default when
      # nil, the value's truth otherwise.
      private_class_method def self.flag(value, default)
        value.nil? ? default : !!value
      end

      # luax_intflag (src/common/runtime.cpp:317-329): the default unless a
      # number.
      private_class_method def self.integer(value, default)
        (value.is_a?(Integer) || value.is_a?(Float)) ? value.to_i : default
      end

      # luax_checkintflag (src/common/runtime.cpp:362-377): a number, or
      # LÖVE's error for a missing one.
      private_class_method def self.check_integer(value, name)
        raise ArgumentError, "expected integer field '#{name}' in table" unless value.is_a?(Integer) || value.is_a?(Float)

        value.to_i
      end

      # luaL_checkstring of a name: a Symbol or a String.
      private_class_method def self.string(value, name)
        case value
        when Symbol, String then EnumName.of(value)
        else raise TypeError, "wrong argument type #{value.class} for #{name} (expected Symbol or String)"
        end
      end

      # luax_checkboolean: true or false.
      private_class_method def self.boolean(value, name)
        return value if value == true || value == false

        raise TypeError, "wrong argument type #{value.class} for #{name} (expected true or false)"
      end

      # What Lota::Graphics passes the engine for each image getImageData
      # reads (wrap_Graphics.cpp:714-745): an ImageData's engine object as
      # it is, and a file name, a FileData, or other Data as the engine's
      # Data, which it decodes, with an Array, and an Array of Arrays, of
      # them kept as Arrays.
      def self.images(source)
        case source
        when Array then source.map { |item| item.is_a?(Array) ? item.map { |image| image(image) } : image(item) }
        else image(source)
        end
      end

      # One image's engine object, as images makes it.
      private_class_method def self.image(source)
        case source
        when String then Native::Filesystem.file_data(source)
        when Lota::Image::ImageData, Lota::Data then source.native
        else
          raise TypeError,
            "wrong argument type #{source.class} (expected String, Lota::Filesystem::FileData, or " \
              "Lota::Image::ImageData)"
        end
      end

      # The width, height, and layer count a texture's size starts with,
      # which w_newTexture and its kin read where their first argument is a
      # number (wrap_Graphics.cpp:921-937 and 1094-1100), each as
      # luaL_checkinteger reads it, in +settings+: +count+ is how many they
      # take, and a layer count makes the texture +layered+, unless it is
      # nil, when it must be given.
      def self.read_size(settings, arguments, count, layered)
        check_count(arguments, count)
        width, height, layers = arguments
        settings.width = size(width, "width")
        settings.height = size(height, "height")
        return unless count.cover?(3)
        return if layers.nil? && layered

        settings.layers = size(layers, "layers")
        settings.set_type(layered) if layered
      end

      # An ArgumentError unless +arguments+ holds as many as +count+ allows.
      def self.check_count(arguments, count)
        return if count.cover?(arguments.size)

        expected = (count.min == count.max) ? count.min.to_s : "#{count.min}..#{count.max}"
        raise ArgumentError, "wrong number of arguments (given #{arguments.size}, expected #{expected})"
      end

      # A number a texture's size starts with, as luaL_checkinteger reads
      # it, or TypeError.
      def self.size(value, name)
        case value
        when Integer, Float then value.to_i
        else raise TypeError, "wrong argument type #{value.class} for #{name} (expected Integer)"
        end
      end

      # Whether +value+ is a number, as lua_type(L, i) == LUA_TNUMBER asks.
      def self.number?(value)
        value.is_a?(Integer) || value.is_a?(Float)
      end
    end
    # SPDX-SnippetEnd
  end
end
