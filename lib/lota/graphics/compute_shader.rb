# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Lota
  module Graphics
    # Compiles compute shaders, matching love.graphics.newComputeShader.
    #
    # A compute shader runs on the graphics card without drawing: it reads
    # and writes buffers and textures, for work such as moving thousands of
    # particles. LÖVE has no ComputeShader class, newComputeShader makes a
    # Shader, so by rule 2 of doc/contributors/design/translation.md,
    # ComputeShader is a module whose new returns a Lota::Graphics::Shader and
    # whose <tt>===</tt> asks the shader whether it has a compute stage, as
    # Canvas === asks <tt>canvas?</tt>. Run one with
    # Lota::Graphics.dispatch_threadgroups.
    #
    # === Example
    #
    #   simulate = Lota::Graphics::ComputeShader.new(<<~GLSL)
    #     layout(local_size_x = 64) in;
    #     void computemain() {}
    #   GLSL
    #   Lota::Graphics.dispatch_threadgroups(simulate, 16)
    module ComputeShader
      # Compiles a compute shader, matching love.graphics.newComputeShader
      # (src/modules/graphics/wrap_Graphics.cpp, w_newComputeShader).
      #
      # [source] The GLSL source as a String, the name of a file in the
      #   game's folder that holds it, or a Lota::Filesystem::FileData.
      # [defines] As Lota::Graphics::Shader.new takes them.
      # [debugname] As Lota::Graphics::Shader.new takes it.
      # [write] As Lota::Graphics::Shader.new takes it.
      #
      # Raises what Lota::Graphics::Shader.new raises, and RuntimeError with
      # LÖVE's message where the renderer has no compute shaders.
      #
      # === Example
      #
      #   Lota::Graphics::ComputeShader.new("compute.glsl", debugname: "simulate")
      def self.new(source, defines: nil, debugname: nil, write: nil)
        Shader.__send__(:compute, source, caller_locations(1, 1)&.first, defines:, debugname:, write:)
      end

      # Whether +object+ is a Lota::Graphics::Shader with a compute stage.
      #
      # === Example
      #
      #   Lota::Graphics::ComputeShader === Lota::Graphics.shader # => false
      def self.===(object)
        case object
        when Shader then object.stage?(:compute)
        else false
        end
      end
    end
  end
end
