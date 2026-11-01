# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "native_helper"
require_relative "../engine_helper"

# Lota::Graphics::Shader beyond what Lövetest's tests for it check
# (test/lovetest/tests/graphics.rb): the sources and options
# w_getShaderSource reads (wrap_Graphics.cpp:1481-1607), the message
# _transformGLSLErrorMessages rewrites (wrap_Graphics.lua:99-132), the
# deprecated uses w_newShader marks, and the forms and errors of
# Shader:send and Shader:sendColor (wrap_Shader.cpp:50-477), each seen in
# the pixel a shader draws with what it was sent. Shader#send is called
# through __send__, as RuboCop's Style/Send takes a call of send for
# Ruby's own Object#send.
class ShaderTest < Minitest::Test
  def setup
    EngineHelper.open_window
    Lota::Graphics.color = 1, 1, 1, 1
  end

  # A shader whose every pixel is +color+, a GLSL vec4 expression of the
  # uniforms +declarations+ declares.
  def shader_of(declarations, color)
    Lota::Graphics::Shader.new(<<~GLSL)
      #{declarations}
      vec4 effect(vec4 c, Image tex, vec2 tc, vec2 pc) { return #{color}; }
    GLSL
  end

  # The color +shader+ draws a pixel in, from 0 to 1, with no blending,
  # so that an alpha below 1 changes nothing else.
  def drawn(shader)
    canvas = Lota::Graphics::Canvas.new(1, 1)
    Lota::Graphics.push(:all)
    Lota::Graphics.blend_mode = :none
    Lota::Graphics.canvas = canvas
    Lota::Graphics.shader = shader
    Lota::Graphics.rectangle(:fill, 0, 0, 1, 1)
    Lota::Graphics.pop
    Lota::Graphics.readback_texture(canvas).pixel(0, 0)
  end

  def assert_color(expected, actual)
    expected.zip(actual).each { |want, got| assert_in_delta want, got, 1.0 / 255 }
  end

  def test_the_shader_set_is_the_same_object_until_reset_with_nil
    shader = shader_of("", "vec4(1.0)")
    Lota::Graphics.shader = shader

    assert_same shader, Lota::Graphics.shader
    Lota::Graphics.shader = nil

    assert_nil Lota::Graphics.shader
    assert_raises(TypeError) { Lota::Graphics.shader = :shader }
  end

  # w_getShaderSource reads a file the source names, and refuses a name
  # that looks like a file's but names none (lines 1504-1528).
  def test_a_source_can_be_a_file_or_a_file_data
    code = "vec4 effect(vec4 c, Image t, vec2 tc, vec2 pc) { return vec4(0.0, 1.0, 0.0, 1.0); }\n"
    in_identity("lota-shader-test") do
      Lota::Filesystem.write("green.glsl", code)

      assert_color [0, 1, 0, 1], drawn(Lota::Graphics::Shader.new("green.glsl"))
    ensure
      Lota::Filesystem.remove("green.glsl")
    end
    missing = assert_raises(RuntimeError) { Lota::Graphics::Shader.new("missing.glsl") }

    assert_color [0, 1, 0, 1], drawn(Lota::Graphics::Shader.new(Lota::Filesystem::FileData.new(code, "x.glsl")))
    assert_equal "Could not open file missing.glsl. Does not exist.", missing.message
    assert_raises(TypeError) { Lota::Graphics::Shader.new(nil) }
    assert_raises(TypeError) { Lota::Graphics::Shader.new(1) }
  end

  # Defines take a String, a number as Lua writes it, or a boolean as 1 or
  # 0, and an Array's names define nothing (lines 1547-1582).
  def test_defines_are_set_before_the_source
    defined = <<~GLSL
      #if LEVEL == 2 && ON == 1 && OFF == 0 && TWO == 2 && defined(NAMED)
      #{effect}
      #else
      #error a define is missing
      #endif
    GLSL
    defines = { :LEVEL => 2.0, "ON" => true, :OFF => false, :TWO => 2, :NAMED => "yes" }
    bare = "#ifndef BARE\n#error BARE is not defined\n#endif\n#{effect}"

    assert_equal [true], Lota::Graphics.validate_shader(false, defined, defines:)
    assert_equal "Shader", Lota::Graphics::Shader.new(defined, defines:).object_type
    assert_equal false, Lota::Graphics.validate_shader(false, defined, defines: defines.merge(LEVEL: 2.5)).first
    assert_equal [true], Lota::Graphics.validate_shader(false, bare, defines: ["BARE"])
    assert_equal false, Lota::Graphics.validate_shader(false, bare).first
    assert_raises(ArgumentError) { Lota::Graphics::Shader.new(effect, defines: { 1 => "x" }) }
    assert_raises(ArgumentError) { Lota::Graphics::Shader.new(effect, defines: { "X" => nil }) }
    assert_raises(ArgumentError) { Lota::Graphics::Shader.new(effect, defines: "X") }
    assert_raises(TypeError) { Lota::Graphics::Shader.new(effect, debugname: 1) }
  end

  def effect
    "vec4 effect(vec4 c, Image tex, vec2 tc, vec2 pc) { return c; }\n"
  end

  def test_validate_shader_returns_true_alone_or_false_and_the_message
    assert_equal [true], Lota::Graphics.validate_shader(false, effect)
    ok, message = Lota::Graphics.validate_shader(false, "#{effect}nonsense")

    assert_equal false, ok
    assert_kind_of String, message
    assert_raises(TypeError) { Lota::Graphics.validate_shader(nil, effect) }
  end

  # w_newShader raises the message _transformGLSLErrorMessages rewrites,
  # from glslang's, which LÖVE checks every shader with before the driver
  # compiles it, so it reads the same on every renderer.
  def test_a_shader_that_does_not_compile_raises_its_lines
    error = assert_raises(RuntimeError) { Lota::Graphics::Shader.new("#{effect}nonsense") }

    assert_match(/\AError validating pixel shader code:\nLine 2: ERROR: /, error.message)
  end

  # Each driver's line format, as _transformGLSLErrorMessages reads it.
  def test_compile_errors_are_rewritten_from_each_drivers_format
    transform = -> (message) { Lota::Graphics::Shader.__send__(:transform_glsl_error_messages, message) }
    nvidia = "Cannot compile pixel shader code:\n0(12) : error C0000: syntax error, unexpected '}'"
    amd = "Cannot compile vertex shader code:\nERROR: 0:7: error(#132) Syntax error: 'x' parse error"
    apple = "Error validating pixel shader code:\nERROR: 0:3: Use of undeclared identifier 'foo'\nERROR: 1 compilation errors."

    assert_equal "Cannot compile pixel shader code:\nLine 12: error: syntax error, unexpected '}'", transform.(nvidia)
    assert_equal "Cannot compile vertex shader code:\nLine 7: error: Syntax error: 'x' parse error", transform.(amd)
    assert_equal "Error validating pixel shader code:\nLine 3: ERROR: Use of undeclared identifier 'foo'\n" \
      "ERROR: 1 compilation errors.", transform.(apple)
    assert_equal "Cannot compile pixel shader code:\nunknown", transform.("Cannot compile pixel shader code:\nunknown")
    assert_equal "Something else", transform.("Something else")
  end

  def test_texture2d_is_marked_deprecated_where_the_shader_was_made
    output = Lota::Deprecation.output?
    Lota::Deprecation.output = true
    out, = capture_io do
      Lota::Graphics::Shader.new("vec4 effect(vec4 c, Image t, vec2 tc, vec2 pc) { return texture2D(t, tc); }\n")
    end

    assert_match(/#{Regexp.escape(__FILE__)}:\d+: Using deprecated texture2D\(\) or texture3D\(\) or textureCube\(\) /, out)
    assert_includes out, "(replaced by texture() function calls)"
  ensure
    capture_io { Lota::Deprecation.output = output }
  end

  # A matrix is a flat Array or one of rows, row-major unless the layout
  # says column (wrap_Shader.cpp:160-269).
  def test_a_matrix_is_read_in_rows_unless_sent_in_columns
    shader = shader_of("uniform mat2 m;", "vec4(m[0][0], m[1][0], m[0][1], 1.0)")
    shader.__send__(:send, "m", [0.2, 0.4, 0.6, 0.8])

    assert_color [0.2, 0.4, 0.6, 1], drawn(shader)
    shader.__send__(:send, "m", [[0.2, 0.4], [0.6, 0.8]])

    assert_color [0.2, 0.4, 0.6, 1], drawn(shader)
    shader.__send__(:send, "m", :column, [0.2, 0.4, 0.6, 0.8])

    assert_color [0.2, 0.6, 0.4, 1], drawn(shader)
    shader.__send__(:send, "m", :column, [[0.2, 0.4], [0.6, 0.8]])

    assert_color [0.2, 0.6, 0.4, 1], drawn(shader)
    assert_raises(ArgumentError) { shader.__send__(:send, "m", :diagonal, [0, 0, 0, 0]) }
    assert_raises(TypeError) { shader.__send__(:send, "m", 1) }
  end

  def test_a_mat4_can_be_a_transform
    shader = shader_of("uniform mat4 m;", "vec4(m[3][0], m[3][1], 0.0, 1.0)")
    transform = Lota::Math::Transform.new
    transform.translate(0.2, 0.6)
    shader.__send__(:send, "m", transform)

    assert_color [0.2, 0.6, 0, 1], drawn(shader)
  end

  # A Data sends its bytes, a matrix's transposed from rows
  # (wrap_Shader.cpp:330-441).
  def test_a_data_sends_its_bytes
    bytes = [0.2, 0.4, 0.6, 0.8].pack("f*")
    data = Lota::Image::ImageData.new(1, 1, :rgba32f, bytes)
    matrix = shader_of("uniform mat2 m;", "vec4(m[0][0], m[1][0], m[0][1], 1.0)")
    vector = shader_of("uniform vec4 v;", "v")
    matrix.__send__(:send, "m", data)

    assert_color [0.2, 0.4, 0.6, 1], drawn(matrix)
    matrix.__send__(:send, "m", :column, data)

    assert_color [0.2, 0.6, 0.4, 1], drawn(matrix)
    matrix.__send__(:send, "m", data, :column)

    assert_color [0.2, 0.6, 0.4, 1], drawn(matrix)
    vector.__send__(:send, "v", data)

    assert_color [0.2, 0.4, 0.6, 0.8], drawn(vector)
    assert_equal "Offset cannot be negative.", assert_raises(RuntimeError) { vector.__send__(:send, "v", data, -1) }.message
    assert_equal "Size must be greater than 0.", assert_raises(RuntimeError) { vector.__send__(:send, "v", data, 0, 0) }.message
    assert_equal "Size (8) must be a multiple of the uniform's size in bytes (16).",
      assert_raises(RuntimeError) { vector.__send__(:send, "v", data, 0, 8) }.message
  end

  def test_numbers_and_booleans_go_to_their_types
    ints = shader_of("#pragma language glsl3\nuniform int i; uniform uint u; uniform bvec2 b;",
      "vec4(float(i) / 4.0, float(u) / 4.0, b.x ? 1.0 : 0.0, b.y ? 1.0 : 0.0)")
    ints.__send__(:send, "i", 1)
    ints.__send__(:send, "u", 3)
    ints.__send__(:send, "b", [true, false])

    assert_color [0.25, 0.75, 1, 0], drawn(ints)
    assert_raises(TypeError) { ints.__send__(:send, "b", [1, 0]) }
    assert_raises(TypeError) { ints.__send__(:send, "i", "1") }
  end

  # sendColor clamps each component (luax_checknumberclamped01) and
  # returns true; it takes only a vec3 or a vec4.
  def test_send_color_clamps_its_components
    shader = shader_of("uniform vec4 tint; uniform float f;", "tint * f")
    shader.__send__(:send, "f", 1)

    assert_equal true, shader.send_color("tint", [2, -1, 0.5, 1])
    assert_color [1, 0, 0.5, 1], drawn(shader)
    error = assert_raises(RuntimeError) { shader.send_color("f", [1, 1, 1]) }

    assert_equal "Lota::Graphics::Shader#send_color can only be used with vec3 or vec4 uniforms.", error.message
  end

  def test_a_uniform_the_shader_does_not_use_is_an_error
    shader = shader_of("uniform float unused;", "vec4(1.0)")
    error = assert_raises(RuntimeError) { shader.__send__(:send, "unused", 1) }

    assert_equal "Shader uniform 'unused' does not exist.\nA common error is to define but not use the variable.",
      error.message
    assert_raises(TypeError) { shader_of("uniform Image t;", "Texel(t, vec2(0.0))").__send__(:send, "t", 1) }
  end

  def test_stages_and_the_thread_group_size_of_a_shader_with_no_compute_stage
    shader = shader_of("", "vec4(1.0)")

    assert_equal [true, true, false], %i[vertex pixel compute].map { |stage| shader.stage?(stage) }
    assert_equal [nil], shader.local_threadgroup_size
    assert_nil shader.debug_name
    assert_equal "Shader", shader.object_type
    assert_raises(ArgumentError) { shader.stage?(:geometry) }
  end

  private def in_identity(identity)
    previous = Lota::Filesystem.identity
    Lota::Filesystem.identity = identity
    yield
  ensure
    Lota::Filesystem.identity = previous
  end
end
